// Mole System Optimizer
// System optimization and maintenance

package main

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"
)

type OptimizationItem struct {
	Category    string `json:"category"`
	Name        string `json:"name"`
	Description string `json:"description"`
	Action      string `json:"action"`
	Safe        bool   `json:"safe"`
}

type SystemHealth struct {
	MemoryUsedGB    float64            `json:"memory_used_gb"`
	MemoryTotalGB   float64            `json:"memory_total_gb"`
	DiskUsedGB      float64            `json:"disk_used_gb"`
	DiskTotalGB     float64            `json:"disk_total_gb"`
	DiskUsedPercent float64            `json:"disk_used_percent"`
	UptimeDays      float64            `json:"uptime_days"`
	Optimizations   []OptimizationItem `json:"optimizations"`
}

func main() {
	health := collectSystemHealth()

	encoder := json.NewEncoder(os.Stdout)
	encoder.SetIndent("", "  ")
	if err := encoder.Encode(health); err != nil {
		fmt.Fprintf(os.Stderr, "Error encoding JSON: %v\n", err)
		os.Exit(1)
	}
}

func collectSystemHealth() SystemHealth {
	health := SystemHealth{
		Optimizations: []OptimizationItem{},
	}

	// Collect system info
	health.MemoryUsedGB, health.MemoryTotalGB = getMemoryInfo()
	health.DiskUsedGB, health.DiskTotalGB, health.DiskUsedPercent = getDiskInfo()
	health.UptimeDays = getUptimeDays()

	// System optimizations (always show)
	health.Optimizations = append(health.Optimizations, OptimizationItem{
		Category:    "system",
		Name:        "System Maintenance",
		Description: "Rebuild system databases & flush caches",
		Action:      "system_maintenance",
		Safe:        true,
	})

	// Startup items (conditional)
	if item := checkStartupItems(); item != nil {
		health.Optimizations = append(health.Optimizations, *item)
	}

	// Network services (always show)
	health.Optimizations = append(health.Optimizations, OptimizationItem{
		Category:    "network",
		Name:        "Network Services",
		Description: "Reset network services",
		Action:      "network_services",
		Safe:        true,
	})

	// Cache refresh (always available)
	if item := buildCacheRefreshItem(); item != nil {
		health.Optimizations = append(health.Optimizations, *item)
	}

	// macOS maintenance scripts (always available)
	health.Optimizations = append(health.Optimizations, OptimizationItem{
		Category:    "maintenance",
		Name:        "Maintenance Scripts",
		Description: "Run daily/weekly/monthly scripts & rotate logs",
		Action:      "maintenance_scripts",
		Safe:        true,
	})

	// Wireless preferences refresh (always available)
	health.Optimizations = append(health.Optimizations, OptimizationItem{
		Category:    "network",
		Name:        "Bluetooth & Wi-Fi Refresh",
		Description: "Reset wireless preference caches",
		Action:      "radio_refresh",
		Safe:        true,
	})

	// Recent items cleanup (always available)
	health.Optimizations = append(health.Optimizations, OptimizationItem{
		Category:    "privacy",
		Name:        "Recent Items",
		Description: "Clear recent apps/documents/servers lists",
		Action:      "recent_items",
		Safe:        true,
	})

	// Diagnostic log cleanup (always available)
	health.Optimizations = append(health.Optimizations, OptimizationItem{
		Category:    "system",
		Name:        "Diagnostics Cleanup",
		Description: "Purge old diagnostic & crash logs",
		Action:      "log_cleanup",
		Safe:        true,
	})

	if item := buildMailDownloadsItem(); item != nil {
		health.Optimizations = append(health.Optimizations, *item)
	}

	if item := buildSavedStateItem(); item != nil {
		health.Optimizations = append(health.Optimizations, *item)
	}

	health.Optimizations = append(health.Optimizations, OptimizationItem{
		Category:    "interface",
		Name:        "Finder & Dock Refresh",
		Description: "Clear Finder/Dock caches and restart",
		Action:      "finder_dock_refresh",
		Safe:        true,
	})

	if item := buildSwapCleanupItem(); item != nil {
		health.Optimizations = append(health.Optimizations, *item)
	}

	if item := buildLoginItemsItem(); item != nil {
		health.Optimizations = append(health.Optimizations, *item)
	}

	health.Optimizations = append(health.Optimizations, OptimizationItem{
		Category:    "system",
		Name:        "Startup Cache Rebuild",
		Description: "Rebuild kext caches & prelinked kernel",
		Action:      "startup_cache",
		Safe:        true,
	})

	// Local snapshot thinning (conditional)
	if item := checkLocalSnapshots(); item != nil {
		health.Optimizations = append(health.Optimizations, *item)
	}

	// Developer-focused cleanup (conditional)
	if item := checkDeveloperCleanup(); item != nil {
		health.Optimizations = append(health.Optimizations, *item)
	}

	return health
}

