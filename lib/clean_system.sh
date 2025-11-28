#!/bin/bash
# System-Level Cleanup Module
# Deep system cleanup (requires sudo) and Time Machine failed backups

set -euo pipefail

# Deep system cleanup (requires sudo)
# Env: DRY_RUN, TEMP_FILE_AGE_DAYS
clean_deep_system() {
    # Clean system caches safely (only old files)
    sudo find /Library/Caches -name "*.cache" -mtime +7 -delete 2> /dev/null || true
    sudo find /Library/Caches -name "*.tmp" -mtime +7 -delete 2> /dev/null || true
    sudo find /Library/Caches -type f -name "*.log" -mtime +30 -delete 2> /dev/null || true

    # Clean old temp files only
    local tmp_cleaned=0
    local tmp_count=$(sudo find /tmp -type f -mtime +${TEMP_FILE_AGE_DAYS} 2> /dev/null | wc -l | tr -d ' ')
    if [[ "$tmp_count" -gt 0 ]]; then
        sudo find /tmp -type f -mtime +${TEMP_FILE_AGE_DAYS} -delete 2> /dev/null || true
        tmp_cleaned=1
    fi
    local var_tmp_count=$(sudo find /var/tmp -type f -mtime +${TEMP_FILE_AGE_DAYS} 2> /dev/null | wc -l | tr -d ' ')
    if [[ "$var_tmp_count" -gt 0 ]]; then
        sudo find /var/tmp -type f -mtime +${TEMP_FILE_AGE_DAYS} -delete 2> /dev/null || true
        tmp_cleaned=1
    fi
    [[ $tmp_cleaned -eq 1 ]] && log_success "Old system temp files (${TEMP_FILE_AGE_DAYS}+ days)"

    # Clean system crash reports and diagnostics
    sudo find /Library/Logs/DiagnosticReports -type f -mtime +30 -delete 2> /dev/null || true
    sudo find /Library/Logs/CrashReporter -type f -mtime +30 -delete 2> /dev/null || true
    log_success "Old system crash reports (30+ days)"

    # Clean old system logs
    sudo find /var/log -name "*.log" -type f -mtime +30 -delete 2> /dev/null || true
    sudo find /var/log -name "*.gz" -type f -mtime +30 -delete 2> /dev/null || true
    log_success "Old system logs (30+ days)"

    sudo rm -rf /Library/Updates/* 2> /dev/null || true
    log_success "System library caches and updates"

    # Clean orphaned cask records (delegated to clean_brew module)
    clean_orphaned_casks
}

# Clean Time Machine failed backups
# Env: DRY_RUN
# Globals: files_cleaned, total_size_cleaned, total_items (modified if not DRY_RUN)
clean_time_machine_failed_backups() {
    local tm_cleaned=0

    # Check all mounted volumes
    if [[ ! -d "/Volumes" ]]; then
        echo -e "  ${GREEN}${ICON_SUCCESS}${NC} No failed Time Machine backups found"
        return 0
    fi

    for volume in /Volumes/*; do
        [[ -d "$volume" ]] || continue

        # Skip system and network volumes
        [[ "$volume" == "/Volumes/MacintoshHD" || "$volume" == "/" ]] && continue
        local fs_type=$(df -T "$volume" 2> /dev/null | tail -1 | awk '{print $2}')
        case "$fs_type" in
            nfs | smbfs | afpfs | cifs | webdav) continue ;;
        esac

        # HFS+ style backups (Backups.backupdb)
        local backupdb_dir="$volume/Backups.backupdb"
        if [[ -d "$backupdb_dir" ]]; then
            while IFS= read -r inprogress_file; do
                [[ -d "$inprogress_file" ]] || continue

                # Safety: only delete backups older than 24 hours
                local file_mtime=$(get_file_mtime "$inprogress_file")
                local current_time=$(date +%s)
                local hours_old=$(((current_time - file_mtime) / 3600))

                if [[ $hours_old -lt 24 ]]; then
                    continue
                fi

                local size_kb=$(du -sk "$inprogress_file" 2> /dev/null | awk '{print $1}' || echo "0")
                if [[ "$size_kb" -gt 0 ]]; then
                    local backup_name=$(basename "$inprogress_file")

                    if [[ "$DRY_RUN" != "true" ]]; then
                        if command -v tmutil > /dev/null 2>&1; then
                            if tmutil delete "$inprogress_file" 2> /dev/null; then
                                local size_human=$(bytes_to_human "$((size_kb * 1024))")
                                echo -e "  ${GREEN}${ICON_SUCCESS}${NC} Failed backup: $backup_name ${GREEN}($size_human)${NC}"
                                ((tm_cleaned++))
                                ((files_cleaned++))
                                ((total_size_cleaned += size_kb))
                                ((total_items++))
                                note_activity
                            else
                                echo -e "  ${YELLOW}!${NC} Could not delete: $backup_name (try manually with sudo)"
                            fi
                        else
                            echo -e "  ${YELLOW}!${NC} tmutil not available, skipping: $backup_name"
                        fi
                    else
                        local size_human=$(bytes_to_human "$((size_kb * 1024))")
                        echo -e "  ${YELLOW}→${NC} Failed backup: $backup_name ${YELLOW}($size_human dry)${NC}"
                        ((tm_cleaned++))
                        note_activity
                    fi
                fi
            done < <(find "$backupdb_dir" -maxdepth 3 -type d \( -name "*.inProgress" -o -name "*.inprogress" \) 2> /dev/null || true)
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

                    # Safety: only delete backups older than 24 hours
                    local file_mtime=$(get_file_mtime "$inprogress_file")
                    local current_time=$(date +%s)
                    local hours_old=$(((current_time - file_mtime) / 3600))

                    if [[ $hours_old -lt 24 ]]; then
                        continue
                    fi

                    local size_kb=$(du -sk "$inprogress_file" 2> /dev/null | awk '{print $1}' || echo "0")
                    if [[ "$size_kb" -gt 0 ]]; then
                        local backup_name=$(basename "$inprogress_file")

                        if [[ "$DRY_RUN" != "true" ]]; then
                            if command -v tmutil > /dev/null 2>&1; then
                                if tmutil delete "$inprogress_file" 2> /dev/null; then
                                    local size_human=$(bytes_to_human "$((size_kb * 1024))")
                                    echo -e "  ${GREEN}${ICON_SUCCESS}${NC} Failed APFS backup in $bundle_name: $backup_name ${GREEN}($size_human)${NC}"
                                    ((tm_cleaned++))
                                    ((files_cleaned++))
                                    ((total_size_cleaned += size_kb))
                                    ((total_items++))
                                    note_activity
                                else
                                    echo -e "  ${YELLOW}!${NC} Could not delete from bundle: $backup_name"
                                fi
                            fi
                        else
                            local size_human=$(bytes_to_human "$((size_kb * 1024))")
                            echo -e "  ${YELLOW}→${NC} Failed APFS backup in $bundle_name: $backup_name ${YELLOW}($size_human dry)${NC}"
                            ((tm_cleaned++))
                            note_activity
                        fi
                    fi
                done < <(find "$mounted_path" -maxdepth 3 -type d \( -name "*.inProgress" -o -name "*.inprogress" \) 2> /dev/null || true)
            fi
        done
    done

    if [[ $tm_cleaned -eq 0 ]]; then
        echo -e "  ${GREEN}${ICON_SUCCESS}${NC} No failed Time Machine backups found"
    fi
}
