package main

import (
	"fmt"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	tea "github.com/charmbracelet/bubbletea"
)

const (
	maxEntries       = 20
	maxLargeFiles    = 20
	barWidth         = 24
	minLargeFileSize = 100 << 20 // 100 MB
	entryViewport    = 10
	largeViewport    = 10
)

// Directories to fold: calculate size but don't expand children
var foldDirs = map[string]bool{
	".git":          true,
	"node_modules":  true,
	".Trash":        true,
	".npm":          true,
	".cache":        true,
	".yarn":         true,
	".pnpm-store":   true,
	"__pycache__":   true,
	".pytest_cache": true,
	"target":        true, // Rust/Java build output
	"build":         true,
	"dist":          true,
	".next":         true,
	".nuxt":         true,
}

// System directories to skip (macOS specific)
var skipSystemDirs = map[string]bool{
	"dev":                     true,
	"tmp":                     true,
	"private":                 true,
	"cores":                   true,
	"net":                     true,
	"home":                    true,
	"System":                  true, // macOS system files
	"sbin":                    true,
	"bin":                     true,
	"etc":                     true,
	"var":                     true,
	".vol":                    true,
	".Spotlight-V100":         true,
	".fseventsd":              true,
	".DocumentRevisions-V100": true,
	".TemporaryItems":         true,
}

// File extensions to skip for large file tracking
var skipExtensions = map[string]bool{
	".go":    true,
	".js":    true,
	".ts":    true,
	".jsx":   true,
	".tsx":   true,
	".py":    true,
	".rb":    true,
	".java":  true,
	".c":     true,
	".cpp":   true,
	".h":     true,
	".hpp":   true,
	".rs":    true,
	".swift": true,
	".m":     true,
	".mm":    true,
	".sh":    true,
	".txt":   true,
	".md":    true,
	".json":  true,
	".xml":   true,
	".yaml":  true,
	".yml":   true,
	".toml":  true,
	".css":   true,
	".scss":  true,
	".html":  true,
	".svg":   true,
}

var spinnerFrames = []string{"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧"}

const (
	colorPurple = "\033[0;35m"
	colorBlue   = "\033[0;34m"
	colorGray   = "\033[0;90m"
	colorRed    = "\033[0;31m"
	colorYellow = "\033[1;33m"
	colorGreen  = "\033[0;32m"
	colorCyan   = "\033[0;36m"
	colorReset  = "\033[0m"
	colorBold   = "\033[1m"
	colorBgCyan = "\033[46m"
	colorBgDark = "\033[100m"
	colorInvert = "\033[7m"
)

type dirEntry struct {
	name  string
	path  string
	size  int64
	isDir bool
}

type fileEntry struct {
	name string
	path string
	size int64
}

type scanResult struct {
	entries    []dirEntry
	largeFiles []fileEntry
	totalSize  int64
}

type historyEntry struct {
	path          string
	entries       []dirEntry
	largeFiles    []fileEntry
	totalSize     int64
	selected      int
	entryOffset   int
	largeSelected int
	largeOffset   int
	dirty         bool
}

type scanResultMsg struct {
	result scanResult
	err    error
}

type tickMsg time.Time

type model struct {
	path           string
	history        []historyEntry
	entries        []dirEntry
	largeFiles     []fileEntry
	selected       int
	offset         int
	status         string
	totalSize      int64
	scanning       bool
	spinner        int
	filesScanned   *int64
	dirsScanned    *int64
	bytesScanned   *int64
	currentPath    *string
	showLargeFiles bool
	isOverview     bool
	deleteConfirm  bool
	deleteTarget   *dirEntry
	cache          map[string]historyEntry
	largeSelected  int
	largeOffset    int
}

func main() {
	target := os.Getenv("MO_ANALYZE_PATH")
	if target == "" && len(os.Args) > 1 {
		target = os.Args[1]
	}

	var abs string
	var isOverview bool

	if target == "" {
		// Default to overview mode
		isOverview = true
		abs = "/"
	} else {
		var err error
		abs, err = filepath.Abs(target)
		if err != nil {
			fmt.Fprintf(os.Stderr, "cannot resolve %q: %v\n", target, err)
			os.Exit(1)
		}
		isOverview = false
	}

	p := tea.NewProgram(newModel(abs, isOverview), tea.WithAltScreen())
	if err := p.Start(); err != nil {
		fmt.Fprintf(os.Stderr, "analyzer error: %v\n", err)
		os.Exit(1)
	}
}

