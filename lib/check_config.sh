#!/bin/bash

# Configuration checks

check_touchid_sudo() {
    # Check if Touch ID is configured for sudo
    local pam_file="/etc/pam.d/sudo"
    if [[ -f "$pam_file" ]] && grep -q "pam_tid.so" "$pam_file" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Touch ID     Enabled for sudo"
    else
        # Check if Touch ID is supported
        local is_supported=false
        if command -v bioutil > /dev/null 2>&1; then
            if bioutil -r 2>/dev/null | grep -q "Touch ID"; then
                is_supported=true
            fi
        elif [[ "$(uname -m)" == "arm64" ]]; then
            is_supported=true
        fi

        if [[ "$is_supported" == "true" ]]; then
            echo -e "  ${YELLOW}⚠${NC} Touch ID     ${YELLOW}Not configured${NC} for sudo"
            export TOUCHID_NOT_CONFIGURED=true
        fi
    fi
}

check_rosetta() {
    # Check Rosetta 2 (for Apple Silicon Macs)
    if [[ "$(uname -m)" == "arm64" ]]; then
        if [[ -f "/Library/Apple/usr/share/rosetta/rosetta" ]]; then
            echo -e "  ${GREEN}✓${NC} Rosetta 2    Installed"
        else
            echo -e "  ${YELLOW}⚠${NC} Rosetta 2    ${YELLOW}Not installed${NC}"
            export ROSETTA_NOT_INSTALLED=true
        fi
    fi
}

check_git_config() {
    # Check basic Git configuration
    if command -v git > /dev/null 2>&1; then
        local git_name=$(git config --global user.name 2>/dev/null || echo "")
        local git_email=$(git config --global user.email 2>/dev/null || echo "")

        if [[ -n "$git_name" && -n "$git_email" ]]; then
            echo -e "  ${GREEN}✓${NC} Git Config   Configured"
        else
            echo -e "  ${YELLOW}⚠${NC} Git Config   ${YELLOW}Not configured${NC}"
        fi
    fi
}

check_all_config() {
    check_touchid_sudo
    check_rosetta
    check_git_config
}
