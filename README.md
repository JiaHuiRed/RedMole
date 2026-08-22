# 🛠 RedMole

> **Windows 磁盘分析 + 缓存清理工具，来自 macOS 清理工具 Mole 的移植版。**
> 作者：敏敏 · 基于 Go（Bubble Tea TUI）+ PowerShell 构建，删除一律走回收站。

[![版本](https://img.shields.io/badge/版本-v0.1.0-blue)](CHANGELOG.md)
[![平台](https://img.shields.io/badge/平台-Windows%2010%2F11-0078d4)](https://github.com/tw93/mole)
[![Go](https://img.shields.io/badge/Go-1.25-00add8)](https://go.dev)
[![上游](https://img.shields.io/badge/上游-Mole-ff6b35)](https://github.com/tw93/mole)
[![许可证](https://img.shields.io/badge/许可证-MIT-lightgrey)](LICENSE)

---

## ✨ 这是什么？

RedMole 是 [Mole](https://github.com/tw93/mole)（macOS 系统清理工具）的 **Windows 移植版**，继承它的产品哲学：**检查优先、删除可恢复、路径精确、操作留痕**。两个入口：`redmole-analyze` 终端磁盘分析（全盘分布 + 大文件 + 目录下钻 + 删除入口），`clean.ps1` 白名单缓存清理（npm / pip / 浏览器缓存等，默认只检查）。

---

## 🧭 核心功能

- 🗺️ **全盘 Overview**：自动枚举所有盘符 + 用户目录 + 隐藏空间洞察（Temp、npm 缓存、旧 Downloads 等），一眼看到空间去哪了
- 🔍 **目录下钻**：任何目录实时扫描，Top 20 大文件排名，增量过滤
- 🗑️ **安全删除**：所有删除经 `SHFileOperationW` 送**回收站**，可恢复；系统目录、其他用户目录、AppData（Temp 除外）受保护，拒绝执行
- 🧹 **clean.ps1 一键检查**：精确白名单目标，dry-run 默认，`-Apply` 才动手；小体积缓存走回收站，Temp/uv 大体积目标直接删除（三重安全门槛 + 明细展示）
- 📜 **操作日志**：每次清理写 CSV 到 `%LOCALAPPDATA%\mole\logs\`

## ⌨️ 使用

```powershell
# analyze：终端 TUI
.\redmole-analyze.exe                  # 全盘 overview
.\redmole-analyze.exe D:\some\dir      # 扫指定目录
.\redmole-analyze.exe --json D:\dir    # JSON 输出（脚本友好）
.\redmole-analyze.exe --json --depth 2 D:\dir   # 2 层嵌套 JSON
.\redmole-analyze.exe --json --top 10 C:\        # 只看最大 10 项

# clean：缓存清理
.\gui.ps1                 # 可视化面板：勾选 → 一键清理
.\clean.ps1                # 只检查：列出可回收空间（不删除）
.\clean.ps1 -Apply         # 执行：小缓存进回收站，Temp/uv 直接删除（默认仅清 14 天前未修改的项）
.\clean.ps1 -Apply -Force  # 跳过确认
.\clean.ps1 -MinAgeDays 30 # 收紧/放宽大体积目标的"最近修改"门槛（默认 14 天）
.\clean.ps1 -Json          # 机器可读输出
```

---

## 📁 项目结构

```
RedMole/
├── redmole-analyze.exe   # 编译产物（go build 生成）
├── clean.ps1             # 迷你清理工具（白名单 + 回收站 + 日志）
├── cmd/analyze/          # Go 磁盘分析 TUI（Mole cmd/analyze 移植）
│   ├── main.go           # 入口：路由 + Overview 构造
│   ├── scanner.go        # 并发扫描器（原生遍历，无 du/Spotlight）
│   ├── delete.go         # 回收站删除 + 路径保护（Windows 版）
│   ├── cache.go          # 分析缓存（%LOCALAPPDATA%\mole\analyzer）
│   └── insights.go       # 隐藏空间洞察（Windows 路径版）
└── internal/units/       # 字节格式化
```

---

## 🚀 构建

```powershell
go build -o redmole-analyze.exe ./cmd/analyze
```

> 国内网络需先设置镜像：`go env -w GOPROXY=https://goproxy.cn,direct`

---

## 🛠 技术栈

| 层 | 技术 |
|----|------|
| 分析 TUI | Go + Bubble Tea（跨平台，无 CGO） |
| 磁盘测量 | gopsutil + 原生遍历（无 du / Spotlight） |
| 回收站 | shell32 `SHFileOperationW`（FOF_ALLOWUNDO） |
| 缓存清理 | PowerShell 脚本（.NET / Microsoft.VisualBasic） |
| 缓存位置 | `%LOCALAPPDATA%\mole\` |

---

## 📋 更新日志

见 [CHANGELOG.md](CHANGELOG.md)。

---

## 💙 致谢

特别感谢 [tw93/mole](https://github.com/tw93/mole)——RedMole 的磁盘分析与安全删除逻辑源自这个优秀的 macOS 清理工具，本项目的移植建立在它的设计与实现之上。

- 构建者：敏敏
- 许可证：MIT
