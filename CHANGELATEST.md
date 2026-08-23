# v0.3.4
## 新增 | New
- 本地更新器：更新改为直接 spawn 安装目录下的 `python -m deploy.update`，不再经过 server 的 HTTP 接口。Windows 会锁定已加载的 onnxruntime DLL，更新必须由不加载 OCR 的干净进程执行
- 新增 `ServerOperationLock`，把 Git 操作、配置读写与进程清理串行化，避免并发触发时互相踩踏
- 菜单加载失败自动重试，重试期间显示加载动画

## 改进 | Improved
- 日志按后端 23 列行首渲染，字号固定 12 并锁定行宽上限，等宽字体下整片日志成列
- Server 启动链的进程清理改为按 OAS 根目录过滤（读 `Win32_Process.CommandLine` 后比对根目录前缀），不再无差别结束机器上其它 Python 进程
- 启动链继承父环境变量并在任一步失败时立即停止，不再带着半初始化状态继续
- BOOL 勾选框与相邻列光学对齐，两个悬浮按钮改为横排
- CI：新增 GitHub→Gitee 自动同步 workflow，代码推送时同步最新 release

## 修复 | Fix
- 自启设置探测异常时也结束 loading，不再卡在转圈
- 日志毫秒截断改为锚定行首，保留真实空行，并补齐跨数据块的 utf-8 解码
- 更新器接入操作锁，修复进程树残留与 `onDone` 回调丢失
- 修复启动链断裂与日志乱码：PATH 分隔符与混编码解码

