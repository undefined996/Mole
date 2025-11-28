#!/bin/bash
# User Data Cleanup Module
# Essential user caches, browsers, cloud storage, office apps

set -euo pipefail

# Clean user essentials (caches, logs, trash, crash reports)
# Env: DRY_RUN
clean_user_essentials() {
    safe_clean ~/Library/Caches/* "User app cache"
    safe_clean ~/Library/Logs/* "User app logs"
    safe_clean ~/.Trash/* "Trash"

    # Empty trash on mounted volumes
    if [[ -d "/Volumes" ]]; then
        for volume in /Volumes/*; do
            [[ -d "$volume" && -d "$volume/.Trashes" && -w "$volume" ]] || continue

            # Skip network volumes
            local fs_type=$(df -T "$volume" 2> /dev/null | tail -1 | awk '{print $2}')
            case "$fs_type" in
                nfs | smbfs | afpfs | cifs | webdav) continue ;;
            esac

            # Verify volume is mounted
            if mount | grep -q "on $volume "; then
                if [[ "$DRY_RUN" != "true" ]]; then
                    find "$volume/.Trashes" -mindepth 1 -maxdepth 1 -exec rm -rf {} \; 2> /dev/null || true
                fi
            fi
        done
    fi

    safe_clean ~/Library/Application\ Support/CrashReporter/* "Crash reports"
    safe_clean ~/Library/DiagnosticReports/* "Diagnostic reports"
    safe_clean ~/Library/Caches/com.apple.QuickLook.thumbnailcache "QuickLook thumbnails"
    safe_clean ~/Library/Caches/Quick\ Look/* "QuickLook cache"
    safe_clean ~/Library/Caches/com.apple.iconservices* "Icon services cache"
    safe_clean ~/Library/Caches/CloudKit/* "CloudKit cache"

    # Clean incomplete downloads
    safe_clean ~/Downloads/*.download "Incomplete downloads (Safari)"
    safe_clean ~/Downloads/*.crdownload "Incomplete downloads (Chrome)"
    safe_clean ~/Downloads/*.part "Incomplete downloads (partial)"

    # Additional user-level caches
    safe_clean ~/Library/Autosave\ Information/* "Autosave information"
    safe_clean ~/Library/IdentityCaches/* "Identity caches"
    safe_clean ~/Library/Suggestions/* "Suggestions cache (Siri)"
    safe_clean ~/Library/Calendars/Calendar\ Cache "Calendar cache"
    safe_clean ~/Library/Application\ Support/AddressBook/Sources/*/Photos.cache "Address Book photo cache"
}

