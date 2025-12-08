#!/bin/bash
# Mole - Common Functions Library
# Main entry point that loads all core modules

set -euo pipefail

# Prevent multiple sourcing
if [[ -n "${MOLE_COMMON_LOADED:-}" ]]; then
    return 0
fi
readonly MOLE_COMMON_LOADED=1

_MOLE_CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load core modules in dependency order
source "$_MOLE_CORE_DIR/base.sh"
source "$_MOLE_CORE_DIR/log.sh"
source "$_MOLE_CORE_DIR/timeout.sh"
source "$_MOLE_CORE_DIR/file_ops.sh"
source "$_MOLE_CORE_DIR/ui.sh"
source "$_MOLE_CORE_DIR/app_protection.sh"

# Load sudo management if available
if [[ -f "$_MOLE_CORE_DIR/sudo.sh" ]]; then
    source "$_MOLE_CORE_DIR/sudo.sh"
fi

# Update Mole via Homebrew
# Args: $1 = current version
update_via_homebrew() {
    local current_version="$1"

    if [[ -t 1 ]]; then
        start_inline_spinner "Updating Homebrew..."
    else
        echo "Updating Homebrew..."
    fi
    brew update 2>&1 | grep -Ev "^(==>|Already up-to-date)" || true
    if [[ -t 1 ]]; then
        stop_inline_spinner
    fi

    if [[ -t 1 ]]; then
        start_inline_spinner "Upgrading Mole..."
    else
        echo "Upgrading Mole..."
    fi
    local upgrade_output
    upgrade_output=$(brew upgrade mole 2>&1) || true
    if [[ -t 1 ]]; then
        stop_inline_spinner
    fi

    if echo "$upgrade_output" | grep -q "already installed"; then
        local installed_version
        installed_version=$(brew list --versions mole 2> /dev/null | awk '{print $2}')
        echo ""
        echo -e "${GREEN}${ICON_SUCCESS}${NC} Already on latest version (${installed_version:-$current_version})"
        echo ""
    elif echo "$upgrade_output" | grep -q "Error:"; then
        log_error "Homebrew upgrade failed"
        echo "$upgrade_output" | grep "Error:" >&2
        return 1
    else
        echo "$upgrade_output" | grep -Ev "^(==>|Updating Homebrew|Warning:)" || true
        local new_version
        new_version=$(brew list --versions mole 2> /dev/null | awk '{print $2}')
        echo ""
        echo -e "${GREEN}${ICON_SUCCESS}${NC} Updated to latest version (${new_version:-$current_version})"
        echo ""
    fi

    # Clear update cache
    rm -f "$HOME/.cache/mole/version_check" "$HOME/.cache/mole/update_message" 2> /dev/null || true
}