func newModel(path string, isOverview bool) model {
	var filesScanned, dirsScanned, bytesScanned int64
	currentPath := ""

	m := model{
		path:           path,
		selected:       0,
		status:         "Preparing scan...",
		scanning:       !isOverview,
		filesScanned:   &filesScanned,
		dirsScanned:    &dirsScanned,
		bytesScanned:   &bytesScanned,
		currentPath:    &currentPath,
		showLargeFiles: false,
		isOverview:     isOverview,
		cache:          make(map[string]historyEntry),
	}

	// In overview mode, create shortcut entries
	if isOverview {
		m.scanning = false
		m.entries = createOverviewEntries()
		m.status = "Ready"
	}

	return m
}

func createOverviewEntries() []dirEntry {
	home := os.Getenv("HOME")
	entries := []dirEntry{
		{name: "Home (~)", path: home, isDir: true},
		{name: "Library (~/Library)", path: filepath.Join(home, "Library"), isDir: true},
		{name: "Applications", path: "/Applications", isDir: true},
		{name: "System Library", path: "/Library", isDir: true},
	}

	// Add Volumes if exists
	if _, err := os.Stat("/Volumes"); err == nil {
		entries = append(entries, dirEntry{name: "Volumes", path: "/Volumes", isDir: true})
	}

	return entries
}

func (m model) Init() tea.Cmd {
	if m.isOverview {
		return nil
	}
	return tea.Batch(m.scanCmd(m.path), tickCmd())
}

func (m model) scanCmd(path string) tea.Cmd {
	return func() tea.Msg {
		result, err := scanPathConcurrent(path, m.filesScanned, m.dirsScanned, m.bytesScanned, m.currentPath)
		return scanResultMsg{result: result, err: err}
	}
}

func tickCmd() tea.Cmd {
	return tea.Tick(time.Millisecond*120, func(t time.Time) tea.Msg {
		return tickMsg(t)
	})
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		return m.updateKey(msg)
	case scanResultMsg:
		m.scanning = false
		if msg.err != nil {
			m.status = fmt.Sprintf("Scan failed: %v", msg.err)
			return m, nil
		}
		m.entries = msg.result.entries
		m.largeFiles = msg.result.largeFiles
		m.totalSize = msg.result.totalSize
		m.status = fmt.Sprintf("Scanned %s", humanizeBytes(m.totalSize))
		m.clampEntrySelection()
		m.clampLargeSelection()
		m.cache[m.path] = cacheSnapshot(m)
		return m, nil
	case tickMsg:
		if m.scanning {
			m.spinner = (m.spinner + 1) % len(spinnerFrames)
			return m, tickCmd()
		}
		return m, nil
	default:
		return m, nil
	}
}