func getMemoryInfo() (float64, float64) {
	cmd := exec.Command("sysctl", "-n", "hw.memsize")
	output, err := cmd.Output()
	if err != nil {
		return 0, 0
	}

	totalBytes, err := strconv.ParseInt(strings.TrimSpace(string(output)), 10, 64)
	if err != nil {
		return 0, 0
	}
	totalGB := float64(totalBytes) / (1024 * 1024 * 1024)

	// Get used memory via vm_stat
	cmd = exec.Command("vm_stat")
	output, err = cmd.Output()
	if err != nil {
		return 0, totalGB
	}

	var pageSize int64 = 4096
	var active, wired, compressed int64

	lines := strings.Split(string(output), "\n")
	for _, line := range lines {
		if strings.Contains(line, "Pages active:") {
			active = parseVMStatLine(line)
		} else if strings.Contains(line, "Pages wired down:") {
			wired = parseVMStatLine(line)
		} else if strings.Contains(line, "Pages occupied by compressor:") {
			compressed = parseVMStatLine(line)
		}
	}

	usedBytes := (active + wired + compressed) * pageSize
	usedGB := float64(usedBytes) / (1024 * 1024 * 1024)

	return usedGB, totalGB
}

func parseVMStatLine(line string) int64 {
	fields := strings.Fields(line)
	if len(fields) < 2 {
		return 0
	}
	numStr := strings.TrimSuffix(fields[len(fields)-1], ".")
	num, _ := strconv.ParseInt(numStr, 10, 64)
	return num
}

func getUptimeDays() float64 {
	cmd := exec.Command("sysctl", "-n", "kern.boottime")
	output, err := cmd.Output()
	if err != nil {
		return 0
	}

	line := string(output)
	if idx := strings.Index(line, "sec = "); idx != -1 {
		secStr := line[idx+6:]
		if endIdx := strings.Index(secStr, ","); endIdx != -1 {
			secStr = secStr[:endIdx]
			if bootTime, err := strconv.ParseInt(strings.TrimSpace(secStr), 10, 64); err == nil {
				uptime := time.Now().Unix() - bootTime
				return float64(uptime) / (24 * 3600)
			}
		}
	}
	return 0
}

func getDiskInfo() (float64, float64, float64) {
	var stat syscall.Statfs_t
	home, err := os.UserHomeDir()
	if err != nil {
		home = "/"
	}

	if err := syscall.Statfs(home, &stat); err != nil {
		return 0, 0, 0
	}

	totalBytes := stat.Blocks * uint64(stat.Bsize)
	freeBytes := stat.Bfree * uint64(stat.Bsize)
	usedBytes := totalBytes - freeBytes

	totalGB := float64(totalBytes) / (1024 * 1024 * 1024)
	usedGB := float64(usedBytes) / (1024 * 1024 * 1024)
	usedPercent := (float64(usedBytes) / float64(totalBytes)) * 100

	return usedGB, totalGB, usedPercent
}

func checkStartupItems() *OptimizationItem {
	launchAgentsCount := 0
	agentsDirs := []string{
		filepath.Join(os.Getenv("HOME"), "Library/LaunchAgents"),
		"/Library/LaunchAgents",
	}

	for _, dir := range agentsDirs {
		if entries, err := os.ReadDir(dir); err == nil {
			launchAgentsCount += len(entries)
		}
	}

	if launchAgentsCount > 5 {
		suggested := launchAgentsCount / 2
		if suggested < 1 {
			suggested = 1
		}
		return &OptimizationItem{
			Category:    "startup",
			Name:        "Startup Items",
			Description: fmt.Sprintf("%d items (suggest disable %d)", launchAgentsCount, suggested),
			Action:      "startup_items",
			Safe:        false,
		}
	}
	return nil
}

func buildCacheRefreshItem() *OptimizationItem {
	desc := "Refresh Finder previews, Quick Look, and Safari caches"
	if home, err := os.UserHomeDir(); err == nil {
		cacheDir := filepath.Join(home, "Library", "Caches")
		if sizeKB := dirSizeKB(cacheDir); sizeKB > 0 {
			desc = fmt.Sprintf("Refresh %s of Finder/Safari caches", formatSizeFromKB(sizeKB))
		}
	}

	return &OptimizationItem{
		Category:    "cache",
		Name:        "User Cache Refresh",
		Description: desc,
		Action:      "cache_refresh",
		Safe:        true,
	}
}

func buildMailDownloadsItem() *OptimizationItem {
	home, err := os.UserHomeDir()
	if err != nil {
		return nil
	}

	dirs := []string{
		filepath.Join(home, "Library", "Mail Downloads"),
		filepath.Join(home, "Library", "Containers", "com.apple.mail", "Data", "Library", "Mail Downloads"),
	}

	var totalKB int64
	for _, dir := range dirs {
		totalKB += dirSizeKB(dir)
	}

	if totalKB == 0 {
		return nil
	}

	return &OptimizationItem{
		Category:    "applications",
		Name:        "Mail Downloads",
		Description: fmt.Sprintf("Recover %s of Mail attachments", formatSizeFromKB(totalKB)),
		Action:      "mail_downloads",
		Safe:        true,
	}
}

