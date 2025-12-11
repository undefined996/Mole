# Mole Security Audit Report

**Date:** December 11, 2025
**Status:** Passed

## Executive Summary

This document outlines the safety mechanisms, defensive programming strategies, and architectural decisions implemented in Mole to ensure user data integrity and system stability. Our primary design philosophy is **"Safety First"**—we prioritize system stability over aggressive cleaning.

## 1. Core Safety Mechanisms (`lib/core/file_ops.sh`)

All file modification and deletion operations are routed through a centralized, hardened library. No script performs raw `rm -rf` commands directly.

* **Mandatory Path Validation**: Every deletion request (`safe_remove`, `safe_sudo_remove`) undergoes strict validation before execution.
* **Root Directory Protection**: The system explicitly rejects operations on critical system paths (`/`, `/bin`, `/usr`, `/etc`, `/var`, `/System`, etc.), even if variables resolve to these paths unexpectedly.
* **Symlink Guard**: `sudo` operations explicitly check for and refuse to traverse or delete symbolic links. This prevents "symlink attacks" where a malicious or accidental link could redirect deletion to critical system files.
* **Path Traversal Prevention**: Paths containing `..` are strictly rejected to prevent escaping the target directory.

## 2. Conservative Cleanup Strategy (`lib/clean/`)

Mole employs a conservative approach to cleaning to avoid "false positives" that could damage user data.

* **Orphaned Data Protection**:
  * Applications are only considered "orphaned" if they are completely missing from `/Applications` **AND** their data has been inactive for **60+ days**.
  * **Vendor Whitelist**: A hardcoded whitelist protects data from major vendors (Adobe, Microsoft, Google, etc.) to prevent accidental configuration loss.
* **SIP Awareness**: The cleanup logic detects macOS System Integrity Protection (SIP) status. It automatically skips protected areas (like `/Library/Updates`) if SIP is enabled to avoid permission errors and maintain system integrity.
* **Time Machine Safety**: Cleanup of failed Time Machine backups is intelligently paused if a backup session (`backupd` process) is currently active, preventing corruption of ongoing backups.

## 3. Optimization Safety (`lib/optimize/`)

* **Standard macOS Tools**: Optimizations rely on official macOS maintenance binaries (`dscacheutil`, `mdutil`, `kextcache`, `periodic`) rather than manual file manipulation wherever possible.
* **Atomic Network Reset**: Network interface resets (Wi-Fi/AirDrop) utilize **atomic execution blocks**. This ensures that even if the script is forcibly interrupted (e.g., via `Ctrl+C`) during a reset, the network interface will automatically recover, preventing persistent connectivity loss.
* **Safe Swap Clearing**: Swap files are only cleared after successfully verifying the `dynamic_pager` daemon has unloaded.

## 4. User Verification & Control

* **Dry-Run Mode**: Users can verify every single file that *would* be deleted using `mo clean --dry-run` (or `-n`) without touching the filesystem.
* **Custom Whitelists**: Users can safeguard specific paths by adding them to `~/.config/mole/whitelist`.

---

*This report verifies that Mole's architecture includes multiple layers of redundancy and safety checks to prevent data loss and system damage.*
