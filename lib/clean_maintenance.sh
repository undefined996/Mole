#!/bin/bash
# Maintenance Cleanup Module
# Universal binary slimming, broken preferences, broken login items

set -euo pipefail

# ============================================================================
# Universal Binary Slimming
# Remove unused architecture code from universal binaries
# ============================================================================

# Slim universal binaries to current architecture only
# Only processes apps in /Applications, skips signed/notarized apps
# Env: DRY_RUN
# Globals: files_cleaned, total_size_cleaned, total_items (modified)
clean_universal_binaries() {
    # Only run on Apple Silicon (most benefit)
    if [[ "$(uname -m)" != "arm64" ]]; then
        return 0
    fi

    # Check if lipo is available
    if ! command -v lipo > /dev/null 2>&1; then
        return 0
    fi

    local current_arch="arm64"
    local remove_arch="x86_64"
    local total_saved_kb=0
    local apps_slimmed=0
    local max_apps=50 # Limit to prevent long runs

    if [[ -t 1 ]]; then
        MOLE_SPINNER_PREFIX="  " start_inline_spinner "Scanning universal binaries..."
    fi

    local app_count=0
    while IFS= read -r app_path; do
        [[ -d "$app_path" ]] || continue

        ((app_count++))
        if [[ $app_count -gt $max_apps ]]; then
            break
        fi

        local binary_path="$app_path/Contents/MacOS"
        [[ -d "$binary_path" ]] || continue

        # Get the main executable
        local info_plist="$app_path/Contents/Info.plist"
        [[ -f "$info_plist" ]] || continue

        local exec_name
        exec_name=$(defaults read "$info_plist" CFBundleExecutable 2> /dev/null || echo "")
        [[ -z "$exec_name" ]] && continue

        local exec_path="$binary_path/$exec_name"
        [[ -f "$exec_path" ]] || continue

        # Check if it's a universal binary with both architectures
        local archs
        archs=$(lipo -archs "$exec_path" 2> /dev/null || echo "")
        if [[ "$archs" != *"$current_arch"* ]] || [[ "$archs" != *"$remove_arch"* ]]; then
            continue
        fi

        # Skip if app is code signed (removing arch breaks signature)
        if codesign -v "$app_path" 2> /dev/null; then
            continue
        fi

        # Calculate size before
        local size_before
        size_before=$(du -sk "$exec_path" 2> /dev/null | awk '{print $1}' || echo "0")

        if [[ "$DRY_RUN" != "true" ]]; then
            # Create backup and slim
            local backup_path="${exec_path}.universal.bak"
            if cp "$exec_path" "$backup_path" 2> /dev/null; then
                if lipo "$backup_path" -remove "$remove_arch" -output "$exec_path" 2> /dev/null; then
                    rm -f "$backup_path"
                    local size_after
                    size_after=$(du -sk "$exec_path" 2> /dev/null | awk '{print $1}' || echo "0")
                    local saved=$((size_before - size_after))
                    if [[ $saved -gt 0 ]]; then
                        ((total_saved_kb += saved))
                        ((apps_slimmed++))
                    fi
                else
                    # Restore backup on failure
                    mv "$backup_path" "$exec_path" 2> /dev/null || true
                fi
            fi
        else
            # Dry run: estimate savings (roughly 40-50% of binary size)
            local estimated_save=$((size_before / 2))
            ((total_saved_kb += estimated_save))
            ((apps_slimmed++))
        fi
    done < <(find /Applications -maxdepth 2 -type d -name "*.app" 2> /dev/null || true)

    if [[ -t 1 ]]; then
        stop_inline_spinner
    fi

    if [[ $apps_slimmed -gt 0 && $total_saved_kb -gt 1024 ]]; then
        local saved_human
        saved_human=$(bytes_to_human "$((total_saved_kb * 1024))")
        if [[ "$DRY_RUN" == "true" ]]; then
            echo -e "  ${YELLOW}→${NC} Universal binaries: $apps_slimmed apps ${YELLOW}(~$saved_human dry)${NC}"
        else
            echo -e "  ${GREEN}${ICON_SUCCESS}${NC} Slimmed $apps_slimmed apps ${GREEN}($saved_human)${NC}"
        fi
        # Update global statistics
        ((files_cleaned += apps_slimmed))
        ((total_size_cleaned += total_saved_kb))
        ((total_items++))
        note_activity
    fi
}

# ============================================================================
# Broken Preferences Detection and Cleanup
# Find and remove corrupted .plist files
# ============================================================================

