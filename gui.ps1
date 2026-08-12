# RedMole GUI - 可视化面板（缓存清理 + 磁盘分析）
# 用法: 右键"使用 PowerShell 运行" 或 pwsh -File gui.ps1
# 零依赖：仅用 .NET WinForms，Windows 10/11 自带。
# 数据来源：缓存清理走 clean.ps1；磁盘分析走 redmole-analyze.exe --json。

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic

$script:ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:CleanScript = Join-Path $ScriptDir 'clean.ps1'
$script:AnalyzeExe = Join-Path $ScriptDir 'redmole-analyze.exe'

# ---------------------------------------------------------------------------
# 窗体
# ---------------------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = 'RedMole 面板'
$form.Size = New-Object System.Drawing.Size(920, 600)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Dock = 'Fill'

# ===========================================================================
# Tab 1: 缓存清理
# ===========================================================================
$cleanTab = New-Object System.Windows.Forms.TabPage
$cleanTab.Text = '缓存清理'
$cleanTab.Padding = New-Object System.Windows.Forms.Padding(6)

$grid = New-Object System.Windows.Forms.DataGridView
$grid.Dock = 'Fill'
$grid.AllowUserToAddRows = $false
$grid.AllowUserToDeleteRows = $false
$grid.MultiSelect = $false
$grid.SelectionMode = 'FullRowSelect'
$grid.RowHeadersVisible = $false
$grid.AutoSizeColumnsMode = 'Fill'
$grid.BackgroundColor = [System.Drawing.Color]::White

$checkCol = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
$checkCol.HeaderText = '清理'
$checkCol.Width = 50
$checkCol.FillWeight = 5
$grid.Columns.Add($checkCol) | Out-Null

$pathCol = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$pathCol.HeaderText = '路径'
$pathCol.FillWeight = 60
$grid.Columns.Add($pathCol) | Out-Null

$noteCol = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$noteCol.HeaderText = '说明'
$noteCol.FillWeight = 18
$grid.Columns.Add($noteCol) | Out-Null

$sizeCol = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$sizeCol.HeaderText = '大小'
$sizeCol.FillWeight = 10
$sizeCol.ReadOnly = $true
$grid.Columns.Add($sizeCol) | Out-Null

$cleanBottom = New-Object System.Windows.Forms.Panel
$cleanBottom.Dock = 'Bottom'
$cleanBottom.Height = 90

$cleanStatus = New-Object System.Windows.Forms.Label
$cleanStatus.Location = New-Object System.Drawing.Point(10, 10)
$cleanStatus.Size = New-Object System.Drawing.Size(560, 22)
$cleanStatus.Text = '就绪。点击"扫描"检查可清理空间。'

$cleanTotal = New-Object System.Windows.Forms.Label
$cleanTotal.Location = New-Object System.Drawing.Point(10, 36)
$cleanTotal.Size = New-Object System.Drawing.Size(560, 22)
$cleanTotal.ForeColor = [System.Drawing.Color]::DarkOrange
$cleanTotal.Text = ''

$scanBtn = New-Object System.Windows.Forms.Button
$scanBtn.Text = '扫描'
$scanBtn.Location = New-Object System.Drawing.Point(590, 10)
$scanBtn.Size = New-Object System.Drawing.Size(90, 30)

$cleanBtn = New-Object System.Windows.Forms.Button
$cleanBtn.Text = '清理勾选项'
$cleanBtn.Location = New-Object System.Drawing.Point(685, 10)
$cleanBtn.Size = New-Object System.Drawing.Size(100, 30)
$cleanBtn.BackColor = [System.Drawing.Color]::FromArgb(255, 220, 53, 69)
$cleanBtn.ForeColor = [System.Drawing.Color]::White

$selectAllBtn = New-Object System.Windows.Forms.Button
$selectAllBtn.Text = '全选'
$selectAllBtn.Location = New-Object System.Drawing.Point(590, 48)
$selectAllBtn.Size = New-Object System.Drawing.Size(90, 28)

$unselectBtn = New-Object System.Windows.Forms.Button
$unselectBtn.Text = '全不选'
$unselectBtn.Location = New-Object System.Drawing.Point(685, 48)
$unselectBtn.Size = New-Object System.Drawing.Size(100, 28)

