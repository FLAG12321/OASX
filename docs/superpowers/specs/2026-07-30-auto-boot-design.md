# 开机自启全自动流程（拉起 server + 延时错峰自启脚本）— 设计文档

- 日期：2026-07-30
- 状态：已实施（计划 docs/superpowers/plans/2026-07-30-auto-boot.md），待 code-reviewer 审查与用户验收
- 涉及仓库：仅前端 OASX（后端零改动）
- 目标流程：开机自启拉起 OASX → OASX 自动拉起 server → 检测后端就绪 → 自动进入主界面 → 按各脚本配置的延时依次错峰启动脚本

## 1. 问题

1. 现状自动启动脚本的触发点在「登录进 `/main`」之后：`ScriptService` 由 `/main` 路由的 `LayoutBinding` 注册，`onInit` 里轮询后端可达后**并发**启动所有勾选脚本，没有延时选项，多个 OAS 实例同时启动会抢资源。
2. server（`server.py` 后端进程）必须用户手动在 Server 页点按钮拉起，开机自启只拉起了 OASX 本体，后续全靠人工。
3. 自启动脚本配置面板要求 `ScriptService` 已注册（即已登录），未登录时只显示「登录后可配置自动启动脚本」，而用户希望 server 启动后（无需登录）就能配置。

## 2. 现状机制（探索结论）

| 环节 | 位置 | 行为 |
| --- | --- | --- |
| 开机自启注册 | `lib/service/auto_start_service.dart` | schtasks（Win）/ LaunchAgent plist（mac）/ autostart .desktop（Linux）注册 OASX 可执行文件，**不带任何参数** |
| server 拉起 | `lib/controller/server/server_controller.dart` `run()` | shell 执行 `python -m deploy.installer` + `taskkill /f /t /im pythonw.exe`（杀掉系统内所有 pythonw 进程）+ `pythonw.exe server.py`，依赖 `rootPathServer` 路径校验；命令为 **Windows 专属** |
| 自动登录 | `lib/controller/login/login_controller.dart` `onInit` | 存有 address 且未登录过则自动 `login()`：testAddress 可达 → `Get.offAllNamed('/main')`；不可达 → snackbar 报错留在登录页 |
| 脚本自启 | `lib/service/script_service.dart` `onInit` | 500ms×5 轮询 `/test`，可达即**并发**启动 `autoScriptList` 中未运行的脚本 |
| 自启配置存储 | `StorageKey.autoScriptList` | 脚本名 JSON 数组（如 `["OAS1","OAS2"]`），GetStorage 持久化 |
| 配置面板 | `lib/views/server/auto_start_settings.dart` | `Get.isRegistered<ScriptService>()` 为 false 时只显示登录提示 |

## 3. 目标与决策（均经用户确认）

- **触发条件**：OASX 确实被开机自启拉起（启动参数含 `--autostart`）**且**自启脚本列表非空，才走全自动流程；用户手动双击打开 OASX 不触发（即使开关都勾选）。
- **server 拉起**：满足触发条件时由 OASX 自动完成（复用 Server 页现有 shell 启动逻辑）。
- **延时粒度**：每个脚本单独设置延时秒数，实现错峰依次启动。
- **计时起点**：后端就绪时刻（`/test` 首次响应成功），不管 server 是 OASX 拉起的还是本来就在运行。
- **就绪后跳转**：自动完成登录进入主界面（复用现有登录链路）。
- **手动登录不再自启脚本**：这是行为变更——现状是每次登录进 `/main` 都自动启动勾选脚本，改造后仅开机自启全自动流程会启动脚本。
- **配置面板时机**：server 可达即可配置（用已保存地址直接拉脚本列表，无需登录）；不可达时显示提示，不提供缓存列表。
- **后端地址取值规则**（自动流程与面板探测共用）：优先取已保存的登录地址（`StorageKey.address`），未保存过则用默认 `127.0.0.1:22288`。探测前调 `ApiClient().setAddress()` 设置全局地址——与登录行为一致，且手动登录时会用用户输入值重新覆盖，无负面影响。
- **平台约束**：自动拉起 server 的命令（`pythonw.exe`、`taskkill`）为 Windows 专属，仅 Windows 执行拉起；macOS/Linux 走降级流程——跳过拉起步骤，仅轮询探测已在运行的 server，就绪后照常调度。

## 4. 方案设计（方案 A：AutoBootService 统一编排）

