# v0.3.5
## 新增 | New
- 日志字体自定义：可选字体与字号，设置即时生效（感谢 @SuAstronaut 的贡献）

## 改进 | Improved
- 更新器技术信息面板与日志/首页展示细节优化

## 修复 | Fix
- OAS 目录识别不再要求预装 toolkit/Git 与 config/deploy.yaml（后者已移出仓库分发），缺失由 installer 自愈，手动拷贝的残缺安装也能启动
- 进程清理命令改用 PowerShell 绝对路径：个别机器 PATH 不含 PowerShell 目录，裸 `powershell` 会直接报命令不存在
- 进程清理成败改为树杀后复查存活判定：taskkill 树杀父进程会连带终止子进程，逐条判退出码会把正常树杀误报为失败
- 启动链主动 kill 旧会话产生的 ShellException 不再误报为命令失败

