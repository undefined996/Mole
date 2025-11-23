#!/bin/bash
# Optimization Tasks
# Individual optimization operations extracted from execute_optimization

set -euo pipefail

# System maintenance: rebuild databases and flush caches
opt_system_maintenance() {
    echo -e "${BLUE}${ICON_ARROW}${NC} Rebuilding LaunchServices database..."
    timeout 10 /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user > /dev/null 2>&1 || true
    echo -e "${GREEN}${ICON_SUCCESS}${NC} LaunchServices database rebuilt"

    echo -e "${BLUE}${ICON_ARROW}${NC} Clearing DNS cache..."
    if sudo dscacheutil -flushcache 2> /dev/null && sudo killall -HUP mDNSResponder 2> /dev/null; then
        echo -e "${GREEN}${ICON_SUCCESS}${NC} DNS cache cleared"
    else
        echo -e "${RED}${ICON_ERROR}${NC} Failed to clear DNS cache"
    fi

    echo -e "${BLUE}${ICON_ARROW}${NC} Clearing memory cache..."
    if sudo purge 2> /dev/null; then
        echo -e "${GREEN}${ICON_SUCCESS}${NC} Memory cache cleared"
    else
        echo -e "${RED}${ICON_ERROR}${NC} Failed to clear memory"
    fi

    echo -e "${BLUE}${ICON_ARROW}${NC} Rebuilding font cache..."
    sudo atsutil databases -remove > /dev/null 2>&1
    echo -e "${GREEN}${ICON_SUCCESS}${NC} Font cache rebuilt"

    echo -e "${BLUE}${ICON_ARROW}${NC} Rebuilding Spotlight index (runs in background)..."
    # mdutil triggers background indexing - don't wait
    timeout 10 sudo mdutil -E / > /dev/null 2>&1 || true
    echo -e "${GREEN}${ICON_SUCCESS}${NC} Spotlight rebuild initiated"
}

# Cache refresh: update Finder/Safari caches
opt_cache_refresh() {
    echo -e "${BLUE}${ICON_ARROW}${NC} Resetting Quick Look cache..."
    qlmanage -r cache > /dev/null 2>&1 || true
    qlmanage -r > /dev/null 2>&1 || true

    local -a cache_targets=(
        "$HOME/Library/Caches/com.apple.QuickLook.thumbnailcache|Quick Look thumbnails"
        "$HOME/Library/Caches/com.apple.iconservices.store|Icon Services store"
        "$HOME/Library/Caches/com.apple.iconservices|Icon Services cache"
        "$HOME/Library/Caches/com.apple.Safari/WebKitCache|Safari WebKit cache"
        "$HOME/Library/Caches/com.apple.Safari/Favicon|Safari favicon cache"
    )

    for target in "${cache_targets[@]}"; do
        IFS='|' read -r target_path label <<< "$target"
        cleanup_path "$target_path" "$label"
    done

    echo -e "${GREEN}${ICON_SUCCESS}${NC} Finder and Safari caches updated"
}

# Maintenance scripts: run periodic tasks
opt_maintenance_scripts() {
    local success=true
    local periodic_cmd="/usr/sbin/periodic"

    # Show spinner while running all tasks
    if [[ -t 1 ]]; then
        start_inline_spinner ""
    fi

    # Run periodic scripts silently with timeout
    if [[ -x "$periodic_cmd" ]]; then
        if ! timeout 180 sudo "$periodic_cmd" daily weekly monthly > /dev/null 2>&1; then
            success=false
        fi
    fi

    # Run newsyslog silently with timeout
    if ! timeout 120 sudo newsyslog > /dev/null 2>&1; then
        success=false
    fi

    # Run repair_packages silently with timeout
    if [[ -x "/usr/libexec/repair_packages" ]]; then
        if ! timeout 180 sudo /usr/libexec/repair_packages --repair --standard-pkgs --volume / > /dev/null 2>&1; then
            success=false
        fi
    fi

    if [[ -t 1 ]]; then
        stop_inline_spinner
    fi

    # Show final status
    if [[ "$success" == "true" ]]; then
        echo -e "${GREEN}${ICON_SUCCESS}${NC} Complete"
    else
        echo -e "${YELLOW}!${NC} Some tasks timed out or failed"
    fi
}

# Log cleanup: remove diagnostic and crash logs
opt_log_cleanup() {
    echo -e "${BLUE}${ICON_ARROW}${NC} Clearing diagnostic & crash logs..."
    local -a user_logs=(
        "$HOME/Library/Logs/DiagnosticReports"
        "$HOME/Library/Logs/CrashReporter"
        "$HOME/Library/Logs/corecaptured"
    )
    for target in "${user_logs[@]}"; do
        cleanup_path "$target" "$(basename "$target")"
    done

    if [[ -d "/Library/Logs/DiagnosticReports" ]]; then
        sudo find /Library/Logs/DiagnosticReports -type f -name "*.crash" -delete 2> /dev/null || true
        sudo find /Library/Logs/DiagnosticReports -type f -name "*.panic" -delete 2> /dev/null || true
        echo -e "${GREEN}${ICON_SUCCESS}${NC} System diagnostic logs cleared"
    else
        echo -e "${GRAY}-${NC} No system diagnostic logs found"
    fi
}

