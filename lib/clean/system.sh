#!/bin/bash
# System-Level Cleanup Module
# Deep system cleanup (requires sudo) and Time Machine failed backups

set -euo pipefail

# Deep system cleanup (requires sudo)
clean_deep_system() {
    # Clean old system caches
    safe_sudo_find_delete "/Library/Caches" "*.cache" "$MOLE_TEMP_FILE_AGE_DAYS" "f" || true
    safe_sudo_find_delete "/Library/Caches" "*.tmp" "$MOLE_TEMP_FILE_AGE_DAYS" "f" || true
    safe_sudo_find_delete "/Library/Caches" "*.log" "$MOLE_LOG_AGE_DAYS" "f" || true

    # Clean temp files - use real paths (macOS /tmp is symlink to /private/tmp)
    local tmp_cleaned=0
    safe_sudo_find_delete "/private/tmp" "*" "${MOLE_TEMP_FILE_AGE_DAYS}" "f" && tmp_cleaned=1 || true
    safe_sudo_find_delete "/private/var/tmp" "*" "${MOLE_TEMP_FILE_AGE_DAYS}" "f" && tmp_cleaned=1 || true
    [[ $tmp_cleaned -eq 1 ]] && log_success "System temp files"

    # Clean crash reports
    safe_sudo_find_delete "/Library/Logs/DiagnosticReports" "*" "$MOLE_CRASH_REPORT_AGE_DAYS" "f" || true
    log_success "System crash reports"

    # Clean system logs - use real path (macOS /var is symlink to /private/var)
    safe_sudo_find_delete "/private/var/log" "*.log" "$MOLE_LOG_AGE_DAYS" "f" || true
    safe_sudo_find_delete "/private/var/log" "*.gz" "$MOLE_LOG_AGE_DAYS" "f" || true
    log_success "System logs"

    # Clean Library Updates safely - skip if SIP is enabled to avoid error messages
    # SIP-protected files in /Library/Updates cannot be deleted even with sudo
    if [[ -d "/Library/Updates" && ! -L "/Library/Updates" ]]; then
        if is_sip_enabled; then
            # SIP is enabled, skip /Library/Updates entirely to avoid error messages
            # These files are system-protected and cannot be removed
            : # No-op, silently skip
        else
            # SIP is disabled, attempt cleanup with restricted flag check
            local updates_cleaned=0
            while IFS= read -r -d '' item; do
                # Skip system-protected files (restricted flag)
                local item_flags
                item_flags=$(command stat -f%Sf "$item" 2> /dev/null || echo "")
                if [[ "$item_flags" == *"restricted"* ]]; then
                    continue
                fi

                if safe_sudo_remove "$item"; then
                    ((updates_cleaned++))
                fi
            done < <(find /Library/Updates -mindepth 1 -maxdepth 1 -print0 2> /dev/null || true)
            [[ $updates_cleaned -gt 0 ]] && log_success "System library updates"
        fi
    fi

    # Clean orphaned cask records (delegated to clean_brew module)
    clean_orphaned_casks

    # Clean macOS Install Data (system upgrade leftovers)
    # Only remove if older than 30 days to ensure system stability
    if [[ -d "/macOS Install Data" ]]; then
        local mtime=$(get_file_mtime "/macOS Install Data")
        local age_days=$((($(date +%s) - mtime) / 86400))
        
        debug_log "Found macOS Install Data (age: ${age_days} days)"
        
        if [[ $age_days -ge 30 ]]; then
            local size_kb=$(get_path_size_kb "/macOS Install Data")
            if [[ -n "$size_kb" && "$size_kb" -gt 0 ]]; then
                local size_human=$(bytes_to_human "$((size_kb * 1024))")
                debug_log "Cleaning macOS Install Data: $size_human (${age_days} days old)"
                
                if safe_sudo_remove "/macOS Install Data"; then
                    log_success "macOS Install Data ($size_human)"
                fi
            fi
        else
            debug_log "Keeping macOS Install Data (only ${age_days} days old, needs 30+)"
        fi
    fi

    # Clean browser code signature caches
    # These are regenerated automatically when needed
    local code_sign_cleaned=0
    while IFS= read -r -d '' cache_dir; do
        debug_log "Found code sign cache: $cache_dir"
        if safe_remove "$cache_dir" true; then
            ((code_sign_cleaned++))
        fi
    done < <(find /private/var/folders -type d -name "*.code_sign_clone" -path "*/X/*" -print0 2>/dev/null || true)
    
    [[ $code_sign_cleaned -gt 0 ]] && log_success "Browser code signature caches ($code_sign_cleaned items)"

    # Clean system diagnostics logs
    safe_sudo_find_delete "/private/var/db/diagnostics/Special" "*" "$MOLE_LOG_AGE_DAYS" "f" || true
    safe_sudo_find_delete "/private/var/db/diagnostics/Persist" "*" "$MOLE_LOG_AGE_DAYS" "f" || true
    safe_sudo_find_delete "/private/var/db/DiagnosticPipeline" "*" "$MOLE_LOG_AGE_DAYS" "f" || true
    log_success "System diagnostic logs"

    # Clean power logs
    safe_sudo_find_delete "/private/var/db/powerlog" "*" "$MOLE_LOG_AGE_DAYS" "f" || true
    log_success "Power logs"
}

