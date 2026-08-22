
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"sort"
	"sync"
	"sync/atomic"
	"time"
)

type jsonOutput struct {
	Path           string        `json:"path"`
	Overview       bool          `json:"overview"`
	Entries        []jsonEntry   `json:"entries"`
	LargeFiles     []jsonFileEntry `json:"large_files,omitempty"`
	TotalSize      int64         `json:"total_size"`
	TotalSizeHuman string        `json:"total_size_human,omitempty"`
	TotalFiles     int64         `json:"total_files,omitempty"`
}

type jsonEntry struct {
	Name       string      `json:"name"`
	Path       string      `json:"path"`
	Size       int64       `json:"size"`
	SizeHuman  string      `json:"size_human,omitempty"`
	IsDir      bool        `json:"is_dir"`
	Insight    bool        `json:"insight,omitempty"`
	Cleanable  bool        `json:"cleanable,omitempty"`
	LastAccess string      `json:"last_access,omitempty"`
	Entries    []jsonEntry `json:"entries,omitempty"`
}

type jsonFileEntry struct {
	Name      string `json:"name"`
	Path      string `json:"path"`
	Size      int64  `json:"size"`
	SizeHuman string `json:"size_human,omitempty"`
}

func runJSONMode(path string, isOverview bool, depth, topN int) {
	result := performScanForJSONWithDepth(path, isOverview, depth, topN)

	result.TotalSizeHuman = humanizeBytes(result.TotalSize)
	for i := range result.Entries {
		result.Entries[i].SizeHuman = humanizeBytes(result.Entries[i].Size)
		formatEntriesHuman(&result.Entries[i])
	}
	for i := range result.LargeFiles {
		result.LargeFiles[i].SizeHuman = humanizeBytes(result.LargeFiles[i].Size)
	}

	encoder := json.NewEncoder(os.Stdout)
	encoder.SetIndent("", "  ")
	if err := encoder.Encode(result); err != nil {
		fmt.Fprintf(os.Stderr, "failed to encode JSON: %v\n", err)
		os.Exit(1)
	}
}

func formatEntriesHuman(entry *jsonEntry) {
	entry.SizeHuman = humanizeBytes(entry.Size)
	for i := range entry.Entries {
		entry.Entries[i].SizeHuman = humanizeBytes(entry.Entries[i].Size)
		formatEntriesHuman(&entry.Entries[i])
	}
}

func performScanForJSONWithDepth(path string, isOverview bool, depth, topN int) jsonOutput {
	if isOverview {
		return performOverviewScanForJSONWithDepth(path, depth, topN)
	}
	return performDirectoryScanForJSONWithDepth(path, depth, topN)
}

func performScanForJSON(path string, isOverview bool) jsonOutput {
	return performScanForJSONWithDepth(path, isOverview, 1, 0)
}

func performDirectoryScanForJSONWithDepth(path string, remainingDepth, topN int) jsonOutput {
	entryLimit := 0
	if topN > 0 {
		entryLimit = topN
	}

	var filesScanned, dirsScanned, bytesScanned int64
	currentPath := &atomic.Value{}
	currentPath.Store("")

	result, err := scanPathConcurrentWithOptions(path, &filesScanned, &dirsScanned, &bytesScanned, currentPath, true, entryLimit)
	if err != nil {
		fmt.Fprintf(os.Stderr, "failed to scan directory: %v\n", err)
		os.Exit(1)
	}

	output := jsonOutput{
		Path:       path,
		Overview:   false,
		Entries:    jsonEntriesFromDirEntries(result.Entries, false, nil),
		LargeFiles: jsonFileEntriesFromFileEntries(result.LargeFiles),
		TotalSize:  result.TotalSize,
		TotalFiles: result.TotalFiles,
	}

	if remainingDepth > 1 || remainingDepth <= 0 {
		childDepth := remainingDepth - 1
		if remainingDepth <= 0 {
			childDepth = 0
		}
		for i := range output.Entries {
			if output.Entries[i].IsDir {
				child := performDirectoryScanForJSONWithDepth(output.Entries[i].Path, childDepth, 0)
				output.Entries[i].Entries = child.Entries
			}
		}
	}

	return output
}

func performOverviewScanForJSON(path string) jsonOutput {
	return performOverviewScanForJSONWithDepth(path, 1, 0)
}

