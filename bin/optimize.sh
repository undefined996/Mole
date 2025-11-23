#!/bin/bash

set -euo pipefail

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/optimize_health.sh"
source "$SCRIPT_DIR/lib/sudo_manager.sh"
source "$SCRIPT_DIR/lib/update_manager.sh"
source "$SCRIPT_DIR/lib/autofix_manager.sh"
source "$SCRIPT_DIR/lib/optimization_tasks.sh"

# Load check modules
source "$SCRIPT_DIR/lib/check_updates.sh"
source "$SCRIPT_DIR/lib/check_health.sh"
source "$SCRIPT_DIR/lib/check_security.sh"
source "$SCRIPT_DIR/lib/check_config.sh"

# Colors and icons from common.sh

print_header() {
    printf '\n'
    echo -e "${PURPLE}Optimize and Check${NC}"
    echo ""
}

# System check functions (real-time display)
run_system_checks() {
    echo ""
    echo -e "${PURPLE}System Check${NC}"
    echo ""

    # Check updates - real-time display
    echo -e "${BLUE}${ICON_ARROW}${NC} System updates"
    check_all_updates
    echo ""

    # Check health - real-time display
    echo -e "${BLUE}${ICON_ARROW}${NC} System health"
    check_system_health
    echo ""

    # Check security - real-time display
    echo -e "${BLUE}${ICON_ARROW}${NC} Security posture"
    check_all_security
    echo ""

    # Check configuration - real-time display
    echo -e "${BLUE}${ICON_ARROW}${NC} Configuration"
    check_all_config
    echo ""

    # Show suggestions
    show_suggestions
    echo ""

    # Ask about updates first
    if ask_for_updates; then
        perform_updates
    fi

    # Ask about auto-fix
    if ask_for_auto_fix; then
        perform_auto_fix
    fi
}

show_optimization_summary() {
    if [[ -z "${OPTIMIZE_SAFE_COUNT:-}" ]]; then
        return
    fi

    echo ""
    local summary_title="Optimization and Check Complete"
    local -a summary_details=()

    # Optimization results
    if ((OPTIMIZE_SAFE_COUNT > 0)); then
        summary_details+=("Applied ${GREEN}${OPTIMIZE_SAFE_COUNT}${NC} optimizations")
    else
        summary_details+=("System already optimized")
    fi

    if ((OPTIMIZE_CONFIRM_COUNT > 0)); then
        summary_details+=("${YELLOW}${OPTIMIZE_CONFIRM_COUNT}${NC} manual checks suggested")
    fi

    summary_details+=("Caches cleared, databases rebuilt, services refreshed")

    # System check results
    summary_details+=("System updates, health, security, and config reviewed")
    summary_details+=("System should feel faster and more responsive")

    if [[ "${OPTIMIZE_SHOW_TOUCHID_TIP:-false}" == "true" ]]; then
        echo -e "${YELLOW}☻${NC} Run ${GRAY}mo touchid${NC} to approve sudo via Touch ID"
    fi
    print_summary_block "success" "$summary_title" "${summary_details[@]}"
}


show_system_health() {
    local health_json="$1"

    # Parse system health using jq
    local mem_used=$(echo "$health_json" | jq -r '.memory_used_gb')
    local mem_total=$(echo "$health_json" | jq -r '.memory_total_gb')
    local disk_used=$(echo "$health_json" | jq -r '.disk_used_gb')
    local disk_total=$(echo "$health_json" | jq -r '.disk_total_gb')
    local disk_percent=$(echo "$health_json" | jq -r '.disk_used_percent')
    local uptime=$(echo "$health_json" | jq -r '.uptime_days')

    # Compact one-line format with icon
    printf "${ICON_ADMIN} System  %.0f/%.0f GB RAM | %.0f/%.0f GB Disk (%.0f%%) | Uptime %.0fd\n" \
        "$mem_used" "$mem_total" "$disk_used" "$disk_total" "$disk_percent" "$uptime"
    echo ""
}

parse_optimizations() {
    local health_json="$1"

    # Extract optimizations array
    echo "$health_json" | jq -c '.optimizations[]' 2> /dev/null
}

