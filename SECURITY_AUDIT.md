# Mole Security Audit Report

**Date:** December 11, 2025

**Audited Version:** Current `main` branch

**Status:** Passed

---

## Security Philosophy: "Do No Harm"

Mole is designed with a **Zero Trust** architecture regarding file operations. Every request to modify the filesystem is treated as potentially dangerous until strictly validated. Our primary directive is to prioritize system stability over aggressive cleaning—we would rather leave 1GB of junk than delete 1KB of critical user data.

## 1. Multi-Layered Defense Architecture

Mole does not execute raw commands directly. All operations pass through a hardened middleware layer (`lib/core/file_ops.sh`).

### Layer 1: Input Sanitization

Before any operation reaches the execution stage, the target path is sanitized:

- **Absolute Path Enforcement**: Relative paths (e.g., `../foo`) are strictly rejected to prevent path traversal attacks.
- **Control Character Filtering**: Paths containing hidden control characters or newlines are blocked.
- **Empty Variable Protection**: Guards against shell scripting errors where an empty variable could result in `rm -rf /`.

### Layer 2: The "Iron Dome" (Path Validation)

A centralized validation logic explicitly blocks operations on critical system hierarchies, even with `sudo` privileges:

- `/` (Root)
- `/System`, `/usr`, `/bin`, `/sbin`, `/etc`, `/var`
- `/Library` (Root Library)
- `/Applications` (Root Applications)
- `/Users` (Root User Directory)

### Layer 3: Symlink Failsafe

For privileged (`sudo`) operations, Mole performs a pre-flight check to verify if the target is a **Symbolic Link**.

- **Risk**: A malicious or accidental symlink could point from a cache folder to a system file.
- **Defense**: Mole explicitly refuses to recursively delete symbolic links in privileged mode.

## 2. Conservative Cleaning Logic

### Orphaned Data: The "60-Day Rule"

Mole's "Smart Uninstall" and orphan detection (`lib/clean/apps.sh`) are intentionally conservative:

1. **Verification**: An app is confirmed "uninstalled" only if it is completely missing from `/Applications`, `~/Applications`, and `/System/Applications`.
2. **Dormancy Check**: Associated data folders are only flagged for removal if they have not been modified for **at least 60 days**.
3. **Vendor Whitelist**: A hardcoded whitelist protects shared resources from major vendors (Adobe, Microsoft, Google, etc.) to prevent breaking software suites.

### Active Uninstallation Heuristics

When a user explicitly selects an app for uninstallation, Mole employs advanced heuristics to find scattered remnants (e.g., "Visual Studio Code" -> `~/.vscode`, `~/Library/Application Support/VisualStudioCode`).

- **Sanitized Name Matching**: We search for app name variations (removing spaces, replacing with underscores) to catch non-standard folder naming.
- **Safety Constraints**: Fuzzy matching and sanitized name searches are **strictly disabled** for app names shorter than 4 characters to prevent false positives (e.g., an app named "Box" will not trigger a broad scan).
- **Plug-in & System Scope**: Mole scans specific system-level directories (`/Library/Audio/Plug-Ins`, `/Library/LaunchAgents`) for related components. These operations are subject to the same **Iron Dome** validation to ensure no critical system files are touched.

### System Integrity Protection (SIP) Awareness

Mole respects macOS SIP. It detects if SIP is enabled and automatically skips protected directories (like `/Library/Updates`) to avoid triggering permission errors or interfering with macOS updates.

### Time Machine Preservation

Before cleaning failed backups, Mole checks for the `backupd` process. If a backup is currently running, the cleanup task is strictly **aborted** to prevent data corruption.

## 3. Atomic Operations & Crash Safety

We anticipate that scripts can be interrupted (e.g., power loss, `Ctrl+C`).

- **Network Interface Reset**: Wi-Fi and AirDrop resets use **atomic execution blocks**. The script ignores termination signals (`SIGINT`, `SIGTERM`) during the critical 1-second window of resetting the interface, ensuring you are never left without a network connection.
- **Swap Clearing**: Swap files are only touched after verifying that the `dynamic_pager` daemon has successfully unloaded.

## 4. User Control & Transparency

- **Dry-Run Mode (`--dry-run`)**: We believe users should trust but verify. This mode simulates the entire cleanup process, listing every single file and byte that *would* be removed, without touching the disk.
- **Custom Whitelists**: Users can define their own immutable paths in `~/.config/mole/whitelist`. These paths are loaded into memory before any scan begins and serve as a "final override" to prevent deletion.

## 5. Dependency Audit

Mole relies on standard, battle-tested macOS binaries for critical tasks, minimizing the attack surface:

- `plutil`: Used to validate `.plist` integrity before modification.
- `tmutil`: Used for safe interaction with Time Machine snapshots.
- `kextcache`, `dscacheutil`: Used for system-compliant cache rebuilding.

---

*This document certifies that Mole's architecture implements industry-standard defensive programming practices to ensure the safety and integrity of your Mac.*