func (m model) updateKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	// Handle delete confirmation
	if m.deleteConfirm {
		if msg.String() == "delete" || msg.String() == "backspace" {
			// Confirm delete
			if m.deleteTarget != nil {
				err := os.RemoveAll(m.deleteTarget.path)
				if err != nil {
					m.status = fmt.Sprintf("Failed to delete: %v", err)
				} else {
					m.status = fmt.Sprintf("Deleted %s", m.deleteTarget.name)
					for i := range m.history {
						m.history[i].dirty = true
					}
					for path := range m.cache {
						entry := m.cache[path]
						entry.dirty = true
						m.cache[path] = entry
					}
					// Refresh the view
					m.scanning = true
					m.deleteConfirm = false
					m.deleteTarget = nil
					return m, tea.Batch(m.scanCmd(m.path), tickCmd())
				}
			}
			m.deleteConfirm = false
			m.deleteTarget = nil
			return m, nil
		} else if msg.String() == "esc" || msg.String() == "q" {
			// Cancel delete with ESC or Q
			m.status = "Cancelled"
			m.deleteConfirm = false
			m.deleteTarget = nil
			return m, nil
		} else {
			// Any other key also cancels
			m.status = "Cancelled"
			m.deleteConfirm = false
			m.deleteTarget = nil
			return m, nil
		}
	}

	switch msg.String() {
	case "q", "ctrl+c":
		return m, tea.Quit
	case "esc":
		if m.showLargeFiles {
			m.showLargeFiles = false
			return m, nil
		}
		return m, tea.Quit
	case "up", "k":
		if m.showLargeFiles {
			if m.largeSelected > 0 {
				m.largeSelected--
				if m.largeSelected < m.largeOffset {
					m.largeOffset = m.largeSelected
				}
			}
		} else if len(m.entries) > 0 && m.selected > 0 {
			m.selected--
			if m.selected < m.offset {
				m.offset = m.selected
			}
		}
	case "down", "j":
		if m.showLargeFiles {
			if m.largeSelected < len(m.largeFiles)-1 {
				m.largeSelected++
				if m.largeSelected >= m.largeOffset+largeViewport {
					m.largeOffset = m.largeSelected - largeViewport + 1
				}
			}
		} else if len(m.entries) > 0 && m.selected < len(m.entries)-1 {
			m.selected++
			if m.selected >= m.offset+entryViewport {
				m.offset = m.selected - entryViewport + 1
			}
		}
	case "enter":
		if m.showLargeFiles {
			return m, nil
		}
		return m.enterSelectedDir()
	case "right":
		if m.showLargeFiles {
			return m, nil
		}
		return m.enterSelectedDir()
	case "b", "left":
		if m.showLargeFiles {
			m.showLargeFiles = false
			return m, nil
		}
		if len(m.history) == 0 {
			// Return to overview if at top level
			if !m.isOverview {
				m.isOverview = true
				m.path = "/"
				m.entries = createOverviewEntries()
				m.selected = 0
				m.offset = 0
				m.status = "Ready"
				m.scanning = false
			}
			return m, nil
		}
		last := m.history[len(m.history)-1]
		m.history = m.history[:len(m.history)-1]
		m.path = last.path
		m.selected = last.selected
		m.offset = last.entryOffset
		m.largeSelected = last.largeSelected
		m.largeOffset = last.largeOffset
		m.isOverview = false
		if last.dirty {
			m.status = "Scanning..."
			m.scanning = true
			return m, tea.Batch(m.scanCmd(m.path), tickCmd())
		}
		m.entries = last.entries
		m.largeFiles = last.largeFiles
		m.totalSize = last.totalSize
		m.clampEntrySelection()
		m.clampLargeSelection()
		if len(m.entries) == 0 {
			m.selected = 0
		} else if m.selected >= len(m.entries) {
			m.selected = len(m.entries) - 1
		}
		if m.selected < 0 {
			m.selected = 0
		}
		m.status = fmt.Sprintf("Scanned %s", humanizeBytes(m.totalSize))
		m.scanning = false
		return m, nil
	case "r":
		m.status = "Refreshing..."
		m.scanning = true
		return m, tea.Batch(m.scanCmd(m.path), tickCmd())
	case "l":
		m.showLargeFiles = !m.showLargeFiles
		if m.showLargeFiles {
			m.largeSelected = 0
			m.largeOffset = 0
		}
	case "o":
		// Open selected entry
		if m.showLargeFiles {
			if len(m.largeFiles) > 0 {
				selected := m.largeFiles[m.largeSelected]
				go func() {
					_ = exec.Command("open", selected.path).Run()
				}()
				m.status = fmt.Sprintf("Opening %s...", selected.name)
			}
		} else if len(m.entries) > 0 && !m.isOverview {
			selected := m.entries[m.selected]
			go func() {
				_ = exec.Command("open", selected.path).Run()
			}()
			m.status = fmt.Sprintf("Opening %s...", selected.name)
		}
	case "f", "F":
		// Reveal selected entry in Finder
		if m.showLargeFiles {
			if len(m.largeFiles) > 0 {
				selected := m.largeFiles[m.largeSelected]
				go func(path string) {
					_ = exec.Command("open", "-R", path).Run()
				}(selected.path)
				m.status = fmt.Sprintf("Revealing %s in Finder...", selected.name)
			}
		} else if len(m.entries) > 0 && !m.isOverview {
			selected := m.entries[m.selected]
			go func(path string) {
				_ = exec.Command("open", "-R", path).Run()
			}(selected.path)
			m.status = fmt.Sprintf("Revealing %s in Finder...", selected.name)
		}
	case "delete", "backspace":
		// Delete selected file or directory
		if m.showLargeFiles {
			if len(m.largeFiles) > 0 {
				selected := m.largeFiles[m.largeSelected]
				m.deleteConfirm = true
				m.deleteTarget = &dirEntry{
					name:  selected.name,
					path:  selected.path,
					size:  selected.size,
					isDir: false,
				}
			}
		} else if len(m.entries) > 0 && !m.isOverview {
			selected := m.entries[m.selected]
			m.deleteConfirm = true
			m.deleteTarget = &selected
		}
	}
	return m, nil
}

