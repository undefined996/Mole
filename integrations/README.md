# Mole Integrations

Quick launcher integrations for Mole.

## Raycast + Alfred (clean & uninstall)

```bash
curl -fsSL https://raw.githubusercontent.com/tw93/Mole/main/integrations/setup-quick-launchers.sh | bash
```

This command:

- Adds two Raycast Script Commands (`clean`, `uninstall`) to the usual Raycast directories and opens the Script Commands panel so you can reload immediately.
- Creates two Alfred workflows with keywords `clean` and `uninstall` so you can type and run Mole in Alfred.
Both launchers call your locally installed `mo`/`mole` binary directly—no extra prompts or AppleScript permissions needed.

## Alfred

Add a workflow with keyword `clean` and script:

```bash
mo clean
```

For dry-run: `mo clean --dry-run`

For uninstall: `mo uninstall`

## Uninstall

```bash
rm -rf ~/Documents/Raycast/Scripts/mole-*.sh
rm -rf ~/Library/Application\ Support/Raycast/script-commands/mole-*.sh
# Alfred workflows live in:
# ~/Library/Application Support/Alfred/Alfred.alfredpreferences/workflows/user.workflow.*
```
