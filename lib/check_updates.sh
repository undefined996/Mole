#!/bin/bash

# Check for software updates
# Sets global variables for use in suggestions

# Cache configuration
CACHE_DIR="${HOME}/.cache/mole"
CACHE_TTL=600  # 10 minutes in seconds

# Ensure cache directory exists
mkdir -p "$CACHE_DIR" 2>/dev/null || true

clear_cache_file() {
    local file="$1"
    rm -f "$file" 2>/dev/null || true
}

reset_brew_cache() {
    clear_cache_file "$CACHE_DIR/brew_updates"
}

reset_softwareupdate_cache() {
    clear_cache_file "$CACHE_DIR/softwareupdate_list"
    SOFTWARE_UPDATE_LIST=""
}

reset_mole_cache() {
    clear_cache_file "$CACHE_DIR/mole_version"
}

# Check if cache is still valid
is_cache_valid() {
    local cache_file="$1"
    local ttl="${2:-$CACHE_TTL}"

    if [[ ! -f "$cache_file" ]]; then
        return 1
    fi

    local cache_age=$(($(date +%s) - $(stat -f%m "$cache_file" 2>/dev/null || echo 0)))
    [[ $cache_age -lt $ttl ]]
}

check_homebrew_updates() {
    if ! command -v brew > /dev/null 2>&1; then
        return
    fi

    local cache_file="$CACHE_DIR/brew_updates"
    local formula_count=0
    local cask_count=0

    if is_cache_valid "$cache_file"; then
        read -r formula_count cask_count < "$cache_file" 2>/dev/null || true
        formula_count=${formula_count:-0}
        cask_count=${cask_count:-0}
    else
        # Show spinner while checking
        if [[ -t 1 ]]; then
            start_inline_spinner "Checking Homebrew..."
        fi

        local outdated_list=""
        outdated_list=$(brew outdated --quiet 2>/dev/null || echo "")
        if [[ -n "$outdated_list" ]]; then
            formula_count=$(echo "$outdated_list" | wc -l | tr -d ' ')
        fi

        local cask_list=""
        cask_list=$(brew outdated --cask --quiet 2>/dev/null || echo "")
        if [[ -n "$cask_list" ]]; then
            cask_count=$(echo "$cask_list" | wc -l | tr -d ' ')
        fi

        echo "$formula_count $cask_count" > "$cache_file" 2>/dev/null || true

        # Stop spinner before output
        if [[ -t 1 ]]; then
            stop_inline_spinner
        fi
    fi

    local total_count=$((formula_count + cask_count))
    export BREW_FORMULA_OUTDATED_COUNT=$formula_count
    export BREW_CASK_OUTDATED_COUNT=$cask_count
    export BREW_OUTDATED_COUNT=$total_count

    if [[ $total_count -gt 0 ]]; then
        local breakdown=""
        if [[ $formula_count -gt 0 && $cask_count -gt 0 ]]; then
            breakdown=" (${formula_count} formula, ${cask_count} cask)"
        elif [[ $formula_count -gt 0 ]]; then
            breakdown=" (${formula_count} formula)"
        elif [[ $cask_count -gt 0 ]]; then
            breakdown=" (${cask_count} cask)"
        fi
        echo -e "  ${YELLOW}⚠${NC} Homebrew     ${YELLOW}${total_count} updates${NC}${breakdown}"
        echo -e "    ${GRAY}Run: ${GREEN}brew upgrade${NC} ${GRAY}and/or${NC} ${GREEN}brew upgrade --cask${NC}"
    else
        echo -e "  ${GREEN}✓${NC} Homebrew     Up to date"
    fi
}

# Cache software update list to avoid calling softwareupdate twice
SOFTWARE_UPDATE_LIST=""

get_software_updates() {
    local cache_file="$CACHE_DIR/softwareupdate_list"

    if [[ -z "$SOFTWARE_UPDATE_LIST" ]]; then
        # Check cache first
        if is_cache_valid "$cache_file"; then
            SOFTWARE_UPDATE_LIST=$(cat "$cache_file" 2>/dev/null || echo "")
        else
            # Show spinner while checking (only on first call)
            local show_spinner=false
            if [[ -t 1 && -z "${SOFTWAREUPDATE_SPINNER_SHOWN:-}" ]]; then
                start_inline_spinner "Checking system updates..."
                show_spinner=true
                export SOFTWAREUPDATE_SPINNER_SHOWN="true"
            fi

            SOFTWARE_UPDATE_LIST=$(softwareupdate -l 2>/dev/null || echo "")
            # Save to cache
            echo "$SOFTWARE_UPDATE_LIST" > "$cache_file" 2>/dev/null || true

            # Stop spinner
            if [[ "$show_spinner" == "true" ]]; then
                stop_inline_spinner
            fi
        fi
    fi
    echo "$SOFTWARE_UPDATE_LIST"
}