func (m model) enterSelectedDir() (tea.Model, tea.Cmd) {
	if len(m.entries) == 0 {
		return m, nil
	}
	selected := m.entries[m.selected]
	if selected.isDir {
		if !m.isOverview {
			m.history = append(m.history, snapshotFromModel(m))
		}
		m.path = selected.path
		m.selected = 0
		m.offset = 0
		m.status = "Scanning..."
		m.scanning = true
		m.isOverview = false
		if cached, ok := m.cache[m.path]; ok && !cached.dirty {
			m.entries = cloneDirEntries(cached.entries)
			m.largeFiles = cloneFileEntries(cached.largeFiles)
			m.totalSize = cached.totalSize
			m.selected = cached.selected
			m.offset = cached.entryOffset
			m.largeSelected = cached.largeSelected
			m.largeOffset = cached.largeOffset
			m.clampEntrySelection()
			m.clampLargeSelection()
			m.status = fmt.Sprintf("Cached view for %s", displayPath(m.path))
			m.scanning = false
			return m, nil
		}
		return m, tea.Batch(m.scanCmd(m.path), tickCmd())
	}
	m.status = fmt.Sprintf("File: %s (%s)", selected.name, humanizeBytes(selected.size))
	return m, nil
}

func (m model) View() string {
	var b strings.Builder
	fmt.Fprintln(&b)

	if m.deleteConfirm && m.deleteTarget != nil {
		// Show delete confirmation prominently at the top
		fmt.Fprintf(&b, "%sDelete: %s (%s)? Press Delete again to confirm, ESC to cancel%s\n\n",
			colorRed, m.deleteTarget.name, humanizeBytes(m.deleteTarget.size), colorReset)
	}

	if m.isOverview {
		fmt.Fprintf(&b, "%sAnalyze Disk%s\n", colorPurple, colorReset)
		fmt.Fprintf(&b, "%sSelect a location to explore:%s\n", colorGray, colorReset)
	} else {
		fmt.Fprintf(&b, "%sAnalyze Disk%s  %s%s%s", colorPurple, colorReset, colorGray, displayPath(m.path), colorReset)
		if !m.scanning {
			fmt.Fprintf(&b, "  |  Total: %s", humanizeBytes(m.totalSize))
		}
		fmt.Fprintln(&b)
	}

	if m.scanning {
		filesScanned := atomic.LoadInt64(m.filesScanned)
		dirsScanned := atomic.LoadInt64(m.dirsScanned)
		bytesScanned := atomic.LoadInt64(m.bytesScanned)

		fmt.Fprintf(&b, "\n%s%s%s%s Scanning: %s%s files%s, %s%s dirs%s, %s%s%s\n",
			colorCyan, colorBold,
			spinnerFrames[m.spinner],
			colorReset,
			colorYellow, formatNumber(filesScanned), colorReset,
			colorYellow, formatNumber(dirsScanned), colorReset,
			colorGreen, humanizeBytes(bytesScanned), colorReset)

		currentPath := *m.currentPath
		if currentPath != "" {
			shortPath := displayPath(currentPath)
			if len(shortPath) > 60 {
				shortPath = "..." + shortPath[len(shortPath)-57:]
			}
			fmt.Fprintf(&b, "%s%s%s\n", colorGray, shortPath, colorReset)
		}

		return b.String()
	}

	fmt.Fprintln(&b)

	if m.showLargeFiles {
		if len(m.largeFiles) == 0 {
			fmt.Fprintln(&b, "  No large files found (>=100MB)")
		} else {
			start := m.largeOffset
			if start < 0 {
				start = 0
			}
			end := start + largeViewport
			if end > len(m.largeFiles) {
				end = len(m.largeFiles)
			}
			maxLargeSize := int64(1)
			for _, file := range m.largeFiles {
				if file.size > maxLargeSize {
					maxLargeSize = file.size
				}
			}
			for idx := start; idx < end; idx++ {
				file := m.largeFiles[idx]
				shortPath := displayPath(file.path)
				if len(shortPath) > 56 {
					shortPath = shortPath[:53] + "..."
				}
				entryPrefix := "    "
				if idx == m.largeSelected {
					entryPrefix = fmt.Sprintf(" %s%s▶%s  ", colorCyan, colorBold, colorReset)
				}
				nameColumn := padName(shortPath, 56)
				size := humanizeBytes(file.size)
				bar := coloredProgressBar(file.size, maxLargeSize, 0)
				fmt.Fprintf(&b, "%s%2d) %s  |  📄 %s %s%10s%s\n",
					entryPrefix, idx+1, bar, nameColumn, colorGray, size, colorReset)
			}
		}
	} else {
		if len(m.entries) == 0 {
			fmt.Fprintln(&b, "  Empty directory")
		} else {
			if m.isOverview {
				// In overview mode, show simple list without sizes
				for idx, entry := range m.entries {
					displayIndex := idx + 1
					if idx == m.selected {
						// Highlight selected entry
						fmt.Fprintf(&b, " %s%s▶ %d) 📁 %s%s\n", colorCyan, colorBold, displayIndex, entry.name, colorReset)
					} else {
						fmt.Fprintf(&b, "   %d) 📁 %s\n", displayIndex, entry.name)
					}
				}
			} else {
				// Normal mode with sizes and progress bars
				maxSize := int64(1)
				for _, entry := range m.entries {
					if entry.size > maxSize {
						maxSize = entry.size
					}
				}

				start := m.offset
				if start < 0 {
					start = 0
				}
				end := start + entryViewport
				if end > len(m.entries) {
					end = len(m.entries)
				}

				for idx := start; idx < end; idx++ {
					entry := m.entries[idx]
					icon := "📄"
					if entry.isDir {
						icon = "📁"
					}
					size := humanizeBytes(entry.size)
					name := trimName(entry.name)
					paddedName := padName(name, 28)

					// Calculate percentage
					percent := float64(entry.size) / float64(m.totalSize) * 100
					percentStr := fmt.Sprintf("%5.1f%%", percent)

					// Get colored progress bar
					bar := coloredProgressBar(entry.size, maxSize, percent)

					// Color the size based on magnitude
					var sizeColor string
					if percent >= 50 {
						sizeColor = colorRed
					} else if percent >= 20 {
						sizeColor = colorYellow
					} else if percent >= 5 {
						sizeColor = colorCyan
					} else {
						sizeColor = colorGray
					}

					// Keep chart columns aligned even when arrow is shown
					entryPrefix := "    "
					nameSegment := fmt.Sprintf("%s %s", icon, paddedName)
					if idx == m.selected {
						entryPrefix = fmt.Sprintf(" %s%s▶%s  ", colorCyan, colorBold, colorReset)
						nameSegment = fmt.Sprintf("%s%s %s%s", colorBold, icon, paddedName, colorReset)
					}

					displayIndex := idx + 1
					fmt.Fprintf(&b, "%s%2d) %s %s  |  %s %s%10s%s\n",
						entryPrefix, displayIndex, bar, percentStr,
						nameSegment, sizeColor, size, colorReset)
				}
			}
		}
	}

	fmt.Fprintln(&b)
	if m.isOverview {
		fmt.Fprintf(&b, "%s  ↑↓←→ Navigate  |  Q Quit%s\n", colorGray, colorReset)
	} else if m.showLargeFiles {
		fmt.Fprintf(&b, "%s  ↑↓ Navigate  |  O Open  |  F Reveal  |  ⌫ Delete  |  Q Quit%s\n", colorGray, colorReset)
	} else {
		largeFileCount := len(m.largeFiles)
		if largeFileCount > 0 {
			fmt.Fprintf(&b, "%s  ↑↓←→ Navigate  |  O Open  |  F Reveal  |  ⌫ Delete  |  L Large(%d)  |  Q Quit%s\n", colorGray, largeFileCount, colorReset)
		} else {
			fmt.Fprintf(&b, "%s  ↑↓←→ Navigate  |  O Open  |  F Reveal  |  ⌫ Delete  |  Q Quit%s\n", colorGray, colorReset)
		}
	}
	return b.String()
}

