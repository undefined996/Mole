# Mole Integrations

Quick launcher integrations for Mole.

## Shortcut Apps (Spotlight & Shortcuts)

Generate ready-to-use launcher apps (Clean / Dry Run / Uninstall):

```bash
curl -fsSL https://raw.githubusercontent.com/tw93/Mole/main/integrations/setup-shortcut-apps.sh | bash
```

This drops them into `~/Applications`, so you can trigger Mole via Spotlight, Dock, or Shortcuts (“Open App” action).  
Prefer to craft your own shortcut? Add “Run Shell Script”:

```bash
mo clean
```

Dry run: `mo clean --dry-run` • Uninstall: `mo uninstall`

## Alfred

Add a workflow with keyword `clean` and script:

```bash
mo clean
```

For dry-run: `mo clean --dry-run`

For uninstall: `mo uninstall`

## Uninstall

```bash
rm -rf ~/Applications/Mole\ Clean*.app
rm -rf ~/Applications/Mole\ Uninstall\ Apps.app
# Legacy Raycast script commands (if you installed them before switching)
rm -rf ~/Documents/Raycast/Scripts/mole-*.sh
rm -rf ~/Library/Application\ Support/Raycast/script-commands/mole-*.sh
```
