
package main

import (
	"fmt"
	"os"
	"os/user"
	"path/filepath"
	"slices"
	"sort"
	"strings"
	"sync/atomic"
	"time"
	"unsafe"

	tea "github.com/charmbracelet/bubbletea"
	"golang.org/x/sys/windows"
)

const trashTimeout = 30 * time.Second

var (
	shell32              = windows.NewLazySystemDLL("shell32.dll")
	procSHFileOperationW = shell32.NewProc("SHFileOperationW")
)

// shfileop mirrors the SHFILEOPSTRUCTW layout used by SHFileOperationW.
type shfileop struct {
	hwnd                  uintptr
	wFunc                 uint32
	pFrom                 *uint16
	pTo                   *uint16
	fFlags                uint16
	fAnyOperationsAborted bool
	hNameMappings         uintptr
	lpszProgressTitle     *uint16
}

const (
	foDelete     = 0x0003
	fofAllowUndo = 0x0040
	fofNoConfirm = 0x0010
	fofSilent    = 0x0004
	fofNoErrorUI = 0x0400
)

// moveToTrash moves a file/directory to the Recycle Bin through the Windows
// shell (SHFileOperationW with FOF_ALLOWUNDO), so the delete stays recoverable
// and the shell handles cross-volume, read-only and in-use semantics.
func moveToTrash(path string) error {
	// Validate raw input before Abs resolves ".." components away.
	if err := validateTrashTarget(path); err != nil {
		return err
	}

	absPath, err := filepath.Abs(path)
	if err != nil {
		return fmt.Errorf("failed to resolve path: %w", err)
	}

	// Validate resolved path as well (defense-in-depth).
	if err := validateTrashTarget(absPath); err != nil {
		return err
	}

	// pFrom needs a double-null terminator; the extra "\x00" is encoded as a
	// NUL character followed by the UTF-16 terminator.
	pFrom, err := windows.UTF16PtrFromString(absPath + "\x00")
	if err != nil {
		return fmt.Errorf("failed to encode path: %w", err)
	}

	op := shfileop{
		wFunc:  foDelete,
		pFrom:  pFrom,
		fFlags: fofAllowUndo | fofNoConfirm | fofSilent | fofNoErrorUI,
	}
	ret, _, _ := procSHFileOperationW.Call(uintptr(unsafe.Pointer(&op)))
	if ret != 0 {
		return fmt.Errorf("failed to move to Recycle Bin (error 0x%x)", ret)
	}
	if op.fAnyOperationsAborted {
		return fmt.Errorf("move to Recycle Bin was aborted by the shell")
	}
	return nil
}

func deletePathCmd(path string, counter *int64) tea.Cmd {
	return func() tea.Msg {
		count, err := trashPathWithProgress(path, counter)
		return deleteProgressMsg{
			done:  true,
			err:   err,
			count: count,
			path:  path,
		}
	}
}

// deleteMultiplePathsCmd moves paths to Trash and aggregates results.
func deleteMultiplePathsCmd(paths []string, counter *int64) tea.Cmd {
	return func() tea.Msg {
		var totalCount int64
		var errors []string
		var removedPaths []string

		// Process deeper paths first to avoid parent/child conflicts.
		pathsToDelete := append([]string(nil), paths...)
		sort.Slice(pathsToDelete, func(i, j int) bool {
			return strings.Count(pathsToDelete[i], string(filepath.Separator)) > strings.Count(pathsToDelete[j], string(filepath.Separator))
		})

		for _, path := range pathsToDelete {
			count, err := trashPathWithProgress(path, counter)
			totalCount += count
			if err != nil {
				if os.IsNotExist(err) {
					removedPaths = append(removedPaths, path)
					continue
				}
				errors = append(errors, err.Error())
				continue
			}
			removedPaths = append(removedPaths, path)
		}

		var resultErr error
		if len(errors) > 0 {
			resultErr = &multiDeleteError{errors: errors}
		}

		return deleteProgressMsg{
			done:         true,
			err:          resultErr,
			count:        totalCount,
			path:         "",
			removedPaths: removedPaths,
		}
	}
}

// multiDeleteError holds multiple deletion errors.
type multiDeleteError struct {
	errors []string
}

func (e *multiDeleteError) Error() string {
	if len(e.errors) == 1 {
		return e.errors[0]
	}
	return strings.Join(e.errors[:min(3, len(e.errors))], "; ")
}

