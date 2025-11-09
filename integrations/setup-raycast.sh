#!/bin/bash
# One-line Raycast integration installer
# Usage: curl -fsSL https://raw.githubusercontent.com/tw93/Mole/main/integrations/setup-raycast.sh | bash

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

DEFAULT_DIR="$HOME/Library/Application Support/Raycast/script-commands"
ALT_DIR="$HOME/Documents/Raycast/Scripts"
RAYCAST_DIRS=()

if [[ -d "$DEFAULT_DIR" ]]; then
    RAYCAST_DIRS+=("$DEFAULT_DIR")
fi
if [[ -d "$ALT_DIR" ]]; then
    RAYCAST_DIRS+=("$ALT_DIR")
fi
if [[ ${#RAYCAST_DIRS[@]} -eq 0 ]]; then
    RAYCAST_DIRS+=("$DEFAULT_DIR")
fi

BASE_URL="https://raw.githubusercontent.com/tw93/Mole/main/integrations/raycast"
SCRIPTS=(mole-clean.sh mole-clean-dry-run.sh mole-uninstall.sh)

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Mole × Raycast Script Commands"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

log_step "Checking Raycast installation..."
if [[ ! -d "/Applications/Raycast.app" ]]; then
    log_warn "Raycast not found. Install it from https://raycast.com"
    exit 1
fi

log_step "Syncing scripts (${#SCRIPTS[@]}) to Raycast directories..."
for dir in "${RAYCAST_DIRS[@]}"; do
    mkdir -p "$dir"
    for script in "${SCRIPTS[@]}"; do
        curl -fsSL "$BASE_URL/$script" -o "$dir/$script"
        chmod +x "$dir/$script"
    done
    log_success "Scripts ready in: $dir"
done

echo ""
log_success "All set! Next steps:"
cat <<INSTRUCTIONS
  1. Open Raycast and run "Reload Script Directories".
  2. Search for "Clean Mac" / "Dry Run" / "Uninstall Apps".
  3. Missing? Open Raycast Settings → Extensions → Script Commands
     and add $(printf '"%s" ' "${RAYCAST_DIRS[@]}").
INSTRUCTIONS

if open "raycast://extensions/script-commands" > /dev/null 2>&1; then
    log_step "Raycast settings opened so you can confirm the directory."
else
    log_warn "Could not auto-open Raycast. Launch it manually if needed."
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
