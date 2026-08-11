
package main

import (
	"os"
	"path/filepath"
	"strings"
	"time"
)

// createInsightEntries returns the list of hidden-space insight entries
// to show in the overview screen alongside the standard directory entries.
func createInsightEntries() []dirEntry {
	home := os.Getenv("USERPROFILE")
	localAppData := os.Getenv("LOCALAPPDATA")
	if home == "" {
		return nil
	}

	var entries []dirEntry

	// Old Downloads: ~\Downloads (files older than 90 days)
	downloadsPath := filepath.Join(home, "Downloads")
	if info, err := os.Stat(downloadsPath); err == nil && info.IsDir() {
		entries = append(entries, dirEntry{
			Name:  "Old Downloads (90d+)",
			Path:  downloadsPath,
			IsDir: true,
			Size:  -1,
		})
	}

	// Cleanable paths: things the user can safely delete or that a cleaner
	// could reclaim. Every path is checked before it is listed.
	cleanablePaths := []struct {
		name string
		path string
	}{
		{"Temp Files", os.Getenv("TEMP")},
		{"System Temp", filepath.Join(os.Getenv("SystemRoot"), "Temp")},
		{"npm Cache", filepath.Join(localAppData, "npm-cache")},
		{"pnpm Store", filepath.Join(localAppData, "pnpm", "store")},
		{"pip Cache", filepath.Join(localAppData, "pip", "cache")},
		{"yarn Cache", filepath.Join(localAppData, "Yarn", "Cache")},
		{"Edge Cache", filepath.Join(localAppData, "Microsoft", "Edge", "User Data", "Default", "Cache")},
		{"Chrome Cache", filepath.Join(localAppData, "Google", "Chrome", "User Data", "Default", "Cache")},
		{"NuGet Cache", filepath.Join(home, ".nuget", "packages")},
		{"Go Build Cache", filepath.Join(localAppData, "go-build")},
	}
	for _, c := range cleanablePaths {
		if c.path == "" {
			continue
		}
		if info, err := os.Stat(c.path); err == nil && info.IsDir() {
			entries = append(entries, dirEntry{
				Name:  c.name,
				Path:  c.path,
				IsDir: true,
				Size:  -1,
			})
		}
	}

	return entries
}

// measureInsightSize measures the size of a path.
// Old Downloads is treated specially: only files older than 90 days are counted.
func measureInsightSize(path string) (int64, error) {
	home := os.Getenv("USERPROFILE")

	if home != "" && path == filepath.Join(home, "Downloads") {
		return measureOldDownloads(path, 90)
	}

	return measureOverviewSize(path)
}

// measureOldDownloads calculates total size of files in a directory
// that haven't been modified in the given number of days.
func measureOldDownloads(dir string, daysOld int) (int64, error) {
	cutoff := time.Now().AddDate(0, 0, -daysOld)
	var total int64

	entries, err := os.ReadDir(dir)
	if err != nil {
		return 0, err
	}

	for _, entry := range entries {
		// Skip hidden files.
		if strings.HasPrefix(entry.Name(), ".") {
			continue
		}

		info, err := entry.Info()
		if err != nil {
			continue
		}

		if info.ModTime().Before(cutoff) {
			if entry.IsDir() {
				// Walk the subtree natively (no du on Windows).
				if size, err := getDirectoryLogicalSizeWithExclude(filepath.Join(dir, entry.Name()), ""); err == nil {
					total += size
				}
			} else {
				total += info.Size()
			}
		}
	}

	return total, nil
}