# Clean Finder metadata (.DS_Store files)
# Env: PROTECT_FINDER_METADATA
clean_finder_metadata() {
    if [[ "$PROTECT_FINDER_METADATA" == "true" ]]; then
        note_activity
        echo -e "  ${YELLOW}☻${NC} Finder metadata protected by whitelist"
        echo -e "  ${YELLOW}☻${NC} Run ${GRAY}mo clean --whitelist${NC} to allow cleaning .DS_Store files"
    else
        clean_ds_store_tree "$HOME" "Home directory (.DS_Store)"

        if [[ -d "/Volumes" ]]; then
            for volume in /Volumes/*; do
                [[ -d "$volume" && -w "$volume" ]] || continue

                local fs_type=""
                fs_type=$(df -T "$volume" 2> /dev/null | tail -1 | awk '{print $2}')
                case "$fs_type" in
                    nfs | smbfs | afpfs | cifs | webdav) continue ;;
                esac

                clean_ds_store_tree "$volume" "$(basename "$volume") volume (.DS_Store)"
            done
        fi
    fi
}

# Clean macOS system caches
clean_macos_system_caches() {
    safe_clean ~/Library/Saved\ Application\ State/* "Saved application states"
    safe_clean ~/Library/Caches/com.apple.spotlight "Spotlight cache"
    safe_clean ~/Library/Caches/com.apple.photoanalysisd "Photo analysis cache"
    safe_clean ~/Library/Caches/com.apple.akd "Apple ID cache"
    safe_clean ~/Library/Caches/com.apple.Safari/Webpage\ Previews/* "Safari webpage previews"
    safe_clean ~/Library/Application\ Support/CloudDocs/session/db/* "iCloud session cache"
    safe_clean ~/Library/Caches/com.apple.Safari/fsCachedData/* "Safari cached data"
    safe_clean ~/Library/Caches/com.apple.WebKit.WebContent/* "WebKit content cache"
    safe_clean ~/Library/Caches/com.apple.WebKit.Networking/* "WebKit network cache"
}

# Clean sandboxed app caches
clean_sandboxed_app_caches() {
    safe_clean ~/Library/Containers/com.apple.wallpaper.agent/Data/Library/Caches/* "Wallpaper agent cache"
    safe_clean ~/Library/Containers/com.apple.mediaanalysisd/Data/Library/Caches/* "Media analysis cache"
    safe_clean ~/Library/Containers/com.apple.AppStore/Data/Library/Caches/* "App Store cache"
    safe_clean ~/Library/Containers/com.apple.configurator.xpc.InternetService/Data/tmp/* "Apple Configurator temp files"
    safe_clean ~/Library/Containers/*/Data/Library/Caches/* "Sandboxed app caches"
}

# Clean browser caches (Safari, Chrome, Edge, Firefox, etc.)
clean_browsers() {
    safe_clean ~/Library/Caches/com.apple.Safari/* "Safari cache"

    # Chrome/Chromium
    safe_clean ~/Library/Caches/Google/Chrome/* "Chrome cache"
    safe_clean ~/Library/Application\ Support/Google/Chrome/*/Application\ Cache/* "Chrome app cache"
    safe_clean ~/Library/Application\ Support/Google/Chrome/*/GPUCache/* "Chrome GPU cache"
    safe_clean ~/Library/Caches/Chromium/* "Chromium cache"

    safe_clean ~/Library/Caches/com.microsoft.edgemac/* "Edge cache"
    safe_clean ~/Library/Caches/company.thebrowser.Browser/* "Arc cache"
    safe_clean ~/Library/Caches/company.thebrowser.dia/* "Dia cache"
    safe_clean ~/Library/Caches/BraveSoftware/Brave-Browser/* "Brave cache"
    safe_clean ~/Library/Caches/Firefox/* "Firefox cache"
    safe_clean ~/Library/Caches/com.operasoftware.Opera/* "Opera cache"
    safe_clean ~/Library/Caches/com.vivaldi.Vivaldi/* "Vivaldi cache"
    safe_clean ~/Library/Caches/Comet/* "Comet cache"
    safe_clean ~/Library/Caches/com.kagi.kagimacOS/* "Orion cache"
    safe_clean ~/Library/Caches/zen/* "Zen cache"
    safe_clean ~/Library/Application\ Support/Firefox/Profiles/*/cache2/* "Firefox profile cache"

    # Service Worker CacheStorage (all profiles)
    # Limit search depth to prevent hanging on large profile directories
    while IFS= read -r sw_path; do
        [[ -z "$sw_path" ]] && continue
        local profile_name=$(basename "$(dirname "$(dirname "$sw_path")")")
        local browser_name="Chrome"
        [[ "$sw_path" == *"Microsoft Edge"* ]] && browser_name="Edge"
        [[ "$sw_path" == *"Brave"* ]] && browser_name="Brave"
        [[ "$sw_path" == *"Arc"* ]] && browser_name="Arc"
        [[ "$profile_name" != "Default" ]] && browser_name="$browser_name ($profile_name)"
        clean_service_worker_cache "$browser_name" "$sw_path"
    done < <(find "$HOME/Library/Application Support/Google/Chrome" \
        "$HOME/Library/Application Support/Microsoft Edge" \
        "$HOME/Library/Application Support/BraveSoftware/Brave-Browser" \
        "$HOME/Library/Application Support/Arc/User Data" \
        -maxdepth 6 -type d -name "CacheStorage" -path "*/Service Worker/*" 2> /dev/null || true)
}

# Clean cloud storage app caches
clean_cloud_storage() {
    safe_clean ~/Library/Caches/com.dropbox.* "Dropbox cache"
    safe_clean ~/Library/Caches/com.getdropbox.dropbox "Dropbox cache"
    safe_clean ~/Library/Caches/com.google.GoogleDrive "Google Drive cache"
    safe_clean ~/Library/Caches/com.baidu.netdisk "Baidu Netdisk cache"
    safe_clean ~/Library/Caches/com.alibaba.teambitiondisk "Alibaba Cloud cache"
    safe_clean ~/Library/Caches/com.box.desktop "Box cache"
    safe_clean ~/Library/Caches/com.microsoft.OneDrive "OneDrive cache"
}

# Clean office application caches
clean_office_applications() {
    safe_clean ~/Library/Caches/com.microsoft.Word "Microsoft Word cache"
    safe_clean ~/Library/Caches/com.microsoft.Excel "Microsoft Excel cache"
    safe_clean ~/Library/Caches/com.microsoft.Powerpoint "Microsoft PowerPoint cache"
    safe_clean ~/Library/Caches/com.microsoft.Outlook/* "Microsoft Outlook cache"
    safe_clean ~/Library/Caches/com.apple.iWork.* "Apple iWork cache"
    safe_clean ~/Library/Caches/com.kingsoft.wpsoffice.mac "WPS Office cache"
    safe_clean ~/Library/Caches/org.mozilla.thunderbird/* "Thunderbird cache"
    safe_clean ~/Library/Caches/com.apple.mail/* "Apple Mail cache"
}

# Clean virtualization tools
clean_virtualization_tools() {
    safe_clean ~/Library/Caches/com.vmware.fusion "VMware Fusion cache"
    safe_clean ~/Library/Caches/com.parallels.* "Parallels cache"
    safe_clean ~/VirtualBox\ VMs/.cache "VirtualBox cache"
    safe_clean ~/.vagrant.d/tmp/* "Vagrant temporary files"
}

# Clean Application Support logs
clean_application_support_logs() {
    # Check permission
    if [[ ! -d "$HOME/Library/Application Support" ]] || ! ls "$HOME/Library/Application Support" > /dev/null 2>&1; then
        note_activity
        echo -e "  ${YELLOW}${ICON_WARNING}${NC} Skipped: No permission to access Application Support"
        return 0
    fi

    # Clean log directories with iteration limit to prevent hanging
    local iteration_count=0
    local max_iterations=200

    for app_dir in ~/Library/Application\ Support/*; do
        [[ -d "$app_dir" ]] || continue

        # Safety: limit iterations
        ((iteration_count++))
        if [[ $iteration_count -gt $max_iterations ]]; then
            break
        fi

        app_name=$(basename "$app_dir")

        # Skip system and protected apps
        case "$app_name" in
            com.apple.* | Adobe* | JetBrains* | 1Password | Claude | *ClashX* | *clash* | mihomo* | *Surge* | iTerm* | *iterm* | Warp* | Kitty* | Alacritty* | WezTerm* | Ghostty*)
                continue
                ;;
        esac

        # Clean common log directories (only if they exist and are accessible)
        if [[ -d "$app_dir/log" ]] && ls "$app_dir/log" > /dev/null 2>&1; then
            safe_clean "$app_dir/log"/* "App logs: $app_name"
        fi
        if [[ -d "$app_dir/logs" ]] && ls "$app_dir/logs" > /dev/null 2>&1; then
            safe_clean "$app_dir/logs"/* "App logs: $app_name"
        fi
        if [[ -d "$app_dir/activitylog" ]] && ls "$app_dir/activitylog" > /dev/null 2>&1; then
            safe_clean "$app_dir/activitylog"/* "Activity logs: $app_name"
        fi
    done
}

# Check and show iOS device backup info
check_ios_device_backups() {
    local backup_dir="$HOME/Library/Application Support/MobileSync/Backup"
    if [[ -d "$backup_dir" ]] && find "$backup_dir" -mindepth 1 -maxdepth 1 | read -r _; then
        local backup_kb=$(du -sk "$backup_dir" 2> /dev/null | awk '{print $1}')
        if [[ -n "${backup_kb:-}" && "$backup_kb" -gt 102400 ]]; then
            local backup_human=$(du -sh "$backup_dir" 2> /dev/null | awk '{print $1}')
            note_activity
            echo -e "  Found ${GREEN}${backup_human}${NC} iOS backups"
            echo -e "  You can delete them manually: ${backup_dir}"
        fi
    fi
}

# Clean Apple Silicon specific caches
# Env: IS_M_SERIES
clean_apple_silicon_caches() {
    if [[ "$IS_M_SERIES" != "true" ]]; then
        return 0
    fi

    safe_clean /Library/Apple/usr/share/rosetta/rosetta_update_bundle "Rosetta 2 cache"
    safe_clean ~/Library/Caches/com.apple.rosetta.update "Rosetta 2 user cache"
    safe_clean ~/Library/Caches/com.apple.amp.mediasevicesd "Apple Silicon media service cache"
}