$cleanBottom.Controls.Add($cleanStatus)
$cleanBottom.Controls.Add($cleanTotal)
$cleanBottom.Controls.Add($scanBtn)
$cleanBottom.Controls.Add($cleanBtn)
$cleanBottom.Controls.Add($selectAllBtn)
$cleanBottom.Controls.Add($unselectBtn)

$cleanTab.Controls.Add($grid)
$cleanTab.Controls.Add($cleanBottom)
$tabs.TabPages.Add($cleanTab)

# ===========================================================================
# Tab 2: 磁盘分析
# ===========================================================================
$diskTab = New-Object System.Windows.Forms.TabPage
$diskTab.Text = '磁盘分析'
$diskTab.Padding = New-Object System.Windows.Forms.Padding(6)

$diskTop = New-Object System.Windows.Forms.Panel
$diskTop.Dock = 'Top'
$diskTop.Height = 44

$driveLabel = New-Object System.Windows.Forms.Label
$driveLabel.Text = '盘符:'
$driveLabel.Location = New-Object System.Drawing.Point(10, 13)
$driveLabel.Size = New-Object System.Drawing.Size(45, 22)

$driveCombo = New-Object System.Windows.Forms.ComboBox
$driveCombo.Location = New-Object System.Drawing.Point(58, 10)
$driveCombo.Size = New-Object System.Drawing.Size(70, 24)
$driveCombo.DropDownStyle = 'DropDownList'

$diskScanBtn = New-Object System.Windows.Forms.Button
$diskScanBtn.Text = '扫描'
$diskScanBtn.Location = New-Object System.Drawing.Point(140, 9)
$diskScanBtn.Size = New-Object System.Drawing.Size(70, 26)

$upBtn = New-Object System.Windows.Forms.Button
$upBtn.Text = '← 返回上级'
$upBtn.Location = New-Object System.Drawing.Point(218, 9)
$upBtn.Size = New-Object System.Drawing.Size(95, 26)
$upBtn.Enabled = $false

$diskPathLabel = New-Object System.Windows.Forms.Label
$diskPathLabel.Location = New-Object System.Drawing.Point(325, 13)
$diskPathLabel.Size = New-Object System.Drawing.Size(560, 22)
$diskPathLabel.ForeColor = [System.Drawing.Color]::DimGray
$diskPathLabel.Text = ''

$diskTop.Controls.Add($driveLabel)
$diskTop.Controls.Add($driveCombo)
$diskTop.Controls.Add($diskScanBtn)
$diskTop.Controls.Add($upBtn)
$diskTop.Controls.Add($diskPathLabel)

$diskGrid = New-Object System.Windows.Forms.DataGridView
$diskGrid.Dock = 'Fill'
$diskGrid.AllowUserToAddRows = $false
$diskGrid.AllowUserToDeleteRows = $false
$diskGrid.ReadOnly = $true
$diskGrid.MultiSelect = $false
$diskGrid.SelectionMode = 'FullRowSelect'
$diskGrid.RowHeadersVisible = $false
$diskGrid.AutoSizeColumnsMode = 'Fill'
$diskGrid.BackgroundColor = [System.Drawing.Color]::White

$dNameCol = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$dNameCol.HeaderText = '名称'
$dNameCol.FillWeight = 40
$diskGrid.Columns.Add($dNameCol) | Out-Null

$dSizeCol = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$dSizeCol.HeaderText = '大小'
$dSizeCol.FillWeight = 15
$diskGrid.Columns.Add($dSizeCol) | Out-Null

$dTypeCol = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$dTypeCol.HeaderText = '类型'
$dTypeCol.FillWeight = 8
$diskGrid.Columns.Add($dTypeCol) | Out-Null

$dAccessCol = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$dAccessCol.HeaderText = '最近访问'
$dAccessCol.FillWeight = 20
$diskGrid.Columns.Add($dAccessCol) | Out-Null

$diskStatus = New-Object System.Windows.Forms.Label
$diskStatus.Dock = 'Bottom'
$diskStatus.Height = 24
$diskStatus.Text = '选择盘符后点击"扫描"。双击目录行可下钻。'
$diskStatus.ForeColor = [System.Drawing.Color]::DimGray

$diskTab.Controls.Add($diskGrid)
$diskTab.Controls.Add($diskStatus)
$diskTab.Controls.Add($diskTop)
$tabs.TabPages.Add($diskTab)

