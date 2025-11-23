#!/bin/bash

# Security checks

check_filevault() {
    # Check FileVault encryption status
    if command -v fdesetup > /dev/null 2>&1; then
        local fv_status=$(fdesetup status 2>/dev/null || echo "")
        if echo "$fv_status" | grep -q "FileVault is On"; then
            echo -e "  ${GREEN}✓${NC} FileVault    Enabled"
        else
            echo -e "  ${RED}✗${NC} FileVault    ${RED}Disabled${NC} (Recommend enabling)"
            export FILEVAULT_DISABLED=true
        fi
    fi
}

check_firewall() {
    # Check firewall status
    local firewall_status=$(defaults read /Library/Preferences/com.apple.alf globalstate 2>/dev/null || echo "0")
    if [[ "$firewall_status" == "1" || "$firewall_status" == "2" ]]; then
        echo -e "  ${GREEN}✓${NC} Firewall     Enabled"
    else
        echo -e "  ${YELLOW}⚠${NC} Firewall     ${YELLOW}Disabled${NC} (Consider enabling)"
        echo -e "    ${GRAY}System Settings → Network → Firewall, or run:${NC}"
        echo -e "    ${GRAY}sudo defaults write /Library/Preferences/com.apple.alf globalstate -int 1${NC}"
        export FIREWALL_DISABLED=true
    fi
}

check_gatekeeper() {
    # Check Gatekeeper status
    if command -v spctl > /dev/null 2>&1; then
        local gk_status=$(spctl --status 2>/dev/null || echo "")
        if echo "$gk_status" | grep -q "enabled"; then
            echo -e "  ${GREEN}✓${NC} Gatekeeper   Active"
        else
            echo -e "  ${YELLOW}⚠${NC} Gatekeeper   ${YELLOW}Disabled${NC}"
            echo -e "    ${GRAY}Enable via System Settings → Privacy & Security, or:${NC}"
            echo -e "    ${GRAY}sudo spctl --master-enable${NC}"
        fi
    fi
}

check_sip() {
    # Check System Integrity Protection
    if command -v csrutil > /dev/null 2>&1; then
        local sip_status=$(csrutil status 2>/dev/null || echo "")
        if echo "$sip_status" | grep -q "enabled"; then
            echo -e "  ${GREEN}✓${NC} SIP          Enabled"
        else
            echo -e "  ${YELLOW}⚠${NC} SIP          ${YELLOW}Disabled${NC}"
            echo -e "    ${GRAY}Restart into Recovery → Utilities → Terminal → run: csrutil enable${NC}"
        fi
    fi
}

check_all_security() {
    check_filevault
    check_firewall
    check_gatekeeper
    check_sip
}