// trashPathWithProgress moves one selected path to Trash and reports completion.
func trashPathWithProgress(root string, counter *int64) (int64, error) {
	// Verify path exists (use Lstat to handle broken symlinks).
	_, err := os.Lstat(root)
	if err != nil {
		return 0, err
	}

	// Trash moves one selected path as a unit. Recursively counting every file
	// first made large directory deletes appear hung before the move began.
	const count int64 = 1

	// Move through a headless Trash route, with Finder as the last compatibility fallback.
	if err := moveToTrash(root); err != nil {
		return 0, err
	}
	if counter != nil {
		atomic.AddInt64(counter, count)
	}

	return count, nil
}

func validateTrashTarget(path string) error {
	if err := validatePath(path); err != nil {
		return err
	}
	if isProtectedAnalyzeDeletePath(path) {
		return fmt.Errorf("protected path cannot be deleted: %s", path)
	}
	if resolvedPath, err := filepath.EvalSymlinks(path); err == nil && isProtectedAnalyzeDeletePath(resolvedPath) {
		return fmt.Errorf("protected path cannot be deleted: %s", path)
	}
	return nil
}

func isProtectedAnalyzeDeletePath(path string) bool {
	if path == "" {
		return false
	}

	cleanPath := filepath.Clean(path)

	if isCriticalAnalyzeDeletePath(cleanPath) {
		return true
	}

	homeRoots := protectedAnalyzeHomeRoots()
	if len(homeRoots) == 0 {
		return false
	}

	for _, homeRoot := range homeRoots {
		if cleanPath == homeRoot || isSameExistingPath(cleanPath, homeRoot) {
			return true
		}
	}

	// The per-user application-data root is never a cleanup surface on
	// Windows, with one deliberate exception: the Temp subtree (a legit
	// cleanup target) stays deletable. Deleting the LOCALAPPDATA root
	// itself or any other subtree (Microsoft, Google, Programs, ...) is
	// rejected.
	appData := os.Getenv("LOCALAPPDATA")
	if appData != "" {
		if cleanPath == appData || isSameExistingPath(cleanPath, appData) {
			return true
		}
		rel, relErr := filepath.Rel(appData, cleanPath)
		if relErr == nil && rel != "." && rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
			first := rel
			if idx := strings.Index(rel, string(filepath.Separator)); idx >= 0 {
				first = rel[:idx]
			}
			if !strings.EqualFold(first, "Temp") {
				return true
			}
		}
	}
	return false
}