check_appstore_updates() {
    local update_list=""
    update_list=$(get_software_updates | grep -v "Software Update Tool" | grep "^\*" | grep -vi "macOS" || echo "")

    local update_count=0
    if [[ -n "$update_list" ]]; then
        update_count=$(echo "$update_list" | wc -l | tr -d ' ')
    fi

    export APPSTORE_UPDATE_COUNT=$update_count

    if [[ $update_count -gt 0 ]]; then
        echo -e "  ${YELLOW}⚠${NC} App Store    ${YELLOW}${update_count} apps${NC} need update"
        echo -e "    ${GRAY}Run: ${GREEN}softwareupdate -i <label>${NC}"
    else
        echo -e "  ${GREEN}✓${NC} App Store    Up to date"
    fi
}

check_macos_update() {
    # Check for macOS system update using cached list
    local macos_update=""
    macos_update=$(get_software_updates | grep -i "macOS" | head -1 || echo "")

    export MACOS_UPDATE_AVAILABLE="false"

    if [[ -n "$macos_update" ]]; then
        export MACOS_UPDATE_AVAILABLE="true"
        local version=$(echo "$macos_update" | grep -o '[0-9]\+\.[0-9]\+\(\.[0-9]\+\)\?' | head -1)
        if [[ -n "$version" ]]; then
            echo -e "  ${YELLOW}⚠${NC} macOS        ${YELLOW}${version} available${NC}"
        else
            echo -e "  ${YELLOW}⚠${NC} macOS        ${YELLOW}Update available${NC}"
        fi
        echo -e "    ${GRAY}Run: ${GREEN}softwareupdate -i <label>${NC}"
    else
        echo -e "  ${GREEN}✓${NC} macOS        Up to date"
    fi
}

check_mole_update() {
    # Check if Mole has updates
    # Auto-detect version from mole main script
    local current_version
    if [[ -f "${SCRIPT_DIR:-/usr/local/bin}/mole" ]]; then
        current_version=$(grep '^VERSION=' "${SCRIPT_DIR:-/usr/local/bin}/mole" 2>/dev/null | head -1 | sed 's/VERSION="\(.*\)"/\1/' || echo "unknown")
    else
        current_version="${VERSION:-unknown}"
    fi

    local latest_version=""
    local cache_file="$CACHE_DIR/mole_version"

    export MOLE_UPDATE_AVAILABLE="false"

    # Check cache first
    if is_cache_valid "$cache_file"; then
        latest_version=$(cat "$cache_file" 2>/dev/null || echo "")
    else
        # Show spinner while checking
        if [[ -t 1 ]]; then
            start_inline_spinner "Checking Mole version..."
        fi

        # Try to get latest version from GitHub
        if command -v curl > /dev/null 2>&1; then
            latest_version=$(curl -fsSL https://api.github.com/repos/tw93/mole/releases/latest 2>/dev/null | grep '"tag_name"' | sed -E 's/.*"v?([^"]+)".*/\1/' || echo "")
            # Save to cache
            if [[ -n "$latest_version" ]]; then
                echo "$latest_version" > "$cache_file" 2>/dev/null || true
            fi
        fi

        # Stop spinner
        if [[ -t 1 ]]; then
            stop_inline_spinner
        fi
    fi

    # Normalize version strings (remove leading 'v' or 'V')
    current_version=$(echo "$current_version" | sed 's/^[vV]//')
    latest_version=$(echo "$latest_version" | sed 's/^[vV]//')

    if [[ -n "$latest_version" && "$current_version" != "$latest_version" ]]; then
        # Compare versions
        if [[ "$(printf '%s\n' "$current_version" "$latest_version" | sort -V | head -1)" == "$current_version" ]]; then
            export MOLE_UPDATE_AVAILABLE="true"
            echo -e "  ${YELLOW}⚠${NC} Mole         ${YELLOW}${latest_version} available${NC} (current: ${current_version})"
            echo -e "    ${GRAY}Run: ${GREEN}mo update${NC}"
        else
            echo -e "  ${GREEN}✓${NC} Mole         Up to date (${current_version})"
        fi
    else
        echo -e "  ${GREEN}✓${NC} Mole         Up to date (${current_version})"
    fi
}

check_all_updates() {
    # Reset spinner flag for softwareupdate
    unset SOFTWAREUPDATE_SPINNER_SHOWN

    check_homebrew_updates

    # Preload software update data to avoid delays between subsequent checks
    get_software_updates > /dev/null 2>&1

    check_appstore_updates
    check_macos_update
    check_mole_update
}

get_appstore_update_labels() {
    get_software_updates | awk '
        /^\*/ {
            label=$0
            sub(/^[[:space:]]*\* Label: */, "", label)
            sub(/,.*/, "", label)
            lower=tolower(label)
            if (index(lower, "macos") == 0) {
                print label
            }
        }
    '
}

get_macos_update_labels() {
    get_software_updates | awk '
        /^\*/ {
            label=$0
            sub(/^[[:space:]]*\* Label: */, "", label)
            sub(/,.*/, "", label)
            lower=tolower(label)
            if (index(lower, "macos") != 0) {
                print label
            }
        }
    '
}