$form.Controls.Add($tabs)

# ---------------------------------------------------------------------------
# 工具函数
# ---------------------------------------------------------------------------
function Format-Size([int64]$Bytes) {
    if ($Bytes -ge 1GB) { return ('{0:N1} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N1} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N1} KB' -f ($Bytes / 1KB)) }
    return "$Bytes B"
}

function Set-CleanStatus([string]$Text, [System.Drawing.Color]$Color = [System.Drawing.Color]::Black) {
    $cleanStatus.Text = $Text
    $cleanStatus.ForeColor = $Color
    $form.Refresh()
}

# ---------------------------------------------------------------------------
# Tab 1: 缓存清理
# ---------------------------------------------------------------------------
function Invoke-CleanScan {
    $scanBtn.Enabled = $false
    $cleanBtn.Enabled = $false
    Set-CleanStatus '正在扫描（大目录可能耗时）...' ([System.Drawing.Color]::DimGray)
    $grid.Rows.Clear()
    $cleanTotal.Text = ''
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    try {
        $json = & pwsh -NoProfile -File $script:CleanScript -Json 2>$null | Out-String
        $json = ($json -split "`n" | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
        $items = $json | ConvertFrom-Json
        $total = 0L
        foreach ($it in $items) {
            $total += [int64]$it.Size
            $idx = $grid.Rows.Add()
            $grid.Rows[$idx].Cells[0].Value = $false
            $grid.Rows[$idx].Cells[1].Value = $it.Path
            $grid.Rows[$idx].Cells[2].Value = $it.Note
            $grid.Rows[$idx].Cells[3].Value = Format-Size ([int64]$it.Size)
            $grid.Rows[$idx].Tag = [pscustomobject]@{ Path = $it.Path; Size = [int64]$it.Size; Mode = $it.Mode }
        }
        if ($items.Count -eq 0) {
            Set-CleanStatus '没有可清理的目标。' ([System.Drawing.Color]::Green)
        } else {
            Set-CleanStatus ("发现 {0} 个可清理目标。" -f $items.Count) ([System.Drawing.Color]::Black)
            $cleanTotal.Text = "可回收合计：{0}" -f (Format-Size $total)
        }
    } catch {
        Set-CleanStatus ("扫描失败：{0}" -f $_.Exception.Message) ([System.Drawing.Color]::Red)
    } finally {
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
        $scanBtn.Enabled = $true
        $cleanBtn.Enabled = $true
    }
}

function Invoke-CleanSelected {
    $selected = @()
    foreach ($row in $grid.Rows) {
        if ($row.Cells[0].Value -eq $true -and $row.Tag) { $selected += $row.Tag }
    }
    if ($selected.Count -eq 0) {
        Set-CleanStatus '请先勾选要清理的项目。' ([System.Drawing.Color]::DarkOrange)
        return
    }
    $sizeText = Format-Size (($selected | Measure-Object -Property Size -Sum).Sum)
    $direct = @($selected | Where-Object { $_.Tag.Mode -eq 'direct' })
    $recycle = @($selected | Where-Object { $_.Tag.Mode -ne 'direct' })
    $note = ""
    if ($recycle.Count -gt 0) { $note += "`n$($recycle.Count) 项将移入回收站（可恢复）。" }
    if ($direct.Count -gt 0) { $note += "`n$($direct.Count) 项（Temp/uv 缓存）将直接删除，不可恢复（仅清 14 天前未修改的项，锁定的自动跳过）。" }
    $answer = [System.Windows.Forms.MessageBox]::Show(
        "将清理 $($selected.Count) 个项目（约 $sizeText）。$note`n`n继续？",
        'RedMole 确认', 'YesNo', 'Warning')
    if ($answer -ne 'Yes') { return }

    $cleanBtn.Enabled = $false
    Set-CleanStatus '正在清理...' ([System.Drawing.Color]::DimGray)
    try {
        $paths = @($selected | ForEach-Object { $_.Path })
        & pwsh -NoProfile -File $script:CleanScript -Apply -Force -Json -Paths $paths 2>&1 | Out-Null
        $logFile = Get-ChildItem "$env:LOCALAPPDATA\mole\logs\clean-*.csv" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        Set-CleanStatus ("清理完成。日志：{0}" -f $logFile.Name) ([System.Drawing.Color]::Green)
        Invoke-CleanScan
    } catch {
        Set-CleanStatus ("清理失败：{0}" -f $_.Exception.Message) ([System.Drawing.Color]::Red)
    } finally {
        $cleanBtn.Enabled = $true
    }
}

# ---------------------------------------------------------------------------
# Tab 2: 磁盘分析
# ---------------------------------------------------------------------------
$script:CurrentDiskPath = ''

function Set-DiskStatus([string]$Text, [System.Drawing.Color]$Color = [System.Drawing.Color]::DimGray) {
    $diskStatus.Text = $Text
    $diskStatus.ForeColor = $Color
    $form.Refresh()
}

function Invoke-DiskScan([string]$Path) {
    $script:CurrentDiskPath = $Path
    $diskPathLabel.Text = $Path
    $diskGrid.Rows.Clear()
    $diskScanBtn.Enabled = $false
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    Set-DiskStatus "正在扫描 $Path ..." ([System.Drawing.Color]::DimGray)
    try {
        $json = & $script:AnalyzeExe --json $Path 2>$null | Out-String
        $obj = $json | ConvertFrom-Json
        foreach ($it in ($obj.entries | Sort-Object { [int64]$_.size } -Descending)) {
            $idx = $diskGrid.Rows.Add()
            $diskGrid.Rows[$idx].Cells[0].Value = $it.name
            $diskGrid.Rows[$idx].Cells[1].Value = Format-Size ([int64]$it.size)
            $diskGrid.Rows[$idx].Cells[2].Value = $(if ($it.is_dir) { '目录' } else { '文件' })
            $diskGrid.Rows[$idx].Cells[3].Value = $it.last_access
            $diskGrid.Rows[$idx].Tag = [pscustomobject]@{ Path = $it.path; IsDir = $it.is_dir }
        }
        $upBtn.Enabled = $Path -ne (Split-Path -Qualifier $Path)
        Set-DiskStatus ("{0} 个条目（双击目录下钻）" -f $diskGrid.Rows.Count) ([System.Drawing.Color]::DimGray)
    } catch {
        Set-DiskStatus ("扫描失败：{0}" -f $_.Exception.Message) ([System.Drawing.Color]::Red)
    } finally {
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
        $diskScanBtn.Enabled = $true
    }
}

function Initialize-DriveList {
    $driveCombo.Items.Clear()
    foreach ($d in [System.IO.DriveInfo]::GetDrives()) {
        if ($d.IsReady -and $d.DriveType -eq 'Fixed') {
            $driveCombo.Items.Add($d.Name)
        }
    }
    if ($driveCombo.Items.Count -gt 0) { $driveCombo.SelectedIndex = 0 }
}

$driveCombo.Add_SelectedIndexChanged({
    if ($driveCombo.SelectedItem) {
        $upBtn.Enabled = $false
        Invoke-DiskScan $driveCombo.SelectedItem
    }
})
$diskScanBtn.Add_Click({
    if ($driveCombo.SelectedItem) { Invoke-DiskScan $driveCombo.SelectedItem }
})
$upBtn.Add_Click({
    $parent = Split-Path -Parent $script:CurrentDiskPath
    if ($parent -and $parent -ne $script:CurrentDiskPath) { Invoke-DiskScan $parent }
})
$diskGrid.Add_CellDoubleClick({
    if ($_.RowIndex -ge 0) {
        $tag = $diskGrid.Rows[$_.RowIndex].Tag
        if ($tag -and $tag.IsDir) { Invoke-DiskScan $tag.Path }
    }
})

# ---------------------------------------------------------------------------
# Tab 1: 事件绑定
# ---------------------------------------------------------------------------
$scanBtn.Add_Click({ Invoke-CleanScan })
$cleanBtn.Add_Click({ Invoke-CleanSelected })
$selectAllBtn.Add_Click({
    foreach ($row in $grid.Rows) { $row.Cells[0].Value = $true }
})
$unselectBtn.Add_Click({
    foreach ($row in $grid.Rows) { $row.Cells[0].Value = $false }
})

$form.Add_Shown({
    Initialize-DriveList
    Invoke-CleanScan
})

[System.Windows.Forms.Application]::Run($form)