### 4.1 架构与组件

新增：

- `lib/service/auto_boot_service.dart` — `AutoBootService`（GetxService，`initService()` 中**所有平台**注册，流程仅桌面且带 `--autostart` 时执行）：
  - 持有自启配置状态 `autoScriptEntries`（`RxList<AutoScriptEntry>`，storage 读写与迁移，见 4.3）
  - 编排自动流程，状态机：`idle / startingServer / waitingReady / loggingIn / scheduling / done / failed`
  - 记录后端就绪时刻 T0，按各脚本延时调度启动
- `lib/service/server_launcher.dart` — 从 `ServerController` 抽出的 server 拉起逻辑（rootPathServer 读取、路径校验、shell 执行 installer + taskkill + server.py，含杀掉所有 pythonw 进程的既有副作用，Windows 专属），`ServerController.run()` 与 `AutoBootService` 共用；日志仍回流 Server 页日志区

修改：

- `lib/main.dart` — `main(List<String> args)` 接收启动参数，`--autostart` 标记传入 `AutoBootService`
- `lib/service/auto_start_service.dart` — 三平台开机自启注册项追加 `--autostart` 启动参数（schtasks XML `<Arguments>`、plist `ProgramArguments`、.desktop `Exec`）。**已有用户需重新关开一次「开机自启」开关才会带上参数**（升级说明中注明）
- `lib/service/script_service.dart` — 删除 `onInit` 中 `_waitBackendReadyAndAutoRun()` 无条件自启；`onInit` 完成脚本连接后回调 `AutoBootService.onScriptServiceReady()`；新增 `scheduleAutoRun` 相关启动入口仅由 `AutoBootService` 调用；自启配置读写改走 `AutoBootService`（删除脚本时同步移除条目的逻辑保留）
- `lib/controller/login/login_controller.dart` — `onInit` 自动登录在 `--autostart` 流程激活时跳过（登录时机让位给 AutoBootService）；手动登录路径不变
- `lib/views/server/auto_start_settings.dart` — 面板改造（4.4）
- `lib/model/const/storage_key.dart`、i18n 三文件 — 存储 key 注释与新文案

### 4.2 自动流程时序

```
OASX 启动(--autostart && autoScriptEntries 非空 && 桌面平台)
  → AutoBootService.start()   // 幂等，仅执行一次
      1. 按地址取值规则 setAddress；探测 /test：已可达则跳过 2（server 已在跑）
      2. （仅 Windows）校验 rootPathServer 有效 → ServerLauncher 拉起 server.py；
         macOS/Linux 跳过本步
      3. 轮询 /test（间隔 2s，超时 5 分钟）
      4. 首次可达时刻记为 T0；若当前不在 /main，直接 Get.offAllNamed('/main')
         跳转（地址已 set、可达已确认，与 LoginController.login 成功路径等效）
      5. LayoutBinding 注册 ScriptService，其 onInit 完成脚本连接后主动调
         AutoBootService.onScriptServiceReady()，AutoBootService 随即
         scheduleAutoRun(T0)（衔接机制：ScriptService 回调，非轮询）
      6. 每个勾选脚本 i：剩余延时 = max(0, delaySeconds_i - (now - T0))，
         Timer 到点启动；已在运行的跳过；已不存在于 scriptModelMap 的
         （后端侧被删除）跳过并记日志
```

- **自动登录的让位**：`--autostart` 流程激活时，`LoginController.onInit` 的自动登录**跳过**（否则 server 未起时必然失败弹错误 snackbar、且静态 `logined` 被置位），登录跳转时机全权由 AutoBootService 掌控；非自动流程下自动登录行为不变
- 不满足触发条件：行为与现有手动流程一致，唯一差别是登录后不再自动启动脚本
- 全部到点启动后沿用现有「延迟采样 + snackbar 汇报成功列表」逻辑

### 4.3 数据模型与存储

- 存储 key 沿用 `StorageKey.autoScriptList`，值升级为对象数组 JSON：`[{"name":"OAS1","delaySeconds":30}, ...]`
- 读取兼容迁移（覆盖现状全部三种历史形态）：raw List 直存与 JSON 字符串两种容器都接受；元素为字符串（旧格式）→ `{name, delaySeconds: 0}`，元素为对象（新格式）→ 直接解析；读到旧格式后立即按新格式写回；解析失败按空列表处理
- 新增模型 `AutoScriptEntry { String name; int delaySeconds; }`（delaySeconds 取值 0–86400，非法值按 0 处理）
- 配置状态归属从 `ScriptService` 上移到 `AutoBootService`（始终注册），登录前面板即有数据源

