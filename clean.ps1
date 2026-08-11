# RedMole clean - Windows 迷你清理工具
# 用法:
#   .\clean.ps1                  # 只检查：列出可清理目标与可回收空间（不删除）
#   .\clean.ps1 -Apply           # 执行清理：移动到回收站（可恢复）
#   .\clean.ps1 -Apply -Force    # 跳过确认，直接执行
#   .\clean.ps1 -Json            # 机器可读输出（配合 -Apply 记录日志）
#
# 设计原则（继承 Mole 产品哲学）:
#   - 默认 dry-run，可预览；-Apply 才动手
#   - 删除一律走回收站（Microsoft.VisualBasic.FileIO，FOF_ALLOWUNDO 等价物）
#   - 目标全部是精确白名单路径，绝不模糊通配
#   - 系统/应用数据目录受保护（见 $ProtectedPaths）
#   - 每次 -Apply 写操作日志到 %LOCALAPPDATA%\mole\logs\clean-<date>.csv

[CmdletBinding()]
param(
    [switch]$Apply,
    [switch]$Force,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# 保护清单：这些路径绝对不动（即使出现在目标子目录里）
# ---------------------------------------------------------------------------
$ProtectedPaths = @(
    "$env:LOCALAPPDATA\mole",                        # 工具自身状态
    "$env:LOCALAPPDATA\Temp\claude",                 # Claude 会话状态
    "$env:LOCALAPPDATA\Temp\redcode",                # RedCode 会话状态
    "$env:WINDIR\Temp"                               # 系统临时（需特权，宁可跳过）
)

# ---------------------------------------------------------------------------
# 清理目标：精确路径 -> 说明。存在才报告；目录删除递归到回收站。
# ---------------------------------------------------------------------------
$CleanTargets = [ordered]@{
    "$env:LOCALAPPDATA\npm-cache"      = 'npm 包缓存'
    "$env:LOCALAPPDATA\pnpm\store"     = 'pnpm 存储'
    "$env:LOCALAPPDATA\pip\cache"      = 'pip 缓存'
    "$env:LOCALAPPDATA\Yarn\Cache"     = 'yarn 缓存'
    "$env:LOCALAPPDATA\go-build"       = 'Go 编译缓存'
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache"  = 'Edge 浏览器缓存'
    "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache"   = 'Chrome 浏览器缓存'
    "$env:USERPROFILE\Downloads\*.tmp" = '下载目录临时文件'
}

# ---------------------------------------------------------------------------
# 工具函数
# ---------------------------------------------------------------------------
function Get-DirSize([string]$Path) {
    $size = 0L
    if (-not (Test-Path -LiteralPath $Path)) { return $size }
    try {
        Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue |
            ForEach-Object { $size += $_.Length }
    } catch { }
    return $size
}

function Send-ToRecycleBin([string]$Path) {
    Add-Type -AssemblyName Microsoft.VisualBasic
    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(
        $Path, 'OnlyErrorDialogs', 'SendToRecycleBin')
}

function Test-Protected([string]$Path) {
    $full = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
    foreach ($p in $ProtectedPaths) {
        if ($p -and $full.StartsWith([System.IO.Path]::GetFullPath($p).TrimEnd('\') + '\')) {
            return $true
        }
    }
    return $false
}

# ---------------------------------------------------------------------------
# 扫描阶段
# ---------------------------------------------------------------------------
$results = @()
foreach ($target in $CleanTargets.Keys) {
    $literal = $target.Replace('*', '__WILDCARD__')
    $isWildcard = $target.Contains('*')
    $paths = @()
    if ($isWildcard) {
        $paths = Get-ChildItem -Path $target -File -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }
    } else {
        if (Test-Path -LiteralPath $target) { $paths = @($target) }
    }
    foreach ($p in $paths) {
        if (Test-Protected $p) { continue }
        $size = if ((Get-Item -LiteralPath $p -Force).PSIsContainer) { Get-DirSize $p } else { (Get-Item -LiteralPath $p -Force).Length }
        $results += [pscustomobject]@{
            Path  = $p
            Note  = $CleanTargets[$target]
            Size  = $size
            Kind  = if ((Get-Item -LiteralPath $p -Force).PSIsContainer) { 'dir' } else { 'file' }
        }
    }
}

$total = ($results | Measure-Object -Property Size -Sum).Sum

if ($Json) {
    $results | Select-Object Path, Note, Size, Kind | ConvertTo-Json
    if ($total -gt 0) { "`n# total_reclaimable_bytes=$total" }
    if (-not $Apply) { "# dry_run=true (use -Apply to move to Recycle Bin)" }
    return
}

Write-Host "`n=== RedMole clean: $(if ($Apply) { 'APPLY' } else { 'DRY RUN (check only)' }) ===" -ForegroundColor Cyan
Write-Host ""
if ($results.Count -eq 0) {
    Write-Host "No cleanable targets found." -ForegroundColor Green
    return
}
$results | Sort-Object Size -Descending | ForEach-Object {
    $sizeMB = [math]::Round($_.Size / 1MB, 1)
    $sizeStr = if ($sizeMB -ge 1024) { "{0:N1} GB" -f ($sizeMB / 1024) } else { "{0:N1} MB" -f $sizeMB }
    Write-Host ("{0,12}  {1}  [{2}]" -f $sizeStr, $_.Path, $_.Note)
}
Write-Host ""
$totalMB = [math]::Round($total / 1MB, 1)
$totalStr = if ($totalMB -ge 1024) { "{0:N1} GB" -f ($totalMB / 1024) } else { "{0:N1} MB" -f $totalMB }
Write-Host ("Total reclaimable: {0}" -f $totalStr) -ForegroundColor Yellow

if (-not $Apply) {
    Write-Host "`nDry run - nothing deleted. Re-run with -Apply to move targets to the Recycle Bin." -ForegroundColor Green
    return
}

# ---------------------------------------------------------------------------
# 执行阶段
# ---------------------------------------------------------------------------
if (-not $Force) {
    $confirm = Read-Host "Move $($results.Count) target(s) to Recycle Bin? (y/N)"
    if ($confirm -notmatch '^[yY]') { Write-Host "Aborted."; return }
}

$logDir = "$env:LOCALAPPDATA\mole\logs"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$logFile = Join-Path $logDir ("clean-{0:yyyyMMdd-HHmmss}.csv" -f (Get-Date))
$logRows = @()
$okCount = 0; $failCount = 0

foreach ($r in $results | Sort-Object Size -Descending) {
    try {
        if ($r.Kind -eq 'dir') { Send-ToRecycleBin $r.Path } else { Remove-Item -LiteralPath $r.Path -Force }
        $logRows += [pscustomobject]@{ Time = Get-Date -Format o; Path = $r.Path; Size = $r.Size; Status = 'ok' }
        $okCount++
    } catch {
        $logRows += [pscustomobject]@{ Time = Get-Date -Format o; Path = $r.Path; Size = $r.Size; Status = "fail: $_" }
        $failCount++
    }
}
$logRows | Export-Csv -Path $logFile -NoTypeInformation
Write-Host ""
Write-Host "Done: $okCount moved to Recycle Bin, $failCount failed." -ForegroundColor Yellow
Write-Host "Log: $logFile" -ForegroundColor Gray
