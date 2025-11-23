#!/bin/bash

# System health checks
# Sets global variables for use in suggestions

check_disk_space() {
    local free_gb=$(df -H / | awk 'NR==2 {print $4}' | sed 's/G//')
    local free_num=$(echo "$free_gb" | tr -d 'G' | cut -d'.' -f1)

    export DISK_FREE_GB=$free_num

    if [[ $free_num -lt 20 ]]; then
        echo -e "  ${RED}✗${NC} Disk Space   ${RED}${free_gb}GB free${NC} (Critical)"
    elif [[ $free_num -lt 50 ]]; then
        echo -e "  ${YELLOW}⚠${NC} Disk Space   ${YELLOW}${free_gb}GB free${NC} (Low)"
    else
        echo -e "  ${GREEN}✓${NC} Disk Space   ${free_gb}GB free"
    fi
}

check_memory_usage() {
    local mem_total
    mem_total=$(sysctl -n hw.memsize 2>/dev/null || echo "0")
    if [[ -z "$mem_total" || "$mem_total" -le 0 ]]; then
        echo -e "  ${GRAY}-${NC} Memory       Unable to determine"
        return
    fi

    local vm_output
    vm_output=$(vm_stat 2>/dev/null || echo "")

    local page_size
    page_size=$(echo "$vm_output" | awk '/page size of/ {print $8}')
    [[ -z "$page_size" ]] && page_size=4096

    local free_pages inactive_pages spec_pages
    free_pages=$(echo "$vm_output" | awk '/Pages free/ {gsub(/\./,"",$3); print $3}')
    inactive_pages=$(echo "$vm_output" | awk '/Pages inactive/ {gsub(/\./,"",$3); print $3}')
    spec_pages=$(echo "$vm_output" | awk '/Pages speculative/ {gsub(/\./,"",$3); print $3}')

    free_pages=${free_pages:-0}
    inactive_pages=${inactive_pages:-0}
    spec_pages=${spec_pages:-0}

    # Estimate used percent: (total - free - inactive - speculative) / total
    local total_pages=$((mem_total / page_size))
    local free_total=$((free_pages + inactive_pages + spec_pages))
    local used_pages=$((total_pages - free_total))
    if ((used_pages < 0)); then
        used_pages=0
    fi

    local used_percent
    used_percent=$(awk "BEGIN {printf \"%.0f\", ($used_pages / $total_pages) * 100}")
    ((used_percent > 100)) && used_percent=100
    ((used_percent < 0)) && used_percent=0

    if [[ $used_percent -gt 90 ]]; then
        echo -e "  ${RED}✗${NC} Memory       ${RED}${used_percent}% used${NC} (Critical)"
    elif [[ $used_percent -gt 80 ]]; then
        echo -e "  ${YELLOW}⚠${NC} Memory       ${YELLOW}${used_percent}% used${NC} (High)"
    else
        echo -e "  ${GREEN}✓${NC} Memory       ${used_percent}% used"
    fi
}

