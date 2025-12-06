#!/bin/bash
# System Configuration Maintenance Module
# Fix broken preferences and broken login items

set -euo pipefail

# ============================================================================
# Broken Preferences Detection and Cleanup
# Find and remove corrupted .plist files
# ============================================================================

# Clean broken preference files
# Uses plutil -lint to validate plist files
# Returns: count of broken files fixed
fix_broken_preferences() {
    local prefs_dir="$HOME/Library/Preferences"
    [[ -d "$prefs_dir" ]] || return 0

    local broken_count=0

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
        plutil -lint "$plist_file" > /dev/null 2>&1 && continue

        # Remove broken plist
        rm -f "$plist_file" 2> /dev/null || true
        ((broken_count++))
    done < <(run_with_timeout 10 sh -c "find '$prefs_dir' -maxdepth 1 -name '*.plist' -type f 2> /dev/null || true")

    # Check ByHost preferences with timeout protection
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

            plutil -lint "$plist_file" > /dev/null 2>&1 && continue

            rm -f "$plist_file" 2> /dev/null || true
            ((broken_count++))
        done < <(run_with_timeout 10 sh -c "find '$byhost_dir' -name '*.plist' -type f 2> /dev/null || true")
    fi

    echo "$broken_count"
}

# ============================================================================
# Broken Login Items Cleanup
# Find and remove login items pointing to non-existent files
# ============================================================================

# Clean broken login items (LaunchAgents pointing to missing executables)
# Returns: count of broken items fixed
fix_broken_login_items() {
    local launch_agents_dir="$HOME/Library/LaunchAgents"
    [[ -d "$launch_agents_dir" ]] || return 0

    local broken_count=0

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

        # Extract Program or ProgramArguments[0] from plist using plutil
        local program=""
        program=$(plutil -extract Program raw "$plist_file" 2> /dev/null || echo "")

        if [[ -z "$program" ]]; then
            # Try ProgramArguments array (first element)
            program=$(plutil -extract ProgramArguments.0 raw "$plist_file" 2> /dev/null || echo "")
        fi

        # Skip if no program found or program exists
        [[ -z "$program" ]] && continue
        [[ -e "$program" ]] && continue

        # Program doesn't exist - this is a broken login item
        launchctl unload "$plist_file" 2> /dev/null || true
        rm -f "$plist_file" 2> /dev/null || true
        ((broken_count++))
    done < <(run_with_timeout 10 sh -c "find '$launch_agents_dir' -name '*.plist' -type f 2> /dev/null || true")

    echo "$broken_count"
}

# ============================================================================
# Check for broken configurations
# Returns: JSON line if issues found, empty otherwise
# ============================================================================

check_broken_configs() {
    local prefs_dir="$HOME/Library/Preferences"
    local launch_agents_dir="$HOME/Library/LaunchAgents"

    local broken_prefs=0
    local broken_items=0

    # Count broken preferences
    if [[ -d "$prefs_dir" ]]; then
        while IFS= read -r plist_file; do
            [[ -f "$plist_file" ]] || continue
            local filename=$(basename "$plist_file")
            case "$filename" in
                com.apple.* | .GlobalPreferences* | loginwindow.plist) continue ;;
            esac
            plutil -lint "$plist_file" > /dev/null 2>&1 || ((broken_prefs++))
        done < <(run_with_timeout 10 sh -c "find '$prefs_dir' -maxdepth 1 -name '*.plist' -type f 2> /dev/null || true")
    fi

    # Count broken login items
    if [[ -d "$launch_agents_dir" ]]; then
        while IFS= read -r plist_file; do
            [[ -f "$plist_file" ]] || continue
            local filename=$(basename "$plist_file")
            case "$filename" in com.apple.*) continue ;; esac

            local program=$(plutil -extract Program raw "$plist_file" 2> /dev/null || echo "")
            [[ -z "$program" ]] && program=$(plutil -extract ProgramArguments.0 raw "$plist_file" 2> /dev/null || echo "")
            [[ -z "$program" ]] && continue
            [[ -e "$program" ]] || ((broken_items++))
        done < <(run_with_timeout 10 sh -c "find '$launch_agents_dir' -name '*.plist' -type f 2> /dev/null || true")
    fi

    local total=$((broken_prefs + broken_items))
    if [[ $total -gt 0 ]]; then
        echo "fix_broken_configs|Fix Broken Configurations|Fix $total broken preference/login item files|false"
    fi
}
