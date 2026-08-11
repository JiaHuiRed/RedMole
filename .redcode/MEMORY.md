# RedMole 项目记忆

> RedMole = Mole（macOS 清理工具）的 Windows 移植版。工作区 E:\AI\Mole\RedMole。

## 当前进度（260811 完成首版）

- ✅ analyze 移植完成：编译通过 + 全量测试全绿（3s）+ JSON/overview 实跑验证通过
- ✅ clean.ps1 完成：dry-run 实测扫出 17.8GB（npm-cache 16.4GB/pip 925MB/Edge 264MB/Chrome 183MB）
- ✅ gui.ps1 WinForms 面板：缓存清理 + 磁盘分析双 Tab（盘符选择/下钻），实机启动验证通过
- ✅ 已推送 https://github.com/JiaHuiRed/RedMole.git（master，5 commits）
- ✅ README（RedStudio 风格）+ CHANGELOG 0.0.1 + LICENSE + git（3 commits）
- ⏳ 遗留：npm-cache 源目录残留 440MB/35k items（node 进程锁定，重启后自然消失，D:\npm-cache 已完整备份）

## 关键路径

- 入口：`redmole-analyze.exe`、`clean.ps1`、`gui.ps1`（双击/右键 PowerShell 运行）
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
7. **PowerShell 变量大小写不敏感**：clean.ps1 的 `$paths` 循环变量覆盖了 `-Paths` 参数（$Paths）→ 过滤静默失效。局部变量永远避开参数名
8. **robocopy 默认重试参数是坑**：/R:1000000 /W:30 遇锁定文件重试 100 万次每次 30 秒 → 卡死 300s+。一律带 /R:1 /W:1
9. **npm/pnpm 共用 cacache 格式只增不减**：npm-cache 17.6GB 中 _cacache/content-v2 15.4GB 按内容哈希存包本体，重装/升级不回收 → 缓存挪 D 盘（npm config set cache D:\npm-cache + pip config set global.cache-dir D:\pip-cache 已配）

## 架构决策

- 单包移植（无 build tag 双轨），RedMole 定位 Windows-only
- 删除统一走 SHFileOperationW 送回收站（FOF_ALLOWUNDO），不实现永久删除
- du/Spotlight 全砍，原生遍历 + 缓存兜底（调用点都有 fallback，返回错误即可）
- clean.ps1 白名单精确路径，不用模糊扫描；保护清单硬编码脚本顶部
