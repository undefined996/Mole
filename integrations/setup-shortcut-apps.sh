#!/bin/bash
# Create double-clickable Mole launchers (works great with Spotlight & Shortcuts).

set -euo pipefail

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ICON_STEP="➜"
ICON_SUCCESS="✓"
ICON_WARN="!"
ICON_ERR="✗"

log_step() { echo -e "${BLUE}${ICON_STEP}${NC} $1"; }
log_success() { echo -e "${GREEN}${ICON_SUCCESS}${NC} $1"; }
log_warn() { echo -e "${YELLOW}${ICON_WARN}${NC} $1"; }
log_error() { echo -e "${RED}${ICON_ERR}${NC} $1"; }

if ! command -v osascript >/dev/null 2>&1 || ! command -v osacompile >/dev/null 2>&1; then
    log_error "This installer needs AppleScript tools (osascript / osacompile). They ship with macOS."
    exit 1
fi

# Resolve Mole executable
if command -v mo >/dev/null 2>&1; then
    MO_BIN="$(command -v mo)"
elif command -v mole >/dev/null 2>&1; then
    MO_BIN="$(command -v mole)"
else
    log_error "Couldn't find Mole. Install via Homebrew or the install.sh script first."
    exit 1
fi

APP_DIR_BASE="${APP_DIR_BASE:-$HOME/Applications}"
mkdir -p "$APP_DIR_BASE"

declare -a ACTIONS=(
    "Mole Clean|$MO_BIN clean|Run full clean with Mole"
    "Mole Clean (Dry Run)|$MO_BIN clean --dry-run|Preview cleanup targets"
    "Mole Uninstall Apps|$MO_BIN uninstall|Interactive app uninstaller"
)

create_launcher() {
    local name="$1"
    local command="$2"
    local description="$3"
    local app_path="$APP_DIR_BASE/$name.app"
    local tmp_scpt

    tmp_scpt="$(mktemp)"
    # Escape backslashes and quotes for AppleScript literal
    local escaped_cmd="${command//\\/\\\\}"
    escaped_cmd="${escaped_cmd//\"/\\\"}"

    cat > "$tmp_scpt" <<EOF
on run
    set targetCommand to "${escaped_cmd}"
    tell application "Terminal"
        activate
        do script targetCommand
    end tell
end run
EOF

    osacompile -o "$app_path" "$tmp_scpt"
    rm -f "$tmp_scpt"

    /usr/bin/plutil -replace CFBundleIdentifier -string "fun.tw93.mole.$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]' )" "$app_path/Contents/Info.plist" 2>/dev/null || true
    /usr/bin/plutil -replace CFBundleDisplayName -string "$name" "$app_path/Contents/Info.plist" 2>/dev/null || true
    log_success "Created ${name} → ${app_path}"
    log_step "You can now launch it from Spotlight or add to macOS Shortcuts."
    echo "    ${description}"
}

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Mole macOS Launcher Creator"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

log_step "Installing launchers into: $APP_DIR_BASE"
for entry in "${ACTIONS[@]}"; do
    IFS="|" read -r name cmd desc <<< "$entry"
    create_launcher "$name" "$cmd" "$desc"
done

echo ""
log_step "Tip: open Shortcuts.app → New Shortcut → Add Action → 'Open App', then pick the launcher."
log_success "Done! Search Spotlight for “Mole Clean” to try it."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
