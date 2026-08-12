# RedMole clean - Windows 迷你清理工具
# 用法:
#   .\clean.ps1                  # 只检查：列出可清理目标与可回收空间（不删除）
#   .\clean.ps1 -Apply           # 执行清理
#   .\clean.ps1 -Apply -Force    # 跳过确认，直接执行
#   .\clean.ps1 -Json            # 机器可读输出（配合 -Apply 记录日志）
#
# 设计原则（继承 Mole 产品哲学）:
#   - 默认 dry-run，可预览；-Apply 才动手
#   - 两档删除策略（v0.0.2 起）:
#     * 小体积缓存（npm/pip/浏览器等）-> 回收站，可恢复
#     * 大体积临时目标（Temp/uv 缓存）-> 直接删除。回收站也在系统盘，
#       几十 GB 送回收站等于没释放空间。三重门槛才删:
#         a) 不在保护清单（含目录自身，见 $ProtectedPaths）
#         b) 修改时间早于 -MinAgeDays 天（默认 14 天；正在使用的文件
#            通常近几天被写，自动排除）
#         c) 删除时被进程锁定则跳过（在用的版本不受影响）
#   - 目标全部是精确白名单路径，绝不模糊通配
#   - 系统/应用数据目录受保护（见 $ProtectedPaths）
#   - 每次 -Apply 写操作日志到 %LOCALAPPDATA%\mole\logs\clean-<date>.csv