check_login_items() {
    local login_items_count=0
    local -a login_items_list=()

    if [[ -t 0 ]]; then
        # Show spinner while getting login items
        if [[ -t 1 ]]; then
            start_inline_spinner "Checking login items..."
        fi

        while IFS= read -r login_item; do
            [[ -n "$login_item" ]] && login_items_list+=("$login_item")
        done < <(list_login_items || true)
        login_items_count=${#login_items_list[@]}

        # Stop spinner before output
        if [[ -t 1 ]]; then
            stop_inline_spinner
        fi
    fi

    if [[ $login_items_count -gt 15 ]]; then
        echo -e "  ${YELLOW}⚠${NC} Login Items  ${YELLOW}${login_items_count} apps${NC} auto-start (High)"
    elif [[ $login_items_count -gt 0 ]]; then
        echo -e "  ${GREEN}✓${NC} Login Items  ${login_items_count} apps auto-start"
    else
        echo -e "  ${GREEN}✓${NC} Login Items  None"
        return
    fi

    # Show items in a single line
    local preview_limit=5
    ((preview_limit > login_items_count)) && preview_limit=$login_items_count

    local items_display=""
    for ((i = 0; i < preview_limit; i++)); do
        if [[ $i -eq 0 ]]; then
            items_display="${login_items_list[$i]}"
        else
            items_display="${items_display}, ${login_items_list[$i]}"
        fi
    done

    if ((login_items_count > preview_limit)); then
        local remaining=$((login_items_count - preview_limit))
        items_display="${items_display}, and ${remaining} more"
    fi

    echo -e "    ${GRAY}${items_display}${NC}"
    echo -e "    ${GRAY}Manage in System Settings → Login Items${NC}"
}

check_cache_size() {
    local cache_size_kb=0

    # Check common cache locations
    local -a cache_paths=(
        "$HOME/Library/Caches"
        "$HOME/Library/Logs"
    )

    # Show spinner while calculating cache size
    if [[ -t 1 ]]; then
        start_inline_spinner "Scanning cache..."
    fi

    for cache_path in "${cache_paths[@]}"; do
        if [[ -d "$cache_path" ]]; then
            local size_output
            size_output=$(du -sk "$cache_path" 2>/dev/null | awk 'NR==1 {print $1}' | tr -d '[:space:]' || echo "")
            [[ "$size_output" =~ ^[0-9]+$ ]] || size_output=0
            cache_size_kb=$((cache_size_kb + size_output))
        fi
    done

    local cache_size_gb=$(echo "scale=1; $cache_size_kb / 1024 / 1024" | bc)
    export CACHE_SIZE_GB=$cache_size_gb

    # Stop spinner before output
    if [[ -t 1 ]]; then
        stop_inline_spinner
    fi

    # Convert to integer for comparison
    local cache_size_int=$(echo "$cache_size_gb" | cut -d'.' -f1)

    if [[ $cache_size_int -gt 10 ]]; then
        echo -e "  ${YELLOW}⚠${NC} Cache Size   ${YELLOW}${cache_size_gb}GB${NC} cleanable"
    elif [[ $cache_size_int -gt 5 ]]; then
        echo -e "  ${YELLOW}⚠${NC} Cache Size   ${YELLOW}${cache_size_gb}GB${NC} cleanable"
    else
        echo -e "  ${GREEN}✓${NC} Cache Size   ${cache_size_gb}GB"
    fi
}

check_swap_usage() {
    # Check swap usage
    if command -v sysctl > /dev/null 2>&1; then
        local swap_info=$(sysctl vm.swapusage 2>/dev/null || echo "")
        if [[ -n "$swap_info" ]]; then
            local swap_used=$(echo "$swap_info" | grep -o "used = [0-9.]*[GM]" | awk '{print $3}' || echo "0M")
            local swap_num=$(echo "$swap_used" | sed 's/[GM]//')

            if [[ "$swap_used" == *"G"* ]]; then
                local swap_gb=${swap_num%.*}
                if [[ $swap_gb -gt 2 ]]; then
                    echo -e "  ${YELLOW}⚠${NC} Swap Usage   ${YELLOW}${swap_used}${NC} (High)"
                else
                    echo -e "  ${GREEN}✓${NC} Swap Usage   ${swap_used}"
                fi
            else
                echo -e "  ${GREEN}✓${NC} Swap Usage   ${swap_used}"
            fi
        fi
    fi
}

check_timemachine() {
    # Check Time Machine backup status
    if command -v tmutil > /dev/null 2>&1; then
        local tm_status=$(tmutil latestbackup 2>/dev/null || echo "")
        if [[ -z "$tm_status" ]]; then
            echo -e "  ${YELLOW}⚠${NC} Time Machine No backups found"
            echo -e "    ${GRAY}Set up in System Settings → General → Time Machine (optional but recommended)${NC}"
        else
            # Get last backup time
            local backup_date=$(tmutil latestbackup 2>/dev/null | xargs basename 2>/dev/null || echo "")
            if [[ -n "$backup_date" ]]; then
                echo -e "  ${GREEN}✓${NC} Time Machine Backup active"
            else
                echo -e "  ${YELLOW}⚠${NC} Time Machine Not configured"
            fi
        fi
    fi
}

check_brew_health() {
    # Check Homebrew doctor
    if command -v brew > /dev/null 2>&1; then
        # Show spinner while running brew doctor
        if [[ -t 1 ]]; then
            start_inline_spinner "Running brew doctor..."
        fi

        local brew_doctor=$(brew doctor 2>&1 || echo "")

        # Stop spinner before output
        if [[ -t 1 ]]; then
            stop_inline_spinner
        fi

        if echo "$brew_doctor" | grep -q "ready to brew"; then
            echo -e "  ${GREEN}✓${NC} Homebrew     Healthy"
        else
            local warning_count=$(echo "$brew_doctor" | grep -c "Warning:" || echo "0")
            if [[ $warning_count -gt 0 ]]; then
                echo -e "  ${YELLOW}⚠${NC} Homebrew     ${YELLOW}${warning_count} warnings${NC}"
                echo -e "    ${GRAY}Run: ${GREEN}brew doctor${NC} to see fixes, then rerun until clean${NC}"
                export BREW_HAS_WARNINGS=true
            else
                echo -e "  ${GREEN}✓${NC} Homebrew     Healthy"
            fi
        fi
    fi
}

check_system_health() {
    check_disk_space
    check_memory_usage
    check_swap_usage
    check_login_items
    check_cache_size
    # Time Machine check is optional; skip by default to avoid noise on systems without backups
    check_brew_health
}