func scanPathConcurrent(root string, filesScanned, dirsScanned, bytesScanned *int64, currentPath *string) (scanResult, error) {
	children, err := os.ReadDir(root)
	if err != nil {
		return scanResult{}, err
	}

	tracker := newLargeFileTracker()
	var total int64
	entries := make([]dirEntry, 0, len(children))
	var entriesMu sync.Mutex

	// Use worker pool for concurrent directory scanning
	maxWorkers := runtime.NumCPU() * 2
	if maxWorkers < 4 {
		maxWorkers = 4
	}
	if maxWorkers > len(children) {
		maxWorkers = len(children)
	}
	if maxWorkers < 1 {
		maxWorkers = 1
	}
	sem := make(chan struct{}, maxWorkers)
	var wg sync.WaitGroup

	isRootDir := root == "/"

	for _, child := range children {
		fullPath := filepath.Join(root, child.Name())

		if child.IsDir() {
			// In root directory, skip system directories completely
			if isRootDir && skipSystemDirs[child.Name()] {
				continue
			}

			// For folded directories, calculate size quickly without expanding
			if shouldFoldDir(child.Name()) {
				wg.Add(1)
				go func(name, path string) {
					defer wg.Done()
					sem <- struct{}{}
					defer func() { <-sem }()

					size := calculateDirSizeFast(path, filesScanned, dirsScanned, bytesScanned)
					atomic.AddInt64(&total, size)
					atomic.AddInt64(dirsScanned, 1)

					entriesMu.Lock()
					entries = append(entries, dirEntry{
						name:  name,
						path:  path,
						size:  size,
						isDir: true,
					})
					entriesMu.Unlock()
				}(child.Name(), fullPath)
				continue
			}

			// Normal directory: full scan with detail
			wg.Add(1)
			go func(name, path string) {
				defer wg.Done()
				sem <- struct{}{}
				defer func() { <-sem }()

				size := calculateDirSizeConcurrent(path, tracker, filesScanned, dirsScanned, bytesScanned, currentPath)
				atomic.AddInt64(&total, size)
				atomic.AddInt64(dirsScanned, 1)

				entriesMu.Lock()
				entries = append(entries, dirEntry{
					name:  name,
					path:  path,
					size:  size,
					isDir: true,
				})
				entriesMu.Unlock()
			}(child.Name(), fullPath)
			continue
		}

		info, err := child.Info()
		if err != nil {
			continue
		}
		size := info.Size()
		atomic.AddInt64(&total, size)
		atomic.AddInt64(filesScanned, 1)
		atomic.AddInt64(bytesScanned, size)

		entries = append(entries, dirEntry{
			name:  child.Name(),
			path:  fullPath,
			size:  size,
			isDir: false,
		})
		// Only track large files that are not code/text files
		if !shouldSkipFileForLargeTracking(fullPath) {
			tracker.add(fileEntry{name: child.Name(), path: fullPath, size: size})
		}
	}

	wg.Wait()

	sort.Slice(entries, func(i, j int) bool {
		return entries[i].size > entries[j].size
	})
	if len(entries) > maxEntries {
		entries = entries[:maxEntries]
	}

	// Try to use Spotlight for faster large file discovery
	var largeFiles []fileEntry
	if spotlightFiles := findLargeFilesWithSpotlight(root, minLargeFileSize); len(spotlightFiles) > 0 {
		largeFiles = spotlightFiles
	} else {
		// Fallback to manual tracking
		largeFiles = tracker.list()
	}

	return scanResult{
		entries:    entries,
		largeFiles: largeFiles,
		totalSize:  total,
	}, nil
}