announce_action() {
    local name="$1"
    local desc="$2"
    local kind="$3"

    local badge=""
    if [[ "$kind" == "confirm" ]]; then
        badge="${YELLOW}[Confirm]${NC} "
    fi

    local line="${BLUE}${ICON_ARROW}${NC} ${badge}${name}"
    if [[ -n "$desc" ]]; then
        line+=" ${GRAY}- ${desc}${NC}"
    fi

    if ${first_heading:-true}; then
        first_heading=false
    else
        echo ""
    fi

    echo -e "$line"
}

touchid_configured() {
    local pam_file="/etc/pam.d/sudo"
    [[ -f "$pam_file" ]] && grep -q "pam_tid.so" "$pam_file" 2> /dev/null
}

touchid_supported() {
    if command -v bioutil > /dev/null 2>&1; then
        bioutil -r 2> /dev/null | grep -q "Touch ID" && return 0
    fi
    [[ "$(uname -m)" == "arm64" ]]
}

cleanup_path() {
    local raw_path="$1"
    local label="$2"

    local expanded_path="${raw_path/#\~/$HOME}"
    if [[ ! -e "$expanded_path" ]]; then
        echo -e "${GREEN}${ICON_SUCCESS}${NC} $label"
        return
    fi

    local size_kb
    size_kb=$(du -sk "$expanded_path" 2> /dev/null | awk '{print $1}' || echo "0")
    local size_display=""
    if [[ "$size_kb" =~ ^[0-9]+$ && "$size_kb" -gt 0 ]]; then
        size_display=$(bytes_to_human "$((size_kb * 1024))")
    fi

    local removed=false
    if rm -rf "$expanded_path" 2> /dev/null; then
        removed=true
    elif request_sudo_access "Removing $label requires admin access"; then
        if sudo rm -rf "$expanded_path" 2> /dev/null; then
            removed=true
        fi
    fi

    if [[ "$removed" == "true" ]]; then
        if [[ -n "$size_display" ]]; then
            echo -e "${GREEN}${ICON_SUCCESS}${NC} $label ${GREEN}(${size_display})${NC}"
        else
            echo -e "${GREEN}${ICON_SUCCESS}${NC} $label"
        fi
    else
        echo -e "${YELLOW}${ICON_WARNING}${NC} Skipped $label ${GRAY}(grant Full Disk Access to your terminal and retry)${NC}"
    fi
}

ensure_directory() {
    local raw_path="$1"
    local expanded_path="${raw_path/#\~/$HOME}"
    mkdir -p "$expanded_path" > /dev/null 2>&1 || true
}

count_local_snapshots() {
    if ! command -v tmutil > /dev/null 2>&1; then
        echo 0
        return
    fi

    local output
    output=$(tmutil listlocalsnapshots / 2> /dev/null || true)
    if [[ -z "$output" ]]; then
        echo 0
        return
    fi

    echo "$output" | grep -c "com.apple.TimeMachine." | tr -d ' '
}


cleanup_all() {
    stop_sudo_session
    cleanup_temp_files
}

