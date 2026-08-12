# Test-Protected 回归测试 —— 防止保护清单再被绕过
# 用法: pwsh -NoProfile -File tests\test-protected.ps1  （退出码 0=通过）
# 背景: v0.0.2 曾因 StartsWith 缺路径分隔符边界 + 不覆盖"目录自身"，
#       导致 Temp\claude / Temp\redcode 保护目录被 clean.ps1 误删（不可恢复）。
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$ps1 = Get-Content (Join-Path $here '..\clean.ps1') -Raw

# 提取 Test-Protected 函数体单独执行（避免跑整个脚本）
$match = [regex]::Match($ps1, 'function Test-Protected\(\[string\]\$Path\) \{.*?\n\}', 'Singleline')
if (-not $match.Success) { throw "Test-Protected 函数未找到" }
Invoke-Expression ($match.Value -replace '\r', '')

# 覆盖全局保护清单（模拟脚本环境）
$script:ProtectedPaths = @(
    "$env:LOCALAPPDATA\mole",
    "$env:LOCALAPPDATA\Temp\claude",
    "$env:LOCALAPPDATA\Temp\redcode",
    "$env:WINDIR\Temp"
)

$cases = @(
    @{ Path = "$env:LOCALAPPDATA\Temp\claude";              Expect = $true;  Name = "保护目录自身" },
    @{ Path = "$env:LOCALAPPDATA\Temp\redcode";              Expect = $true;  Name = "保护目录自身 redcode" },
    @{ Path = "$env:LOCALAPPDATA\Temp\claude\sub\file.tmp"; Expect = $true;  Name = "保护目录子项" },
    @{ Path = "$env:LOCALAPPDATA\Temp\claudebak";            Expect = $false; Name = "相似前缀（应放行）" },
    @{ Path = "$env:LOCALAPPDATA\Temp\random";               Expect = $false; Name = "普通临时项（应放行）" },
    @{ Path = "$env:LOCALAPPDATA\mole\analyzer\abc.cache";   Expect = $true;  Name = "mole 自身缓存" },
    @{ Path = "$env:WINDIR\Temp\foo.tmp";                    Expect = $true;  Name = "系统临时" },
    @{ Path = "$env:WINDIR\TempX\foo.tmp";                   Expect = $false; Name = "系统临时相似前缀（应放行）" }
)

$fail = 0
foreach ($c in $cases) {
    $got = Test-Protected $c.Path
    $ok = $got -eq $c.Expect
    if (-not $ok) { $fail++ }
    "{0,-6} {1,-28} {2}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $c.Name, $c.Path
}
"`n结果: $($cases.Count - $fail)/$($cases.Count) 通过"
exit $fail
