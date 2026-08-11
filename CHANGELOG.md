# RedMole 更新日志

## 0.0.1（2026-08-11）

### ✨ 新功能

- **磁盘分析 TUI** — 移植 Mole `cmd/analyze`：全盘 Overview、目录下钻、Top 大文件、增量过滤、JSON 输出
- **回收站删除** — 所有删除经 SHFileOperationW 送回收站（可恢复），系统/用户目录保护
- **缓存清理** — `clean.ps1`：白名单目标、dry-run 默认、操作日志（CSV）
- **GUI 面板** — `gui.ps1`：WinForms 可视化勾选清理 + 磁盘分析（盘符选择、目录下钻），零依赖双击即用
- **Windows 原生替换** — 去 Spotlight/du/Trash 等 macOS 依赖，全 Go 原生遍历 + gopsutil
- **隐藏空间洞察** — Temp / npm / pip / 浏览器缓存 / 旧 Downloads 自动识别