func buildSavedStateItem() *OptimizationItem {
	home, err := os.UserHomeDir()
	if err != nil {
		return nil
	}

	stateDir := filepath.Join(home, "Library", "Saved Application State")
	sizeKB := dirSizeKB(stateDir)
	if sizeKB == 0 {
		return nil
	}

	return &OptimizationItem{
		Category:    "system",
		Name:        "Saved State",
		Description: fmt.Sprintf("Clear %s of stale saved states", formatSizeFromKB(sizeKB)),
		Action:      "saved_state_cleanup",
		Safe:        true,
	}
}

func buildSwapCleanupItem() *OptimizationItem {
	swapGlob := "/private/var/vm/swapfile*"
	matches, err := filepath.Glob(swapGlob)
	if err != nil {
		return nil
	}

	var totalKB int64
	for _, file := range matches {
		info, err := os.Stat(file)
		if err != nil {
			continue
		}
		totalKB += info.Size() / 1024
	}

	if totalKB == 0 {
		return nil
	}

	return &OptimizationItem{
		Category:    "memory",
		Name:        "Memory & Swap",
		Description: fmt.Sprintf("Purge swap (%s) & inactive memory", formatSizeFromKB(totalKB)),
		Action:      "swap_cleanup",
		Safe:        false,
	}
}

func buildLoginItemsItem() *OptimizationItem {
	items := listLoginItems()
	if len(items) == 0 {
		return nil
	}

	return &OptimizationItem{
		Category:    "startup",
		Name:        "Login Items",
		Description: fmt.Sprintf("Review %d login items", len(items)),
		Action:      "login_items",
		Safe:        true,
	}
}

func listLoginItems() []string {
	cmd := exec.Command("osascript", "-e", "tell application \"System Events\" to get the name of every login item")
	output, err := cmd.Output()
	if err != nil {
		return nil
	}

	line := strings.TrimSpace(string(output))
	if line == "" || line == "missing value" {
		return nil
	}

	parts := strings.Split(line, ", ")
	var items []string
	for _, part := range parts {
		name := strings.TrimSpace(part)
		name = strings.Trim(name, "\"")
		if name != "" {
			items = append(items, name)
		}
	}
	return items
}

func checkLocalSnapshots() *OptimizationItem {
	if _, err := exec.LookPath("tmutil"); err != nil {
		return nil
	}

	cmd := exec.Command("tmutil", "listlocalsnapshots", "/")
	output, err := cmd.Output()
	if err != nil {
		return nil
	}

	lines := strings.Split(strings.TrimSpace(string(output)), "\n")
	count := 0
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "com.apple.TimeMachine.") {
			count++
		}
	}

	if count == 0 {
		return nil
	}

	return &OptimizationItem{
		Category:    "storage",
		Name:        "Local Snapshots",
		Description: fmt.Sprintf("%d APFS local snapshots detected", count),
		Action:      "local_snapshots",
		Safe:        true,
	}
}

func checkDeveloperCleanup() *OptimizationItem {
	home, err := os.UserHomeDir()
	if err != nil {
		return nil
	}

	dirs := []string{
		filepath.Join(home, "Library", "Developer", "Xcode", "DerivedData"),
		filepath.Join(home, "Library", "Developer", "Xcode", "Archives"),
		filepath.Join(home, "Library", "Developer", "Xcode", "iOS DeviceSupport"),
		filepath.Join(home, "Library", "Developer", "CoreSimulator", "Caches"),
	}

	var totalKB int64
	for _, dir := range dirs {
		totalKB += dirSizeKB(dir)
	}

	if totalKB == 0 {
		return nil
	}

	return &OptimizationItem{
		Category:    "developer",
		Name:        "Developer Cleanup",
		Description: fmt.Sprintf("Recover %s of Xcode/simulator data", formatSizeFromKB(totalKB)),
		Action:      "developer_cleanup",
		Safe:        false,
	}
}

func dirSizeKB(path string) int64 {
	if path == "" {
		return 0
	}

	if _, err := os.Stat(path); err != nil {
		return 0
	}

	cmd := exec.Command("du", "-sk", path)
	output, err := cmd.Output()
	if err != nil {
		return 0
	}

	fields := strings.Fields(string(output))
	if len(fields) == 0 {
		return 0
	}

	size, err := strconv.ParseInt(fields[0], 10, 64)
	if err != nil {
		return 0
	}

	return size
}

func formatSizeFromKB(kb int64) string {
	if kb <= 0 {
		return "0B"
	}

	mb := float64(kb) / 1024
	gb := mb / 1024

	switch {
	case gb >= 1:
		return fmt.Sprintf("%.1fGB", gb)
	case mb >= 1:
		return fmt.Sprintf("%.0fMB", mb)
	default:
		return fmt.Sprintf("%dKB", kb)
	}
}