# Recent items: clear recent file lists
opt_recent_items() {
    echo -e "${BLUE}${ICON_ARROW}${NC} Clearing recent items lists..."
    local shared_dir="$HOME/Library/Application Support/com.apple.sharedfilelist"
    if [[ -d "$shared_dir" ]]; then
        find "$shared_dir" -name "*.sfl2" -type f -delete 2> /dev/null || true
        echo -e "${GREEN}${ICON_SUCCESS}${NC} Shared file lists cleared"
    fi

    rm -f "$HOME/Library/Preferences/com.apple.recentitems.plist" 2> /dev/null || true
    defaults delete NSGlobalDomain NSRecentDocumentsLimit 2> /dev/null || true

    echo -e "${GREEN}${ICON_SUCCESS}${NC} Recent items cleared"
}

# Radio refresh: reset Bluetooth and Wi-Fi
opt_radio_refresh() {
    echo -e "${BLUE}${ICON_ARROW}${NC} Resetting Bluetooth preferences..."
    rm -f "$HOME/Library/Preferences/com.apple.Bluetooth.plist" 2> /dev/null || true
    sudo rm -f /Library/Preferences/com.apple.Bluetooth.plist 2> /dev/null || true
    echo -e "${GREEN}${ICON_SUCCESS}${NC} Bluetooth caches refreshed"

    echo -e "${BLUE}${ICON_ARROW}${NC} Resetting Wi-Fi settings..."
    local sysconfig="/Library/Preferences/SystemConfiguration"
    if [[ -d "$sysconfig" ]]; then
        sudo cp "$sysconfig"/com.apple.airport.preferences.plist "$sysconfig"/com.apple.airport.preferences.plist.bak 2> /dev/null || true
        sudo rm -f "$sysconfig"/com.apple.airport.preferences.plist 2> /dev/null || true
        echo -e "${GREEN}${ICON_SUCCESS}${NC} Wi-Fi preferences reset"
    else
        echo -e "${GRAY}-${NC} SystemConfiguration directory missing"
    fi

    sudo ifconfig awdl0 down 2> /dev/null || true
    sudo ifconfig awdl0 up 2> /dev/null || true
    echo -e "${GREEN}${ICON_SUCCESS}${NC} Wireless services refreshed"
}

# Mail downloads: clear Mail attachment cache
opt_mail_downloads() {
    echo -e "${BLUE}${ICON_ARROW}${NC} Clearing Mail attachment downloads..."
    local -a mail_dirs=(
        "$HOME/Library/Mail Downloads|Mail Downloads"
        "$HOME/Library/Containers/com.apple.mail/Data/Library/Mail Downloads|Mail Container Downloads"
    )
    for target in "${mail_dirs[@]}"; do
        IFS='|' read -r target_path label <<< "$target"
        cleanup_path "$target_path" "$label"
        ensure_directory "$target_path"
    done
    echo -e "${GREEN}${ICON_SUCCESS}${NC} Mail downloads cleared"
}

# Saved state: remove app saved states
opt_saved_state_cleanup() {
    echo -e "${BLUE}${ICON_ARROW}${NC} Removing saved application states..."
    local state_dir="$HOME/Library/Saved Application State"
    cleanup_path "$state_dir" "Saved Application State"
    ensure_directory "$state_dir"
    echo -e "${GREEN}${ICON_SUCCESS}${NC} Saved states cleared"
}

# Finder and Dock: refresh interface caches
opt_finder_dock_refresh() {
    echo -e "${BLUE}${ICON_ARROW}${NC} Resetting Finder & Dock caches..."
    local -a interface_targets=(
        "$HOME/Library/Caches/com.apple.finder|Finder cache"
        "$HOME/Library/Caches/com.apple.dock.iconcache|Dock icon cache"
    )
    for target in "${interface_targets[@]}"; do
        IFS='|' read -r target_path label <<< "$target"
        cleanup_path "$target_path" "$label"
    done
    killall Finder > /dev/null 2>&1 || true
    killall Dock > /dev/null 2>&1 || true
    echo -e "${GREEN}${ICON_SUCCESS}${NC} Finder & Dock relaunched"
}