func shouldFoldDir(name string) bool {
	return foldDirs[name]
}

func shouldSkipFileForLargeTracking(path string) bool {
	ext := strings.ToLower(filepath.Ext(path))
	return skipExtensions[ext]
}

// Fast directory size calculation (no detailed tracking, no large files)
func calculateDirSizeFast(root string, filesScanned, dirsScanned, bytesScanned *int64) int64 {
	var total int64

	_ = filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if d.IsDir() {
			atomic.AddInt64(dirsScanned, 1)
			return nil
		}
		info, err := d.Info()
		if err != nil {
			return nil
		}
		size := info.Size()
		total += size
		atomic.AddInt64(filesScanned, 1)
		atomic.AddInt64(bytesScanned, size)
		return nil
	})

	return total
}

// Use Spotlight (mdfind) to quickly find large files in a directory
func findLargeFilesWithSpotlight(root string, minSize int64) []fileEntry {
	// mdfind query: files >= minSize in the specified directory
	query := fmt.Sprintf("kMDItemFSSize >= %d", minSize)

	cmd := exec.Command("mdfind", "-onlyin", root, query)
	output, err := cmd.Output()
	if err != nil {
		// Fallback: mdfind not available or failed
		return nil
	}

	lines := strings.Split(strings.TrimSpace(string(output)), "\n")
	var files []fileEntry

	for _, line := range lines {
		if line == "" {
			continue
		}

		// Check if it's a directory, skip it
		info, err := os.Stat(line)
		if err != nil || info.IsDir() {
			continue
		}

		// Filter out files in folded directories
		inFoldedDir := false
		for foldDir := range foldDirs {
			if strings.Contains(line, string(os.PathSeparator)+foldDir+string(os.PathSeparator)) ||
				strings.HasSuffix(filepath.Dir(line), string(os.PathSeparator)+foldDir) {
				inFoldedDir = true
				break
			}
		}
		if inFoldedDir {
			continue
		}

		// Filter out code files
		if shouldSkipFileForLargeTracking(line) {
			continue
		}

		files = append(files, fileEntry{
			name: filepath.Base(line),
			path: line,
			size: info.Size(),
		})
	}

	// Sort by size (descending)
	sort.Slice(files, func(i, j int) bool {
		return files[i].size > files[j].size
	})

	// Return top N
	if len(files) > maxLargeFiles {
		files = files[:maxLargeFiles]
	}

	return files
}

