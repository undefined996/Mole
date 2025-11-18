package main

import (
	"io/fs"
	"os"
	"path/filepath"
	"sync/atomic"

	tea "github.com/charmbracelet/bubbletea"
)

func deletePathCmd(path string, counter *int64) tea.Cmd {
	return func() tea.Msg {
		count, err := deletePathWithProgress(path, counter)
		return deleteProgressMsg{
			done:  true,
			err:   err,
			count: count,
		}
	}
}

func deletePathWithProgress(root string, counter *int64) (int64, error) {
	var count int64

	err := filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return nil
		}

		if !d.IsDir() {
			if removeErr := os.Remove(path); removeErr == nil {
				count++
				if counter != nil {
					atomic.StoreInt64(counter, count)
				}
			}
		}

		return nil
	})

	if err != nil {
		return count, err
	}

	if err := os.RemoveAll(root); err != nil {
		return count, err
	}

	return count, nil
}