[CmdletBinding()]
param(
    [switch]$Apply,
    [switch]$Force,
    [switch]$Json,
    [int]$MinAgeDays = 14,     # 大体积目标只清超过 N 天未修改的子项（默认 14 天）
    [string[]]$Paths
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
# 清理目标：精确路径 -> 说明。存在才报告；目录删除递归。
#   $RecycleTargets : 走回收站（可恢复）
#   $DirectTargets  : 直接删除（大体积可再生缓存，见头部说明）
# ---------------------------------------------------------------------------
$RecycleTargets = [ordered]@{
    "$env:LOCALAPPDATA\npm-cache"      = 'npm 包缓存'
    "$env:LOCALAPPDATA\pnpm\store"     = 'pnpm 存储'
    "$env:LOCALAPPDATA\pip\cache"      = 'pip 缓存'
    "$env:LOCALAPPDATA\Yarn\Cache"     = 'yarn 缓存'
    "$env:LOCALAPPDATA\go-build"       = 'Go 编译缓存'
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache"  = 'Edge 浏览器缓存'
    "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache"   = 'Chrome 浏览器缓存'
    "$env:USERPROFILE\Downloads\*.tmp" = '下载目录临时文件'
}

$DirectTargets = [ordered]@{
    "$env:LOCALAPPDATA\Temp"                       = '用户临时文件（排除 claude/redcode 会话）'
    "$env:LOCALAPPDATA\uv\cache\archive-v0"        = 'uv 依赖环境缓存（jcodemunch 等，可重建）'
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

# 保护检查：目录自身或其后代命中保护清单都算受保护。
# 注意：StartsWith 必须带上路径分隔符（$p + '\'）做边界，否则 C:\Foo 会
# 误保护 C:\FooBar；同时必须覆盖"等于保护路径本身"（不带尾斜杠）。
function Test-Protected([string]$Path) {
    $full = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
    foreach ($p in $ProtectedPaths) {
        if (-not $p) { continue }
        $protected = [System.IO.Path]::GetFullPath($p).TrimEnd('\')
        if ($full -eq $protected -or $full.StartsWith($protected + '\')) {
            return $true
        }
    }
    return $false
}

# 大体积目标：枚举顶层子项，逐个判断是否可删。
# 安全门槛（全部满足才删）：
#   1. 不在保护清单（Test-Protected，含目录自身）
#   2. 修改时间早于 $MinAgeDays 天前（正在使用的文件通常近 1-2 天内被写）
#   3. 删除时被锁定（进程在用）则自动跳过
# 返回 @(可删列表, 跳过列表)，跳过列表元素为 [pscustomobject]@{Path; Reason}
function Get-DirectCandidates([string]$Root, [int]$MinAgeDays) {
    $candidates = @(); $skipped = @()
    if (-not (Test-Path -LiteralPath $Root)) { return @($candidates, $skipped) }
    $cutoff = (Get-Date).AddDays(-$MinAgeDays)
    $items = Get-ChildItem -LiteralPath $Root -Force -ErrorAction SilentlyContinue
    foreach ($it in $items) {
        if (Test-Protected $it.FullName) {
            $skipped += [pscustomobject]@{ Path = $it.FullName; Reason = 'protected' }
            continue
        }
        if ($it.LastWriteTime -gt $cutoff) {
            $skipped += [pscustomobject]@{ Path = $it.FullName; Reason = 'recent' }
            continue
        }
        $candidates += $it
    }
    return @($candidates, $skipped)
}

function Get-CandidateSize($Item) {
    if ($Item.PSIsContainer) { Get-DirSize $Item.FullName } else { $Item.Length }
}

function Remove-DirectTarget([string]$Root, [int]$MinAgeDays) {
    $ok = 0; $skip = 0
    $pair = Get-DirectCandidates $Root $MinAgeDays
    foreach ($it in $pair[0]) {
        try {
            Remove-Item -LiteralPath $it.FullName -Recurse -Force -ErrorAction Stop
            $ok++
        } catch {
            $skip++   # 锁定/权限不足，跳过
        }
    }
    return @($ok, $skip)
}

# ---------------------------------------------------------------------------
# 扫描阶段
# ---------------------------------------------------------------------------
$results = @()
foreach ($target in $RecycleTargets.Keys) {
    $literal = $target.Replace('*', '__WILDCARD__')
    $isWildcard = $target.Contains('*')
    $candidatePaths = @()
    if ($isWildcard) {
        $candidatePaths = Get-ChildItem -Path $target -File -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }
    } else {
        if (Test-Path -LiteralPath $target) { $candidatePaths = @($target) }
    }
    foreach ($p in $candidatePaths) {
        if (Test-Protected $p) { continue }
        if ($Paths.Count -gt 0 -and $Paths -notcontains $p) { continue }
        $item = Get-Item -LiteralPath $p -Force
        $size = if ($item.PSIsContainer) { Get-DirSize $p } else { $item.Length }
        $results += [pscustomobject]@{
            Path = $p
            Note = $RecycleTargets[$target]
            Size = $size
            Kind = if ($item.PSIsContainer) { 'dir' } else { 'file' }
            Mode = 'recycle'
        }
    }
}

foreach ($target in $DirectTargets.Keys) {
    if (-not (Test-Path -LiteralPath $target)) { continue }
    if ($Paths.Count -gt 0 -and $Paths -notcontains $target) { continue }
    $pair = Get-DirectCandidates $target $MinAgeDays
    $size = 0L
    foreach ($c in $pair[0]) { $size += Get-CandidateSize $c }
    $results += [pscustomobject]@{
        Path = $target
        Note = $DirectTargets[$target]
        Size = $size
        Kind = 'dir'
        Mode = 'direct'
        Candidates = $pair[0].Count
        Skipped = $pair[1].Count
    }
}

$total = ($results | Measure-Object -Property Size -Sum).Sum

if ($Json) {
    $results | Select-Object Path, Note, Size, Kind, Mode, Candidates, Skipped | ConvertTo-Json
    if ($total -gt 0) { "`n# total_reclaimable_bytes=$total" }
    if (-not $Apply) { "# dry_run=true (use -Apply to clean)" }
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
    $modeStr = if ($_.Mode -eq 'direct') { '直接删除' } else { '回收站' }
    $detail = if ($_.Mode -eq 'direct') { "  [$($_.Candidates) 项可删 / $($_.Skipped) 项跳过]" } else { '' }
    Write-Host ("{0,12}  {1}  [{2}] ({3}){4}" -f $sizeStr, $_.Path, $_.Note, $modeStr, $detail)
}
Write-Host ""
$totalMB = [math]::Round($total / 1MB, 1)
$totalStr = if ($totalMB -ge 1024) { "{0:N1} GB" -f ($totalMB / 1024) } else { "{0:N1} MB" -f $totalMB }
Write-Host ("Total reclaimable: {0}" -f $totalStr) -ForegroundColor Yellow
if ($results | Where-Object { $_.Mode -eq 'direct' -and $_.Size -gt 0 }) {
    Write-Host "注意：标记为 [直接删除] 的目标（Temp/uv 缓存）不可恢复，被进程锁定的文件会自动跳过。" -ForegroundColor DarkYellow
}

if (-not $Apply) {
    Write-Host "`nDry run - nothing deleted. Re-run with -Apply to clean." -ForegroundColor Green
    return
}

# ---------------------------------------------------------------------------
# 执行阶段
# ---------------------------------------------------------------------------
$directTotal = ($results | Where-Object { $_.Mode -eq 'direct' } | Measure-Object -Property Size -Sum).Sum
if (-not $Force) {
    $hint = if ($directTotal -gt 0) { " 其中直接删除 {0:N1} GB 不可恢复（仅清 {1} 天前未修改的项）。" -f ($directTotal / 1GB), $MinAgeDays } else { '' }
    $confirm = Read-Host "Clean $($results.Count) target(s)?$hint (y/N)"
    if ($confirm -notmatch '^[yY]') { Write-Host "Aborted."; return }
}

$logDir = "$env:LOCALAPPDATA\mole\logs"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$logFile = Join-Path $logDir ("clean-{0:yyyyMMdd-HHmmss}.csv" -f (Get-Date))
$logRows = @()
$okCount = 0; $failCount = 0

foreach ($r in $results | Sort-Object Size -Descending) {
    try {
        if ($r.Mode -eq 'direct') {
            $counts = Remove-DirectTarget $r.Path $MinAgeDays
            $note = "direct ok=$($counts[0]) skip=$($counts[1]) (minage=${MinAgeDays}d)"
            $logRows += [pscustomobject]@{ Time = Get-Date -Format o; Path = $r.Path; Size = $r.Size; Status = $note }
            $okCount++
        } elseif ($r.Kind -eq 'dir') {
            Send-ToRecycleBin $r.Path
            $logRows += [pscustomobject]@{ Time = Get-Date -Format o; Path = $r.Path; Size = $r.Size; Status = 'ok' }
            $okCount++
        } else {
            Remove-Item -LiteralPath $r.Path -Force
            $logRows += [pscustomobject]@{ Time = Get-Date -Format o; Path = $r.Path; Size = $r.Size; Status = 'ok' }
            $okCount++
        }
    } catch {
        $logRows += [pscustomobject]@{ Time = Get-Date -Format o; Path = $r.Path; Size = $r.Size; Status = "fail: $_" }
        $failCount++
    }
}
$logRows | Export-Csv -Path $logFile -NoTypeInformation
Write-Host ""
Write-Host "Done: $okCount cleaned, $failCount failed." -ForegroundColor Yellow
Write-Host "Log: $logFile" -ForegroundColor Gray