### 4.4 配置面板 UI

- 不再判断 `ScriptService` 注册，改为探测 server 可达：面板构建时按地址取值规则（§3）调 `/test`；可达 → `getScriptList` 拉脚本名渲染；不可达 → 显示「启动 server 后可配置自动启动脚本」提示 + 手动刷新按钮
- **登录与否行为统一**：面板数据源统一为 HTTP `getScriptList`（不再用响应式 `scriptModelMap`）。语义变化：登录后在主界面新增/删除/重命名脚本，面板需手动刷新（或重新展开）才会更新候选列表；勾选状态与延时值仍实时响应
- 每个脚本一行：勾选框 + 脚本名 + 「延时(秒)」数字输入框（未勾选时禁用，仅接受 0–86400 整数），修改即持久化
- i18n：新增未连接提示、延时标签、刷新等 key；原「登录后可配置」文案废弃

## 5. 错误处理

- `--autostart` 但 rootPathServer 无效（且后端不可达）：跳过整条流程，日志 + snackbar，退回正常手动使用
- server 拉起失败 / 轮询超时（5 分钟）：置 `failed`，提示失败，不影响手动操作
- **T0 之后、延时到点之前 server 不可用**（进程挂掉 / 用户在设置页 killServer / 用户在 Server 页手动 Run 重启）：
  - killServer 会注销 `ScriptService`，AutoBootService 监听到该注销即取消全部未触发 Timer（自动流程一次性，不重新调度）
  - Timer 到点时 `startScript` 失败：记日志 + snackbar 提示该脚本启动失败，跳过不重试
  - 用户手动 Run 重启 server 不重置 T0、不重新调度
- 延时 Timer 统一由 `AutoBootService` 持有，`onClose` 时全部取消
- 延时到点脚本已运行 → 跳过（沿用现有过滤）；脚本已不在 `scriptModelMap`（后端侧删除）→ 跳过并记日志
- 面板探测 `/test` 失败不弹网络错误 snackbar（静默显示未连接提示）
- 已知限制：OASX 无单实例保护，开机自启实例运行期间用户再手动打开第二个 OASX 实例的行为不在本设计范围（第二实例无 `--autostart`，不会重复调度）

## 6. 验收标准

1. 勾选「开机自启」后注册项带 `--autostart` 参数；重启系统 → OASX 自动打开 → server 自动拉起 → 后端就绪后自动进入主界面 → 各勾选脚本按配置延时（相对就绪时刻）依次启动。
2. 每个脚本可在 Server 页面板单独设置延时秒数并持久化；旧格式存储数据自动迁移且勾选状态不丢。
3. 手动双击打开 OASX（无 `--autostart`）：不自动拉 server、不自动启动脚本；存了地址仍自动登录进主界面（现状保留），但登录后脚本不再自动启动。
4. server 可达且未登录时，Server 页可直接看到脚本列表并配置自启与延时；server 不可达时显示提示；已登录时面板同样经 `getScriptList` 取列表，配置行为一致。
5. server 已在运行时走开机自启流程：跳过拉起，就绪即调度，行为一致。
6. 轮询超时 / rootPath 无效时有明确提示，OASX 其余功能不受影响。
7. 升级前注册的旧开机自启项（无 `--autostart` 参数）拉起 OASX：行为等同手动打开，不触发自动流程；重新关开一次「开机自启」开关后恢复全自动。

## 7. 测试

- 单测：存储迁移（raw List 直存 / JSON 字符串 × 字符串元素 / 对象元素、脏数据）、剩余延时补偿纯函数 `max(0, delay-(now-T0))`、触发条件判定（`--autostart`/桌面/列表非空）、调度跳过已运行与已删除脚本
- Widget 测试：面板「不可达提示」「可达列表 + 延时输入」两种状态；更新现有 `auto_start_settings` 测试
- 更新现有 `ScriptService` 自启相关测试为新语义（onInit 不再自动启动）
- 端到端按第 6 节手动验证（命令行加 `--autostart` 模拟开机自启）

## 8. 实施流程约束

实施计划须经 plan-reviewer 审查、代码须经 code-reviewer 审查后方可正式落地（用户要求，已建 5 分钟循环任务跟踪审查验收）。