func performOverviewScanForJSONWithDepth(path string, depth, topN int) jsonOutput {
	insightEntries := createInsightEntries()
	overviewEntries := createOverviewEntriesWithInsights(insightEntries)
	return performOverviewScanForJSONWithEntriesAndDepth(path, insightEntries, overviewEntries, depth, topN)
}

func performOverviewScanForJSONWithEntries(path string, insightEntries, overviewEntries []dirEntry) jsonOutput {
	return performOverviewScanForJSONWithEntriesAndDepth(path, insightEntries, overviewEntries, 1, 0)
}

func performOverviewScanForJSONWithEntriesAndDepth(path string, insightEntries, overviewEntries []dirEntry, depth, topN int) jsonOutput {
	insightPaths := make(map[string]bool, len(insightEntries))
	for _, insight := range insightEntries {
		insightPaths[insight.Path] = true
	}

	var totalSize int64
	entries := make([]dirEntry, 0, len(overviewEntries))
	for _, entry := range measureOverviewEntriesForJSON(overviewEntries, insightPaths) {
		// Match the TUI: omit scanned insight/tool entries that ended up empty.
		if entry.Size == 0 {
			continue
		}
		totalSize += entry.Size
		entries = append(entries, entry)
	}

	sort.SliceStable(entries, func(i, j int) bool {
		return entries[i].Size > entries[j].Size
	})

	if topN > 0 && len(entries) > topN {
		entries = entries[:topN]
	}

	output := jsonOutput{
		Path:      path,
		Overview:  true,
		Entries:   jsonEntriesFromDirEntries(entries, true, insightPaths),
		TotalSize: totalSize,
	}

	if depth > 1 || depth <= 0 {
		childDepth := depth - 1
		if depth <= 0 {
			childDepth = 0
		}
		for i := range output.Entries {
			if output.Entries[i].IsDir && !output.Entries[i].Insight {
				child := performDirectoryScanForJSONWithDepth(output.Entries[i].Path, childDepth, 0)
				output.Entries[i].Entries = child.Entries
			}
		}
	}

	return output
}

func measureOverviewEntriesForJSON(overviewEntries []dirEntry, insightPaths map[string]bool) []dirEntry {
	if len(overviewEntries) == 0 {
		return nil
	}

	type measurement struct {
		index int
		entry dirEntry
	}

	measured := make([]dirEntry, len(overviewEntries))
	sem := make(chan struct{}, maxConcurrentOverview)
	results := make(chan measurement, len(overviewEntries))

	var wg sync.WaitGroup
	for index, item := range overviewEntries {
		wg.Go(func() {
			sem <- struct{}{}
			defer func() { <-sem }()

			var (
				size int64
				err  error
			)

			if cached, cacheErr := loadOverviewCachedSize(item.Path); cacheErr == nil && cached > 0 {
				size = cached
			} else if insightPaths[item.Path] {
				size, err = measureInsightSize(item.Path)
			} else {
				size, err = measureOverviewSize(item.Path)
			}

			if err == nil {
				item.Size = size
			}
			results <- measurement{index: index, entry: item}
		})
	}

	wg.Wait()
	close(results)

	for result := range results {
		measured[result.index] = result.entry
	}
	return measured
}

func jsonEntriesFromDirEntries(entries []dirEntry, isOverview bool, insightPaths map[string]bool) []jsonEntry {
	output := make([]jsonEntry, 0, len(entries))
	for _, entry := range entries {
		item := jsonEntry{
			Name:      entry.Name,
			Path:      entry.Path,
			Size:      entry.Size,
			IsDir:     entry.IsDir,
			Cleanable: entry.IsDir && isCleanableDir(entry.Path),
		}

		if isOverview {
			item.Insight = insightPaths[entry.Path]
		}

		if !entry.LastAccess.IsZero() {
			item.LastAccess = entry.LastAccess.UTC().Format(time.RFC3339)
		}

		output = append(output, item)
	}
	return output
}

func jsonFileEntriesFromFileEntries(files []fileEntry) []jsonFileEntry {
	output := make([]jsonFileEntry, 0, len(files))
	for _, f := range files {
		output = append(output, jsonFileEntry{
			Name: f.Name,
			Path: f.Path,
			Size: f.Size,
		})
	}
	return output
}