func calculateDirSizeConcurrent(root string, tracker *largeFileTracker, filesScanned, dirsScanned, bytesScanned *int64, currentPath *string) int64 {
	var total int64
	var updateCounter int64

	_ = filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if d.IsDir() {
			// Skip folded directories during recursive scanning
			if shouldFoldDir(d.Name()) {
				return filepath.SkipDir
			}
			atomic.AddInt64(dirsScanned, 1)
			return nil
		}
		info, err := d.Info()
		if err != nil {
			return nil
		}
		size := info.Size()
		total += size
		atomic.AddInt64(filesScanned, 1)
		atomic.AddInt64(bytesScanned, size)

		// Only track large files that are not code/text files
		if !shouldSkipFileForLargeTracking(path) {
			tracker.add(fileEntry{name: filepath.Base(path), path: path, size: size})
		}

		// Update current path every 100 files to reduce contention
		updateCounter++
		if updateCounter%100 == 0 {
			*currentPath = path
		}

		return nil
	})

	return total
}

type largeFileTracker struct {
	mu      sync.Mutex
	entries []fileEntry
}

func newLargeFileTracker() *largeFileTracker {
	return &largeFileTracker{
		entries: make([]fileEntry, 0, maxLargeFiles),
	}
}

func (t *largeFileTracker) add(f fileEntry) {
	if f.size < minLargeFileSize {
		return
	}

	t.mu.Lock()
	defer t.mu.Unlock()

	t.entries = append(t.entries, f)
	sort.Slice(t.entries, func(i, j int) bool {
		return t.entries[i].size > t.entries[j].size
	})
	if len(t.entries) > maxLargeFiles {
		t.entries = t.entries[:maxLargeFiles]
	}
}

func (t *largeFileTracker) list() []fileEntry {
	t.mu.Lock()
	defer t.mu.Unlock()
	return append([]fileEntry(nil), t.entries...)
}

func displayPath(path string) string {
	home, err := os.UserHomeDir()
	if err != nil || home == "" {
		return path
	}
	if strings.HasPrefix(path, home) {
		return strings.Replace(path, home, "~", 1)
	}
	return path
}

func formatNumber(n int64) string {
	if n < 1000 {
		return fmt.Sprintf("%d", n)
	}
	if n < 1000000 {
		return fmt.Sprintf("%.1fk", float64(n)/1000)
	}
	return fmt.Sprintf("%.1fM", float64(n)/1000000)
}

func humanizeBytes(size int64) string {
	if size < 0 {
		return "0 B"
	}
	const unit = 1024
	if size < unit {
		return fmt.Sprintf("%d B", size)
	}
	div, exp := int64(unit), 0
	for n := size / unit; n >= unit; n /= unit {
		div *= unit
		exp++
	}
	value := float64(size) / float64(div)
	return fmt.Sprintf("%.1f %cB", value, "KMGTPE"[exp])
}

func progressBar(value, max int64) string {
	if max <= 0 {
		return strings.Repeat("░", barWidth)
	}
	filled := int((value * int64(barWidth)) / max)
	if filled > barWidth {
		filled = barWidth
	}
	bar := strings.Repeat("█", filled)
	if filled < barWidth {
		bar += strings.Repeat("░", barWidth-filled)
	}
	return bar
}

func coloredProgressBar(value, max int64, percent float64) string {
	if max <= 0 {
		return colorGray + strings.Repeat("░", barWidth) + colorReset
	}

	filled := int((value * int64(barWidth)) / max)
	if filled > barWidth {
		filled = barWidth
	}

	// Choose color based on percentage
	var barColor string
	if percent >= 50 {
		barColor = colorRed // Large files in red
	} else if percent >= 20 {
		barColor = colorYellow // Medium files in yellow
	} else if percent >= 5 {
		barColor = colorCyan // Small-medium in cyan
	} else {
		barColor = colorGreen // Small files in green
	}

	// Create gradient bar with different characters
	bar := barColor
	for i := 0; i < barWidth; i++ {
		if i < filled {
			if i < filled-1 {
				bar += "█"
			} else {
				// Last filled character might be partial
				remainder := (value * int64(barWidth)) % max
				if remainder > max/2 {
					bar += "█"
				} else if remainder > max/4 {
					bar += "▓"
				} else {
					bar += "▒"
				}
			}
		} else {
			bar += colorGray + "░" + barColor
		}
	}
	bar += colorReset

	return bar
}

