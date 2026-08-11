# RedMole 项目记忆

> RedMole = Mole（macOS 清理工具）的 Windows 移植版。工作区 E:\AI\Mole\RedMole。

## 当前进度（260811 完成首版）

- ✅ analyze 移植完成：编译通过 + 全量测试全绿（3s）+ JSON/overview 实跑验证通过
- ✅ clean.ps1 完成：dry-run 实测扫出 17.8GB（npm-cache 16.4GB/pip 925MB/Edge 264MB/Chrome 183MB）
- ✅ README + git init（2 commits：010b1bf 移植、40ae9d4 gitignore）
- ⏳ 后续可选：TUI 实机体验、clean -Apply 实测、PowerShell 测试

## 关键路径

- 入口：`redmole-analyze.exe`（go build -o redmole-analyze.exe ./cmd/analyze）、`clean.ps1`
- 构建：`$env:GOPROXY=https://goproxy.cn,direct`（GFW，proxy.golang.org 不通）
- 测试：`go test -timeout 300s ./cmd/analyze`
- 环境：GOPATH 已迁 D:\go（用户级环境变量），GOPROXY 已 go env -w 持久化

## 踩坑记录（本项目特有）

1. **macOS 根路径硬编码是移植头号暗雷**：update.go:319 `currentPath != "/"` 死循环（Windows 上 C:\ 永远不等于 "/"）。修法：`filepath.Dir(currentPath) != currentPath` 通用终止
2. **Windows 不能删打开中的文件**：cache.go loadRawCacheFromDisk 删除前必须 file.Close()（os.Remove 静默失败）
3. **混合分隔符绕过 traversal 检测**：validatePath 需先归一化 "/" 再 split
4. **8.3 短名 SameFile 陷阱**：C:\Users\Administrator 的 ADMINI~1 短名与长名 os.SameFile 等价命中 → 整棵保护用户目录会误伤自己的 Temp，别用整棵保护
5. **Pagefile 膨胀（非代码 bug）**：go test 死循环 + 连续编译触发 pagefile.sys 涨到 25GB 吃掉 C 盘 15GB；Windows 自动管理 pagefile 只增不减，重启才收缩
6. **Go 缓存占 C 盘**：GOPATH 默认 C:\Users\Administrator\go 有 2.3GB 模块缓存 → 已 robocopy /MOVE 到 D:\go

## 架构决策

- 单包移植（无 build tag 双轨），RedMole 定位 Windows-only
- 删除统一走 SHFileOperationW 送回收站（FOF_ALLOWUNDO），不实现永久删除
- du/Spotlight 全砍，原生遍历 + 缓存兜底（调用点都有 fallback，返回错误即可）
- clean.ps1 白名单精确路径，不用模糊扫描；保护清单硬编码脚本顶部
