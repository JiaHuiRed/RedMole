# RedMole GUI - 可视化清理面板
# 用法: 右键"使用 PowerShell 运行" 或 pwsh -File gui.ps1
# 零依赖：仅用 .NET WinForms，Windows 10/11 自带。
# 数据来自 clean.ps1（同源逻辑），执行清理复用 clean.ps1 -Apply -Paths。

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic

$script:ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:CleanScript = Join-Path $ScriptDir 'clean.ps1'

# ---------------------------------------------------------------------------
# 控件
# ---------------------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = 'RedMole 清理面板'
$form.Size = New-Object System.Drawing.Size(860, 560)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)

$grid = New-Object System.Windows.Forms.DataGridView
$grid.Dock = 'Fill'
$grid.AllowUserToAddRows = $false
$grid.AllowUserToDeleteRows = $false
$grid.ReadOnly = $false
$grid.MultiSelect = $false
$grid.SelectionMode = 'FullRowSelect'
$grid.RowHeadersVisible = $false
$grid.AutoSizeColumnsMode = 'Fill'
$grid.BackgroundColor = [System.Drawing.Color]::White

# 勾选列
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

# 底部面板：状态 + 按钮
$bottom = New-Object System.Windows.Forms.Panel
$bottom.Dock = 'Bottom'
$bottom.Height = 92

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Location = New-Object System.Drawing.Point(12, 10)
$statusLabel.Size = New-Object System.Drawing.Size(620, 22)
$statusLabel.Text = '就绪。点击"扫描"检查可清理空间。'

$totalLabel = New-Object System.Windows.Forms.Label
$totalLabel.Location = New-Object System.Drawing.Point(12, 36)
$totalLabel.Size = New-Object System.Drawing.Size(620, 22)
$totalLabel.ForeColor = [System.Drawing.Color]::DarkOrange
$totalLabel.Text = ''

$scanBtn = New-Object System.Windows.Forms.Button
$scanBtn.Text = '扫描'
$scanBtn.Location = New-Object System.Drawing.Point(660, 10)
$scanBtn.Size = New-Object System.Drawing.Size(90, 30)

$cleanBtn = New-Object System.Windows.Forms.Button
$cleanBtn.Text = '清理勾选项'
$cleanBtn.Location = New-Object System.Drawing.Point(755, 10)
$cleanBtn.Size = New-Object System.Drawing.Size(95, 30)
$cleanBtn.BackColor = [System.Drawing.Color]::FromArgb(255, 220, 53, 69)
$cleanBtn.ForeColor = [System.Drawing.Color]::White

$selectAllBtn = New-Object System.Windows.Forms.Button
$selectAllBtn.Text = '全选'
$selectAllBtn.Location = New-Object System.Drawing.Point(660, 48)
$selectAllBtn.Size = New-Object System.Drawing.Size(90, 28)

$unselectBtn = New-Object System.Windows.Forms.Button
$unselectBtn.Text = '全不选'
$unselectBtn.Location = New-Object System.Drawing.Point(755, 48)
$unselectBtn.Size = New-Object System.Drawing.Size(95, 28)

$bottom.Controls.Add($statusLabel)
$bottom.Controls.Add($totalLabel)
$bottom.Controls.Add($scanBtn)
$bottom.Controls.Add($cleanBtn)
$bottom.Controls.Add($selectAllBtn)
$bottom.Controls.Add($unselectBtn)

$form.Controls.Add($grid)
$form.Controls.Add($bottom)

# ---------------------------------------------------------------------------
# 工具函数
# ---------------------------------------------------------------------------
function Format-Size([int64]$Bytes) {
    if ($Bytes -ge 1GB) { return ('{0:N1} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N1} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N1} KB' -f ($Bytes / 1KB)) }
    return "$Bytes B"
}

function Set-Status([string]$Text, [System.Drawing.Color]$Color = [System.Drawing.Color]::Black) {
    $statusLabel.Text = $Text
    $statusLabel.ForeColor = $Color
    $form.Refresh()
}

function Invoke-CleanScan {
    $scanBtn.Enabled = $false
    $cleanBtn.Enabled = $false
    Set-Status '正在扫描（大目录可能耗时）...' ([System.Drawing.Color]::DimGray)
    $grid.Rows.Clear()
    $totalLabel.Text = ''
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    try {
        $json = & pwsh -NoProfile -File $script:CleanScript -Json 2>$null | Out-String
        # clean.ps1 在 JSON 尾部追加 # 注释行，先剥离
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
            $grid.Rows[$idx].Tag = [pscustomobject]@{ Path = $it.Path; Size = [int64]$it.Size }
        }
        if ($items.Count -eq 0) {
            Set-Status '没有可清理的目标。' ([System.Drawing.Color]::Green)
        } else {
            Set-Status ("发现 {0} 个可清理目标。" -f $items.Count) ([System.Drawing.Color]::Black)
            $totalLabel.Text = "可回收合计：{0}" -f (Format-Size $total)
        }
    } catch {
        Set-Status ("扫描失败：{0}" -f $_.Exception.Message) ([System.Drawing.Color]::Red)
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
        Set-Status '请先勾选要清理的项目。' ([System.Drawing.Color]::DarkOrange)
        return
    }
    $sizeText = Format-Size (($selected | Measure-Object -Property Size -Sum).Sum)
    $answer = [System.Windows.Forms.MessageBox]::Show(
        "将把 $($selected.Count) 个项目（约 $sizeText）移入回收站。`n回收站里的内容仍占用磁盘，清空回收站后才真正释放空间。`n`n继续？",
        'RedMole 确认', 'YesNo', 'Warning')
    if ($answer -ne 'Yes') { return }

    $cleanBtn.Enabled = $false
    Set-Status '正在移入回收站...' ([System.Drawing.Color]::DimGray)
    try {
        $paths = @($selected | ForEach-Object { $_.Path })
        & pwsh -NoProfile -File $script:CleanScript -Apply -Force -Json -Paths $paths 2>&1 | Out-Null
        $logFile = Get-ChildItem "$env:LOCALAPPDATA\mole\logs\clean-*.csv" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        Set-Status ("清理完成。日志：{0}" -f $logFile.Name) ([System.Drawing.Color]::Green)
        Invoke-CleanScan
    } catch {
        Set-Status ("清理失败：{0}" -f $_.Exception.Message) ([System.Drawing.Color]::Red)
    } finally {
        $cleanBtn.Enabled = $true
    }
}

# ---------------------------------------------------------------------------
# 事件绑定
# ---------------------------------------------------------------------------
$scanBtn.Add_Click({ Invoke-CleanScan })
$cleanBtn.Add_Click({ Invoke-CleanSelected })
$selectAllBtn.Add_Click({
    foreach ($row in $grid.Rows) { $row.Cells[0].Value = $true }
})
$unselectBtn.Add_Click({
    foreach ($row in $grid.Rows) { $row.Cells[0].Value = $false }
})
$form.Add_Shown({ Invoke-CleanScan })

[System.Windows.Forms.Application]::Run($form)