// Calculate display width considering CJK characters
func runeWidth(r rune) int {
	if r >= 0x4E00 && r <= 0x9FFF || // CJK Unified Ideographs
		r >= 0x3400 && r <= 0x4DBF || // CJK Extension A
		r >= 0xAC00 && r <= 0xD7AF || // Hangul
		r >= 0xFF00 && r <= 0xFFEF { // Fullwidth forms
		return 2
	}
	return 1
}

func displayWidth(s string) int {
	width := 0
	for _, r := range s {
		width += runeWidth(r)
	}
	return width
}

func trimName(name string) string {
	const (
		maxWidth      = 28
		ellipsis      = "..."
		ellipsisWidth = 3
	)

	runes := []rune(name)
	widths := make([]int, len(runes))
	for i, r := range runes {
		widths[i] = runeWidth(r)
	}

	currentWidth := 0
	for i, w := range widths {
		if currentWidth+w > maxWidth {
			subWidth := currentWidth
			j := i
			for j > 0 && subWidth+ellipsisWidth > maxWidth {
				j--
				subWidth -= widths[j]
			}
			if j == 0 {
				return ellipsis
			}
			return string(runes[:j]) + ellipsis
		}
		currentWidth += w
	}

	return name
}

func padName(name string, targetWidth int) string {
	currentWidth := displayWidth(name)
	if currentWidth >= targetWidth {
		return name
	}
	return name + strings.Repeat(" ", targetWidth-currentWidth)
}

func (m *model) clampEntrySelection() {
	if len(m.entries) == 0 {
		m.selected = 0
		m.offset = 0
		return
	}
	if m.selected >= len(m.entries) {
		m.selected = len(m.entries) - 1
	}
	if m.selected < 0 {
		m.selected = 0
	}
	maxOffset := len(m.entries) - entryViewport
	if maxOffset < 0 {
		maxOffset = 0
	}
	if m.offset > maxOffset {
		m.offset = maxOffset
	}
	if m.selected < m.offset {
		m.offset = m.selected
	}
	if m.selected >= m.offset+entryViewport {
		m.offset = m.selected - entryViewport + 1
	}
}

func (m *model) clampLargeSelection() {
	if len(m.largeFiles) == 0 {
		m.largeSelected = 0
		m.largeOffset = 0
		return
	}
	if m.largeSelected >= len(m.largeFiles) {
		m.largeSelected = len(m.largeFiles) - 1
	}
	if m.largeSelected < 0 {
		m.largeSelected = 0
	}
	maxOffset := len(m.largeFiles) - largeViewport
	if maxOffset < 0 {
		maxOffset = 0
	}
	if m.largeOffset > maxOffset {
		m.largeOffset = maxOffset
	}
	if m.largeSelected < m.largeOffset {
		m.largeOffset = m.largeSelected
	}
	if m.largeSelected >= m.largeOffset+largeViewport {
		m.largeOffset = m.largeSelected - largeViewport + 1
	}
}

func cloneDirEntries(entries []dirEntry) []dirEntry {
	if len(entries) == 0 {
		return nil
	}
	copied := make([]dirEntry, len(entries))
	copy(copied, entries)
	return copied
}

func cloneFileEntries(files []fileEntry) []fileEntry {
	if len(files) == 0 {
		return nil
	}
	copied := make([]fileEntry, len(files))
	copy(copied, files)
	return copied
}

func snapshotFromModel(m model) historyEntry {
	return historyEntry{
		path:          m.path,
		entries:       cloneDirEntries(m.entries),
		largeFiles:    cloneFileEntries(m.largeFiles),
		totalSize:     m.totalSize,
		selected:      m.selected,
		entryOffset:   m.offset,
		largeSelected: m.largeSelected,
		largeOffset:   m.largeOffset,
	}
}

func cacheSnapshot(m model) historyEntry {
	entry := snapshotFromModel(m)
	entry.dirty = false
	return entry
}
