# RedMole

[Mole](https://github.com/tw93/mole)（macOS 系统清理工具）的 Windows 移植版，保留其产品哲学：**检查优先、删除可恢复、路径精确、操作留痕**。

## 组件

| 组件 | 说明 |
|---|---|
| `redmole-analyze` | Go + Bubble Tea 磁盘分析 TUI（从 Mole `cmd/analyze` 移植）。终端界面浏览目录占用、Top 大文件、删除入口（送回收站） |
| `clean.ps1` | PowerShell 迷你清理工具：白名单目标、dry-run 默认、回收站路由、操作日志 |

## 构建与使用

```powershell
# analyze
go build -o redmole-analyze.exe ./cmd/analyze
.\redmole-analyze.exe          # 全盘 overview TUI
.\redmole-analyze.exe D:\some\dir   # 扫指定目录
.\redmole-analyze.exe --json D:\some\dir   # JSON 输出

# clean
.\clean.ps1                # 只检查：列出可回收空间（不删除）
.\clean.ps1 -Apply         # 执行：移入回收站（可恢复）
.\clean.ps1 -Apply -Force  # 跳过确认
.\clean.ps1 -Json          # 机器可读输出
```

clean 操作日志写在 `%LOCALAPPDATA%\mole\logs\clean-*.csv`。

## 与上游的差异

analyze 移植时替换的 macOS 专属依赖：

| macOS | Windows |
|---|---|
| Spotlight (`mdfind`) 大文件索引 | 原生遍历 |
| `du` 子进程测量 | 纯 Go 遍历（快路径） |
| `open` / `osascript` | `explorer` / `rundll32 url.dll,FileProtocolHandler` |
| `syscall.Statfs` 磁盘剩余 | gopsutil `disk.Usage` |
| Trash 路由（trash(8) / renameatx_np / Finder） | `SHFileOperationW`（FOF_ALLOWUNDO 送回收站） |
| 硬链接去重 / APFS 磁盘占用 | 逻辑大小（NTFS 无需） |
| `~/Library/Caches` 等 macOS 路径 | `%LOCALAPPDATA%`、`%TEMP%`、盘符根 |
| 保护：`/System` `/Library` bundle | `SystemRoot`、`ProgramFiles`、`ProgramData`、`WinSxS`、其他用户目录、`LOCALAPPDATA` 子树（Temp 除外） |

## 安全设计

- 删除一律经回收站（`SHFileOperationW` + `FOF_ALLOWUNDO`），可恢复
- 删除前路径校验：绝对路径、无 traversal、无 null 字节、受保护路径拒绝（`validateTrashTarget`）
- `clean.ps1` 目标为精确白名单路径，保护清单（会话状态、工具自身目录）硬编码在脚本顶部
- dry-run 默认：不加 `-Apply` 绝不删任何东西

## 已知限制

- `analyze` 删除行为在 Windows 上无自动化测试（SHFileOperationW 涉及真实 shell 交互）
- `C:\Windows\Temp` 与需要管理员权限的路径默认跳过
- pagefile / 系统文件不涉及：本工具只处理用户级可重建缓存
