# RedMole 更新日志

## 0.0.2（2026-08-12）

### ✨ 新功能

- **大体积临时目标清理** — `clean.ps1` 新增 Temp / uv 缓存两档目标（`$DirectTargets`）：回收站也在系统盘，几十 GB 送回收站等于没释放空间，改为**直接删除**（不可恢复）
- **三重安全门槛** — 大体积目标仅当同时满足「不在保护清单」「修改时间早于 `-MinAgeDays`（默认 14 天）」「删除时未被进程锁定」才删；dry-run 展示「X 项可删 / Y 项跳过」明细
- **uv 依赖缓存** — 覆盖 `%LOCALAPPDATA%\uv\cache\archive-v0`（jcodemunch 等升级只增不减的历史依赖环境）

### 🐛 修复

- **保护清单绕过（高危）** — `Test-Protected` 用 `StartsWith(路径 + '\')` 只保护保护目录的*子项*，不保护*目录自身*；v0.0.2 开发中实测 `-Apply` 曾误删 `Temp\claude` / `Temp\redcode`。修复为「目录自身 + 后代」双重匹配，并固化为回归测试 `tests/test-protected.ps1`（8 用例）

### 📝 说明

- 误删教训：直接删除模式把「口子开大」，违背原「精确白名单 + 回收站可恢复」哲学。0.0.2 保留直接删除以解决 C 盘爆红救急，但以三重门槛 + 明细展示 + 操作日志把风险收敛回可控

## 0.0.1（2026-08-11）

### ✨ 新功能

- **磁盘分析 TUI** — 移植 Mole `cmd/analyze`：全盘 Overview、目录下钻、Top 大文件、增量过滤、JSON 输出
- **回收站删除** — 所有删除经 SHFileOperationW 送回收站（可恢复），系统/用户目录保护
- **缓存清理** — `clean.ps1`：白名单目标、dry-run 默认、操作日志（CSV）
- **GUI 面板** — `gui.ps1`：WinForms 可视化勾选清理 + 磁盘分析（盘符选择、目录下钻），零依赖双击即用
- **Windows 原生替换** — 去 Spotlight/du/Trash 等 macOS 依赖，全 Go 原生遍历 + gopsutil
- **隐藏空间洞察** — Temp / npm / pip / 浏览器缓存 / 旧 Downloads 自动识别