# Clean Time Machine failed backups
clean_time_machine_failed_backups() {
    local tm_cleaned=0

    # Check if Time Machine is configured
    if command -v tmutil > /dev/null 2>&1; then
        if tmutil destinationinfo 2>&1 | grep -q "No destinations configured"; then
            echo -e "  ${GREEN}${ICON_SUCCESS}${NC} No failed Time Machine backups found"
            return 0
        fi
    fi

    if [[ ! -d "/Volumes" ]]; then
        echo -e "  ${GREEN}${ICON_SUCCESS}${NC} No failed Time Machine backups found"
        return 0
    fi

    # Skip if backup is running
    if pgrep -x "backupd" > /dev/null 2>&1; then
        echo -e "  ${YELLOW}!${NC} Time Machine backup in progress, skipping cleanup"
        return 0
    fi

    for volume in /Volumes/*; do
        [[ -d "$volume" ]] || continue

        # Skip system and network volumes
        [[ "$volume" == "/Volumes/MacintoshHD" || "$volume" == "/" ]] && continue

        # Skip if volume is a symlink (security check)
        [[ -L "$volume" ]] && continue

        # Check if this is a Time Machine destination
        if command -v tmutil > /dev/null 2>&1; then
            if ! tmutil destinationinfo 2> /dev/null | grep -q "$(basename "$volume")"; then
                continue
            fi
        fi

        local fs_type=$(command df -T "$volume" 2> /dev/null | tail -1 | awk '{print $2}')
        case "$fs_type" in
            nfs | smbfs | afpfs | cifs | webdav) continue ;;
        esac

        # HFS+ style backups (Backups.backupdb)
        local backupdb_dir="$volume/Backups.backupdb"
        if [[ -d "$backupdb_dir" ]]; then
            while IFS= read -r inprogress_file; do
                [[ -d "$inprogress_file" ]] || continue

                # Only delete old failed backups (safety window)
                local file_mtime=$(get_file_mtime "$inprogress_file")
                local current_time=$(date +%s)
                local hours_old=$(((current_time - file_mtime) / 3600))

                if [[ $hours_old -lt $MOLE_TM_BACKUP_SAFE_HOURS ]]; then
                    continue
                fi

                local size_kb=$(get_path_size_kb "$inprogress_file")
                [[ "$size_kb" -le 0 ]] && continue

                local backup_name=$(basename "$inprogress_file")
                local size_human=$(bytes_to_human "$((size_kb * 1024))")

                if [[ "$DRY_RUN" == "true" ]]; then
                    echo -e "  ${YELLOW}→${NC} Failed backup: $backup_name ${YELLOW}($size_human dry)${NC}"
                    ((tm_cleaned++))
                    note_activity
                    continue
                fi

                # Real deletion
                if ! command -v tmutil > /dev/null 2>&1; then
                    echo -e "  ${YELLOW}!${NC} tmutil not available, skipping: $backup_name"
                    continue
                fi

                if tmutil delete "$inprogress_file" 2> /dev/null; then
                    echo -e "  ${GREEN}${ICON_SUCCESS}${NC} Failed backup: $backup_name ${GREEN}($size_human)${NC}"
                    ((tm_cleaned++))
                    ((files_cleaned++))
                    ((total_size_cleaned += size_kb))
                    ((total_items++))
                    note_activity
                else
                    echo -e "  ${YELLOW}!${NC} Could not delete: $backup_name (try manually with sudo)"
                fi
            done < <(run_with_timeout 15 find "$backupdb_dir" -maxdepth 3 -type d \( -name "*.inProgress" -o -name "*.inprogress" \) 2> /dev/null || true)
        fi

        # APFS style backups (.backupbundle or .sparsebundle)
        for bundle in "$volume"/*.backupbundle "$volume"/*.sparsebundle; do
            [[ -e "$bundle" ]] || continue
            [[ -d "$bundle" ]] || continue

            # Check if bundle is mounted
            local bundle_name=$(basename "$bundle")
            local mounted_path=$(hdiutil info 2> /dev/null | grep -A 5 "image-path.*$bundle_name" | grep "/Volumes/" | awk '{print $1}' | head -1 || echo "")

            if [[ -n "$mounted_path" && -d "$mounted_path" ]]; then
                while IFS= read -r inprogress_file; do
                    [[ -d "$inprogress_file" ]] || continue

                    # Only delete old failed backups (safety window)
                    local file_mtime=$(get_file_mtime "$inprogress_file")
                    local current_time=$(date +%s)
                    local hours_old=$(((current_time - file_mtime) / 3600))

                    if [[ $hours_old -lt $MOLE_TM_BACKUP_SAFE_HOURS ]]; then
                        continue
                    fi

                    local size_kb=$(get_path_size_kb "$inprogress_file")
                    [[ "$size_kb" -le 0 ]] && continue

                    local backup_name=$(basename "$inprogress_file")
                    local size_human=$(bytes_to_human "$((size_kb * 1024))")

                    if [[ "$DRY_RUN" == "true" ]]; then
                        echo -e "  ${YELLOW}→${NC} Failed APFS backup in $bundle_name: $backup_name ${YELLOW}($size_human dry)${NC}"
                        ((tm_cleaned++))
                        note_activity
                        continue
                    fi

                    # Real deletion
                    if ! command -v tmutil > /dev/null 2>&1; then
                        continue
                    fi

                    if tmutil delete "$inprogress_file" 2> /dev/null; then
                        echo -e "  ${GREEN}${ICON_SUCCESS}${NC} Failed APFS backup in $bundle_name: $backup_name ${GREEN}($size_human)${NC}"
                        ((tm_cleaned++))
                        ((files_cleaned++))
                        ((total_size_cleaned += size_kb))
                        ((total_items++))
                        note_activity
                    else
                        echo -e "  ${YELLOW}!${NC} Could not delete from bundle: $backup_name"
                    fi
                done < <(run_with_timeout 15 find "$mounted_path" -maxdepth 3 -type d \( -name "*.inProgress" -o -name "*.inprogress" \) 2> /dev/null || true)
            fi
        done
    done

    if [[ $tm_cleaned -eq 0 ]]; then
        echo -e "  ${GREEN}${ICON_SUCCESS}${NC} No failed Time Machine backups found"
    fi
}