func isCriticalAnalyzeDeletePath(path string) bool {
	cleanPath := filepath.Clean(path)

	// Volume roots (C:\, D:\ ...) are never a cleanup surface.
	for _, root := range windowsDriveRoots() {
		if cleanPath == root || isSameExistingPath(cleanPath, root) {
			return true
		}
	}

	// System-owned trees, resolved through the real environment values so a
	// non-default installation location is protected too. The constants are
	// fallbacks only; Windows itself sets these variables for every session.
	criticalRoots := []string{
		os.Getenv("SystemRoot"),
		filepath.Join(os.Getenv("SystemRoot"), "System32"),
		filepath.Join(os.Getenv("SystemRoot"), "SysWOW64"),
		os.Getenv("ProgramFiles"),
		os.Getenv("ProgramFiles(x86)"),
		os.Getenv("ProgramData"),
		os.Getenv("USERPROFILE"),
	}
	for _, root := range criticalRoots {
		if root == "" {
			continue
		}
		if cleanPath == root || isSameExistingPath(cleanPath, root) {
			return true
		}
	}

	// These system-owned trees are never an Analyze cleanup surface, even when
	// a caller starts inside one instead of selecting its top-level row.
	systemDrive := ""
	if systemRoot := os.Getenv("SystemRoot"); systemRoot != "" {
		systemDrive = filepath.VolumeName(systemRoot) + `\`
	}
	protectedTrees := []string{
		filepath.Join(os.Getenv("SystemRoot"), "WinSxS"),
		filepath.Join(os.Getenv("SystemRoot"), "Installer"),
		filepath.Join(os.Getenv("SystemRoot"), "SoftwareDistribution"),
		filepath.Join(os.Getenv("SystemRoot"), "servicing"),
		filepath.Join(os.Getenv("SystemRoot"), "Temp"),
		filepath.Join(os.Getenv("SystemRoot"), "Logs"),
		systemDrive + "System Volume Information",
		systemDrive + "$Recycle.Bin",
		systemDrive + "Recovery",
		systemDrive + "PerfLogs",
	}
	for _, root := range protectedTrees {
		if root == "" {
			continue
		}
		if cleanPath == root ||
			strings.HasPrefix(cleanPath, root+string(filepath.Separator)) ||
			isPathWithinExistingRoot(cleanPath, root) {
			return true
		}
	}

	// A child directly under another account's profile root is not an ordinary
	// directory. Protect every account root while keeping its descendants
	// available to the owning user. The Users directory is the parent of the
	// current profile (C:\Users when USERPROFILE is C:\Users\Administrator).
	usersRoot := filepath.Dir(os.Getenv("USERPROFILE"))
	if filepath.IsAbs(usersRoot) && !strings.EqualFold(filepath.Base(usersRoot), "Users") {
		usersRoot = filepath.Join(usersRoot, "Users")
	}
	if filepath.IsAbs(usersRoot) {
		// String-level parent check (works even when the target account
		// directory does not exist yet) plus the stat-based one for aliases.
		if strings.EqualFold(filepath.Dir(cleanPath), usersRoot) ||
			isDirectChildOfExistingRoot(cleanPath, usersRoot) {
			return true
		}
	}
	return false
}

// windowsDriveRoots enumerates the currently attached drive roots (C:\, D:\...).
func windowsDriveRoots() []string {
	var roots []string
	driveBits, err := windows.GetLogicalDrives()
	if err != nil {
		return roots
	}
	for i := 0; i < 26; i++ {
		if driveBits&(1<<uint(i)) != 0 {
			roots = append(roots, string(rune('A'+i))+":\\")
		}
	}
	return roots
}

func protectedAnalyzeHomeRoots() []string {
	var homeRoots []string
	seenHomeRoots := make(map[string]bool)
	addHomeRoot := func(home string) {
		if home == "" {
			return
		}
		cleanHome := filepath.Clean(home)
		if !seenHomeRoots[cleanHome] {
			homeRoots = append(homeRoots, cleanHome)
			seenHomeRoots[cleanHome] = true
		}
		if resolvedHome, err := filepath.EvalSymlinks(cleanHome); err == nil && !seenHomeRoots[resolvedHome] {
			homeRoots = append(homeRoots, resolvedHome)
			seenHomeRoots[resolvedHome] = true
		}
	}

	addHomeRoot(os.Getenv("USERPROFILE"))
	addHomeRoot(filepath.Join(os.Getenv("HOMEDRIVE"), os.Getenv("HOMEPATH")))
	if currentUser, err := user.Current(); err == nil {
		addHomeRoot(currentUser.HomeDir)
	}
	return homeRoots
}

func isPathWithinExistingRoot(path, protectedRoot string) bool {
	protectedInfo, err := os.Stat(protectedRoot)
	if err != nil {
		return false
	}

	for current := filepath.Clean(path); ; current = filepath.Dir(current) {
		if currentInfo, err := os.Stat(current); err == nil && os.SameFile(currentInfo, protectedInfo) {
			return true
		}
		parent := filepath.Dir(current)
		if parent == current {
			return false
		}
	}
}

func isSameExistingPath(path, protectedPath string) bool {
	pathInfo, pathErr := os.Stat(path)
	protectedInfo, protectedErr := os.Stat(protectedPath)
	return pathErr == nil && protectedErr == nil && os.SameFile(pathInfo, protectedInfo)
}

func isDirectChildOfExistingRoot(path, protectedRoot string) bool {
	cleanPath := filepath.Clean(path)
	return cleanPath != filepath.Clean(protectedRoot) &&
		filepath.Dir(cleanPath) != cleanPath &&
		isSameExistingPath(filepath.Dir(cleanPath), protectedRoot)
}

// validatePath checks path safety for external commands.
// Returns error if path is empty, relative, contains null bytes, or has traversal.
func validatePath(path string) error {
	if path == "" {
		return fmt.Errorf("path is empty")
	}
	if !filepath.IsAbs(path) {
		return fmt.Errorf("path must be absolute: %s", path)
	}
	if strings.Contains(path, "\x00") {
		return fmt.Errorf("path contains null bytes")
	}
	// Check for path traversal attempts (.. components). Windows accepts both
	// separators, so normalize before splitting or a mixed path slips through.
	normalized := strings.ReplaceAll(path, "/", string(filepath.Separator))
	if slices.Contains(strings.Split(normalized, string(filepath.Separator)), "..") {
		return fmt.Errorf("path contains traversal components: %s", path)
	}
	return nil
}