# Swap cleanup: reset swap files
opt_swap_cleanup() {
    echo -e "${BLUE}${ICON_ARROW}${NC} Removing swapfiles and resetting dynamic pager..."
    if sudo launchctl unload /System/Library/LaunchDaemons/com.apple.dynamic_pager.plist > /dev/null 2>&1; then
        sudo rm -f /private/var/vm/swapfile* > /dev/null 2>&1 || true
        sudo touch /private/var/vm/swapfile0 > /dev/null 2>&1 || true
        sudo chmod 600 /private/var/vm/swapfile0 > /dev/null 2>&1 || true
        sudo launchctl load /System/Library/LaunchDaemons/com.apple.dynamic_pager.plist > /dev/null 2>&1 || true
        echo -e "${GREEN}${ICON_SUCCESS}${NC} Swap cache rebuilt"
    else
        echo -e "${YELLOW}!${NC} Could not unload dynamic_pager"
    fi
}

# Startup cache: rebuild kernel caches
opt_startup_cache() {
    local macos_version
    macos_version=$(sw_vers -productVersion | cut -d '.' -f 1)
    local success=true

    if [[ -t 1 ]]; then
        start_inline_spinner ""
    fi

    if [[ "$macos_version" -ge 11 ]] || [[ "$(uname -m)" == "arm64" ]]; then
        if ! timeout 120 sudo kextcache -i / > /dev/null 2>&1; then
            success=false
        fi
    else
        if ! timeout 180 sudo kextcache -i / > /dev/null 2>&1; then
            success=false
        fi

        sudo rm -rf /System/Library/PrelinkedKernels/* > /dev/null 2>&1 || true
        timeout 120 sudo kextcache -system-prelinked-kernel > /dev/null 2>&1 || true
    fi

    if [[ -t 1 ]]; then
        stop_inline_spinner
    fi

    if [[ "$success" == "true" ]]; then
        echo -e "${GREEN}${ICON_SUCCESS}${NC} Complete"
    else
        echo -e "${YELLOW}!${NC} Timed out or failed"
    fi
}

# Local snapshots: thin Time Machine snapshots
opt_local_snapshots() {
    if ! command -v tmutil > /dev/null 2>&1; then
        echo -e "${YELLOW}!${NC} tmutil not available on this system"
        return
    fi

    local before after
    before=$(count_local_snapshots)
    if [[ "$before" -eq 0 ]]; then
        echo -e "${GREEN}${ICON_SUCCESS}${NC} No local snapshots to thin"
        return
    fi

    if [[ -t 1 ]]; then
        start_inline_spinner ""
    fi

    local success=false
    if timeout 180 sudo tmutil thinlocalsnapshots / 9999999999 4 > /dev/null 2>&1; then
        success=true
    fi

    if [[ -t 1 ]]; then
        stop_inline_spinner
    fi

    if [[ "$success" == "true" ]]; then
        after=$(count_local_snapshots)
        local removed=$((before - after))
        [[ "$removed" -lt 0 ]] && removed=0
        echo -e "${GREEN}${ICON_SUCCESS}${NC} Removed $removed snapshots (remaining: $after)"
    else
        echo -e "${YELLOW}!${NC} Timed out or failed"
    fi
}

# Developer cleanup: remove Xcode/simulator cruft
opt_developer_cleanup() {
    local -a dev_targets=(
        "$HOME/Library/Developer/Xcode/DerivedData|Xcode DerivedData"
        "$HOME/Library/Developer/Xcode/iOS DeviceSupport|iOS Device support files"
        "$HOME/Library/Developer/CoreSimulator/Caches|CoreSimulator caches"
    )

    for target in "${dev_targets[@]}"; do
        IFS='|' read -r target_path label <<< "$target"
        cleanup_path "$target_path" "$label"
    done

    if command -v xcrun > /dev/null 2>&1; then
        echo -e "${BLUE}${ICON_ARROW}${NC} Removing unavailable simulator runtimes..."
        if xcrun simctl delete unavailable > /dev/null 2>&1; then
            echo -e "${GREEN}${ICON_SUCCESS}${NC} Unavailable simulators removed"
        else
            echo -e "${YELLOW}!${NC} Could not prune simulator runtimes"
        fi
    fi

    echo -e "${GREEN}${ICON_SUCCESS}${NC} Developer caches cleaned"
}

# Execute optimization by action name
execute_optimization() {
    local action="$1"
    local path="${2:-}"

    case "$action" in
        system_maintenance)     opt_system_maintenance ;;
        cache_refresh)          opt_cache_refresh ;;
        maintenance_scripts)    opt_maintenance_scripts ;;
        log_cleanup)            opt_log_cleanup ;;
        recent_items)           opt_recent_items ;;
        radio_refresh)          opt_radio_refresh ;;
        mail_downloads)         opt_mail_downloads ;;
        saved_state_cleanup)    opt_saved_state_cleanup ;;
        finder_dock_refresh)    opt_finder_dock_refresh ;;
        swap_cleanup)           opt_swap_cleanup ;;
        startup_cache)          opt_startup_cache ;;
        local_snapshots)        opt_local_snapshots ;;
        developer_cleanup)      opt_developer_cleanup ;;
        *)
            echo -e "${RED}${ICON_ERROR}${NC} Unknown action: $action"
            return 1
            ;;
    esac
}