# Clean broken preference files
# Uses plutil -lint to validate plist files
# Env: DRY_RUN
# Globals: files_cleaned, total_size_cleaned, total_items (modified)
clean_broken_preferences() {
    local prefs_dir="$HOME/Library/Preferences"
    [[ -d "$prefs_dir" ]] || return 0

    local broken_count=0
    local total_size_kb=0

    if [[ -t 1 ]]; then
        MOLE_SPINNER_PREFIX="  " start_inline_spinner "Checking preference files..."
    fi

    # Check main preferences directory
    while IFS= read -r plist_file; do
        [[ -f "$plist_file" ]] || continue

        # Skip system preferences
        local filename
        filename=$(basename "$plist_file")
        case "$filename" in
            com.apple.* | .GlobalPreferences* | loginwindow.plist)
                continue
                ;;
        esac

        # Validate plist using plutil
        if ! plutil -lint "$plist_file" > /dev/null 2>&1; then
            local size_kb
            size_kb=$(du -sk "$plist_file" 2> /dev/null | awk '{print $1}' || echo "0")

            if [[ "$DRY_RUN" != "true" ]]; then
                rm -f "$plist_file" 2> /dev/null || true
            fi

            ((broken_count++))
            ((total_size_kb += size_kb))
        fi
    done < <(find "$prefs_dir" -maxdepth 1 -name "*.plist" -type f 2> /dev/null || true)

    # Check ByHost preferences
    local byhost_dir="$prefs_dir/ByHost"
    if [[ -d "$byhost_dir" ]]; then
        while IFS= read -r plist_file; do
            [[ -f "$plist_file" ]] || continue

            local filename
            filename=$(basename "$plist_file")
            case "$filename" in
                com.apple.* | .GlobalPreferences*)
                    continue
                    ;;
            esac

            if ! plutil -lint "$plist_file" > /dev/null 2>&1; then
                local size_kb
                size_kb=$(du -sk "$plist_file" 2> /dev/null | awk '{print $1}' || echo "0")

                if [[ "$DRY_RUN" != "true" ]]; then
                    rm -f "$plist_file" 2> /dev/null || true
                fi

                ((broken_count++))
                ((total_size_kb += size_kb))
            fi
        done < <(find "$byhost_dir" -name "*.plist" -type f 2> /dev/null || true)
    fi

    if [[ -t 1 ]]; then
        stop_inline_spinner
    fi

    if [[ $broken_count -gt 0 ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            echo -e "  ${YELLOW}→${NC} Broken preferences: $broken_count files ${YELLOW}(dry)${NC}"
        else
            echo -e "  ${GREEN}${ICON_SUCCESS}${NC} Removed $broken_count broken preference files"
        fi
        # Update global statistics
        ((files_cleaned += broken_count))
        ((total_size_cleaned += total_size_kb))
        ((total_items++))
        note_activity
    fi
}

# ============================================================================
# Broken Login Items Cleanup
# Find and remove login items pointing to non-existent files
# ============================================================================

# Clean broken login items (LaunchAgents pointing to missing executables)
# Env: DRY_RUN
# Globals: files_cleaned, total_items (modified)
clean_broken_login_items() {
    local launch_agents_dir="$HOME/Library/LaunchAgents"
    [[ -d "$launch_agents_dir" ]] || return 0

    local broken_count=0
    local total_size_kb=0

    if [[ -t 1 ]]; then
        MOLE_SPINNER_PREFIX="  " start_inline_spinner "Checking login items..."
    fi

    while IFS= read -r plist_file; do
        [[ -f "$plist_file" ]] || continue

        # Skip system items
        local filename
        filename=$(basename "$plist_file")
        case "$filename" in
            com.apple.*)
                continue
                ;;
        esac

        # Extract Program or ProgramArguments[0] from plist
        local program=""
        program=$(defaults read "$plist_file" Program 2> /dev/null || echo "")

        if [[ -z "$program" ]]; then
            # Try ProgramArguments array
            program=$(defaults read "$plist_file" ProgramArguments 2> /dev/null | head -2 | tail -1 | sed 's/^[[:space:]]*"//' | sed 's/".*$//' || echo "")
        fi

        # Skip if no program found or program exists
        [[ -z "$program" ]] && continue
        [[ -e "$program" ]] && continue

        # Program doesn't exist - this is a broken login item
        local size_kb
        size_kb=$(du -sk "$plist_file" 2> /dev/null | awk '{print $1}' || echo "0")

        if [[ "$DRY_RUN" != "true" ]]; then
            # Unload first if loaded
            launchctl unload "$plist_file" 2> /dev/null || true
            rm -f "$plist_file" 2> /dev/null || true
        fi

        ((broken_count++))
        ((total_size_kb += size_kb))
    done < <(find "$launch_agents_dir" -name "*.plist" -type f 2> /dev/null || true)

    if [[ -t 1 ]]; then
        stop_inline_spinner
    fi

    if [[ $broken_count -gt 0 ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            echo -e "  ${YELLOW}→${NC} Broken login items: $broken_count ${YELLOW}(dry)${NC}"
        else
            echo -e "  ${GREEN}${ICON_SUCCESS}${NC} Removed $broken_count broken login items"
        fi
        # Update global statistics
        ((files_cleaned += broken_count))
        ((total_size_cleaned += total_size_kb))
        ((total_items++))
        note_activity
    fi
}

# ============================================================================
# Main maintenance cleanup function
# ============================================================================

clean_maintenance() {
    clean_broken_preferences
    clean_broken_login_items
    # Universal binary slimming is risky, only run if explicitly enabled
    if [[ "${MOLE_SLIM_BINARIES:-false}" == "true" ]]; then
        clean_universal_binaries
    fi
}