main() {
    # Register unified cleanup handler
    trap cleanup_all EXIT INT TERM

    if [[ -t 1 ]]; then
        clear
    fi
    print_header

    # Check dependencies
    if ! command -v jq > /dev/null 2>&1; then
        echo -e "${RED}${ICON_ERROR}${NC} Missing dependency: jq"
        echo -e "${GRAY}Install with: ${GREEN}brew install jq${NC}"
        exit 1
    fi

    if ! command -v bc > /dev/null 2>&1; then
        echo -e "${RED}${ICON_ERROR}${NC} Missing dependency: bc"
        echo -e "${GRAY}Install with: ${GREEN}brew install bc${NC}"
        exit 1
    fi

    # Simple confirmation
    echo -ne "${PURPLE}${ICON_ARROW}${NC} Optimization needs sudo — ${GREEN}Enter${NC} continue, ${GRAY}ESC${NC} cancel: "

    local key
    if ! key=$(read_key); then
        echo -e " ${GRAY}Cancelled${NC}"
        exit 0
    fi

    if [[ "$key" == "ENTER" ]]; then
        printf "\r\033[K"
    else
        echo -e " ${GRAY}Cancelled${NC}"
        exit 0
    fi

    # Collect system health data after confirmation
    if [[ -t 1 ]]; then
        start_inline_spinner "Collecting system info..."
    fi

    local health_json
    if ! health_json=$(generate_health_json 2> /dev/null); then
        if [[ -t 1 ]]; then
            stop_inline_spinner
        fi
        echo ""
        log_error "Failed to collect system health data"
        exit 1
    fi

    if [[ -t 1 ]]; then
        stop_inline_spinner
    fi

    # Show system health
    show_system_health "$health_json"

    if [[ "${MO_DEBUG:-}" == "1" ]]; then
        echo "DEBUG: System health displayed"
    fi

    # Parse and display optimizations
    local -a safe_items=()
    local -a confirm_items=()

    if [[ "${MO_DEBUG:-}" == "1" ]]; then
        echo "DEBUG: Parsing optimizations..."
    fi

    # Use temp file instead of process substitution to avoid hanging
    local opts_file
    opts_file=$(mktemp_file)
    parse_optimizations "$health_json" > "$opts_file"

    if [[ "${MO_DEBUG:-}" == "1" ]]; then
        local opt_count=$(wc -l < "$opts_file" | tr -d ' ')
        echo "DEBUG: Found $opt_count optimizations"
    fi

    while IFS= read -r opt_json; do
        [[ -z "$opt_json" ]] && continue

        local name=$(echo "$opt_json" | jq -r '.name')
        local desc=$(echo "$opt_json" | jq -r '.description')
        local action=$(echo "$opt_json" | jq -r '.action')
        local path=$(echo "$opt_json" | jq -r '.path // ""')
        local safe=$(echo "$opt_json" | jq -r '.safe')

        local item="${name}|${desc}|${action}|${path}"

        if [[ "$safe" == "true" ]]; then
            safe_items+=("$item")
        else
            confirm_items+=("$item")
        fi
    done < "$opts_file"

    if [[ "${MO_DEBUG:-}" == "1" ]]; then
        echo "DEBUG: Parsing complete. Safe: ${#safe_items[@]}, Confirm: ${#confirm_items[@]}"
    fi

    # Execute all optimizations
    local first_heading=true

    # Debug: show what we're about to do
    if [[ "${MO_DEBUG:-}" == "1" ]]; then
        echo "DEBUG: About to request sudo. Safe items: ${#safe_items[@]}, Confirm items: ${#confirm_items[@]}"
    fi

    ensure_sudo_session "System optimization requires admin access" || true

    if [[ "${MO_DEBUG:-}" == "1" ]]; then
        echo "DEBUG: Sudo session established or skipped"
    fi

    # Run safe optimizations
    if [[ ${#safe_items[@]} -gt 0 ]]; then
        for item in "${safe_items[@]}"; do
            IFS='|' read -r name desc action path <<< "$item"
            announce_action "$name" "$desc" "safe"
            execute_optimization "$action" "$path"
        done
    fi

    # Run confirm items
    if [[ ${#confirm_items[@]} -gt 0 ]]; then
        for item in "${confirm_items[@]}"; do
            IFS='|' read -r name desc action path <<< "$item"
            announce_action "$name" "$desc" "confirm"
            execute_optimization "$action" "$path"
        done
    fi

    # Prepare optimization summary data (to show at the end)
    local safe_count=${#safe_items[@]}
    local confirm_count=${#confirm_items[@]}

    export OPTIMIZE_SAFE_COUNT=$safe_count
    export OPTIMIZE_CONFIRM_COUNT=$confirm_count
    export OPTIMIZE_SHOW_TOUCHID_TIP="false"
    if touchid_supported && ! touchid_configured; then
        export OPTIMIZE_SHOW_TOUCHID_TIP="true"
    fi

    # Run system checks first
    run_system_checks

    # Show optimization summary at the end
    show_optimization_summary

    printf '\n'
}

main "$@"
