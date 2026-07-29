---
comet_change: oasx-autostart-settings-ui
role: technical-design
supersedes: 2026-06-25-port-startup-logs-design.md
status: final(已经 2 名 plan-reviewer 对抗审查并按意见修订)
---

# OASX 自启动设置 —— Windows 实现审查与 UI 迁移技术设计

## 一、实现现状审查(Windows 端)

对照原设计文档 `2026-06-25-port-startup-logs-design.md`,逐项核对当前代码,**结论:功能已在 Windows 端正确实现**,部分实现优于原设计。

| 原设计项 | 实现位置 | 审查结论 |
| --- | --- | --- |
| `AutoStartService` 注册(桌面守卫,permanent) | `lib/main.dart:85-88` | ✅ 符合,`PlatformUtils.isDesktop` 守卫 |
| Windows 开机自启(schtasks + 提权) | `lib/service/auto_start_service.dart:73-166` | ✅ 优于设计:XML 定义计划任务(LogonTrigger + InteractiveToken + LeastPrivilege),PowerShell `Start-Process -Verb RunAs` 提权,任务名 `OASX`,设置后二次查询校验 |
| 启动时 `refresh` 回写真实系统状态 | `auto_start_service.dart:36-41` | ✅ `schtasks /Query` 读取真实状态并回写持久化 |
| 更新失败提示 | `auto_start_service.dart:43-57` | ✅ 失败或状态不一致时 snackbar 提示;`isApplying` 防并发写 |
| `autoScriptList` 持久化(GetStorage) | `lib/service/script_service.dart:20,30-52` | ✅ 优于设计:JSON 持久化并兼容历史 List 直存格式 |
| `isRunning` 运行态判断 | `script_service.dart:55-58` | ✅ 基于 `ScriptState.running` |
| `updateAutoScript` 增删持久化 | `script_service.dart:61-69` | ✅ 用 `sort()` 稳定排序(与原设计"插入顺序"不同,可接受的已知差异) |
| 就绪检查 + `autoRunScript` | `script_service.dart:72-112` | ✅ 合并为 `_waitBackendReadyAndAutoRun`(5×500ms 轮询,不可达跳过不报错);延迟采样改用 `Timer` 字段并在 `onClose` 取消,优于原设计的 `Future.delayed` |
| 删除脚本同步移除自启标记 | `script_service.dart:204-212` | ✅ |
| 重命名脚本迁移自启标记 | `lib/controller/ctrl_nav.dart:139-170` | ✅ 显式原子迁移(先捕获旧名标记,重命名后移旧加新) |
| 设置页 UI(开关 + 多选) | `lib/views/settings/settings_view.dart:25-27,113-163` | ✅ 已实现 —— **本次迁移对象** |
| i18n 键 | `i18n_content.dart:235-239` + cn/us 译文 | ✅ |
| 单元测试 | `test/service/script_service_auto_test.dart` | ✅ 覆盖增删排序持久化、历史格式恢复、删除同步 |

原设计中的手动测试项(MSIX 沙箱下 schtasks 提权、UAC 场景)仍属发布前人工验证范围,不在本次变更内。

## 二、本次变更范围:UI 迁移到 OASX/Server 页

### 需求

1. 设置页(`/settings`)移除「开机自启开关」与「自动启动脚本多选」两个 widget。
2. Server 页(`/server`)新增「**OASX自启动设置**」区块,位置在「服务启动配置」(`I18n.setup_deploy` 的 ExpansionTileItem)与「服务启动日志」(`LogWidget`,`I18n.setup_log`)之间。
3. 布局采用与 Server 页现有区块一致的格式。
4. 服务/持久化/自动运行逻辑**零改动**,仅移动 UI 绑定层。

### 集成锚点(已核对)

| 锚点 | 位置 | 现状 | 本次改动 |
| --- | --- | --- | --- |
| Server 页主体 | `lib/views/server/server_view.dart:33-56` `_body()` | `ExpansionTileGroup[path, deploy]` + `LogWidget` | ExpansionTileGroup 末尾新增第三个 `ExpansionTileItem`(即位于 deploy 与 LogWidget 之间) |
| Server 路由 | `lib/views/routes.dart:28-34` | 仅注册 `ServerController`,**无 ScriptService** | 不改路由;UI 层做注册守卫 |
| Server 入口 | `lib/views/login/login_view.dart:129`(登录前可进) | — | 决定了 ScriptService 可能未注册 |
| 设置页 | `lib/views/settings/settings_view.dart` | 含 `_AutoStartWidget`、`_AutoRunScriptsWidget` | 移除两个 widget、两处 `if (PlatformUtils.isDesktop)` 引用及因此闲置的 import |
| i18n | `lib/config/translation/i18n_content.dart` + `i18n_cn.dart` + `i18n_us.dart` | 已有 `launchAtStartup` / `autoRunScriptConfig` 等键 | 新增 2 键(见下) |

### 关键设计决策

**1. ScriptService 生命周期守卫(本次最重要的正确性问题)**

`/server` 从登录页进入时 `LayoutBinding` 尚未执行,`ScriptService` 未注册,直接 `Get.find<ScriptService>()` 会抛异常。处理:

- 自动启动脚本区域先判断 `Get.isRegistered<ScriptService>()`(三态,已核对):
  - **已注册且在线**(登录后 service 为 permanent;登出 `_exitButton` 仅 `offAllNamed('/login')` 不删 service,故登出后再进 `/server` 同属此态,列表数据仍有效、改动照常持久化 —— 属可接受行为):正常渲染多选列表;
  - **未注册**(应用启动后未登录过;或 `killServer` 后 —— `settings.dart:43` 会 `Get.delete<ScriptService>(force: true)` 并回登录页):渲染提示文案「登录后可配置自动启动脚本」(新 i18n 键),不渲染列表。

> **已知可达性约束(需求方决策,如实记录)**:`/server` 的唯一导航入口是登录页 FAB(`login_view.dart:25,129`,且仅 `PlatformUtils.isWindows` 显示);登录成功 `offAllNamed('/main')` 后无路径再进 `/server`。因此正常流程下脚本多选多数时候显示登录提示,完整列表需经「登录→登出→进 /server」触达;macOS/Linux 桌面将失去自启 UI 入口。本次按用户指定位置执行迁移,入口问题记入风险表,由需求方决定是否后续补 `/main` 侧入口。

**2. 桌面守卫**

`AutoStartService` 仅在桌面注册(`main.dart:86`)。整个「OASX自启动设置」tile 用 `PlatformUtils.isDesktop` 守卫,非桌面不渲染 —— 与原设置页守卫语义一致。已核对 expansion_tile_group 1.3.0:`ExpansionTileGroup.children` 类型为 `List<ExpansionTileItem>`,children 列表字面量内用 collection-if(`if (PlatformUtils.isDesktop) autoStart(context)`)条件插入可行。

**2.1 Obx 结构约束(GetX 陷阱规避)**

GetX 规定 Obx builder 内必须读取至少一个 Rx 变量,否则抛 improper-use 异常。因此:
- `Get.isRegistered<ScriptService>()` 判断放在 **Obx 之外**(普通 build 逻辑);「登录提示文案」分支为纯静态 Text,不包 Obx;
- 开机自启开关单独一个 Obx(读 `enableLaunchAtStartup` + `isApplying`);
- 脚本多选列表单独一个 Obx(读 `scriptModelMap` + `autoScriptList`),仅在已注册分支构建。

注册状态在页面停留期间不会变化(登录/killServer 均伴随路由跳转,重进 `/server` 必然重新 build),build 时一次性判断即可,无需响应式。

**3. 布局格式(与 Server 页风格统一)**

新增 `ExpansionTileItem`,样式复制 `path` / `deploy` 的既有参数(`initiallyExpanded: false`、无上下边框、`secondaryContainer.withOpacity(0.24)` 折叠背景、圆角 10),title 为 `I18n.oasxAutoStartSettings.tr`(titleMedium)。children 内部结构:

```
SwitchListTile  开机自启(I18n.launchAtStartup)
  ├─ value: AutoStartService.enableLaunchAtStartup(Obx)
  └─ isApplying 时 onChanged 置 null(防并发写系统注册项)
Divider
Text  I18n.autoRunScriptConfig(小节标题)
[ScriptService 已注册]
  CheckboxListTile × N(scriptModelMap.keys,勾选绑定 autoScriptList,
                        切换调用 updateAutoScript —— 逻辑同原设置页)
[未注册]
  Text  I18n.autoRunScriptLoginHint(登录提示)
```

开关从原设置页的 `Text + Switch` 纵向布局改为 `SwitchListTile`,与 `CheckboxListTile` 列表项风格对齐,更适合折叠面板内的行式布局。审查补充(已核对 expansion_tile_group 内部实现):tile 默认 `Column(crossAxisAlignment: center)` 会使裸 `Text` 居中,故新 tile 显式设置 `expandedCrossAxisAlignment: CrossAxisAlignment.start` 与 `childrenPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4)`,保证小节标题/提示文案左对齐。children 的 collection-if 条件(`PlatformUtils.isDesktop`)是构建期稳定值,满足组内部 `late final` key 列表对 children 长度不变的前提;**不得**改成 Obx 内动态增删 children。

**3.1 文件组织**

内容区抽成**公开** widget `AutoStartSettingsContent`,放独立文件 `lib/views/server/auto_start_settings.dart`,由 `server_view.dart` import(而非 part)。理由:`server_view.dart` 是 `library server;` 且带 2 个 part(含 shell 逻辑),独立文件缩小测试 import 面,公开 widget 不寄生在页面 library 里。`server_view.dart` 内仅保留构建 `ExpansionTileItem` 外壳的方法(需要 BuildContext 取主题色)。

**4. 组内互斥展开**

`ExpansionTileGroup` 的 `toggleType: expandOnlyCurrent` 使三个 tile 互斥展开,新 tile 加入后行为一致,可接受,不改组配置。

### i18n 新键

| 键 | zh-CN | en-US |
| --- | --- | --- |
| `oasxAutoStartSettings` | OASX自启动设置 | OASX Autostart Settings |
| `autoRunScriptLoginHint` | 登录后可配置自动启动脚本 | Log in to configure auto-run scripts |

### 文件变更清单

1. `lib/config/translation/i18n_content.dart` — 新增 2 个键常量(常量值即英文文案)。
2. `lib/config/translation/i18n_cn.dart` / `i18n_us.dart` — 新增 2 条译文,分别落入 `_cn_ui` / `_us_ui` 段(us 缺键时框架按键值兜底,但为一致性显式补齐;cn 条目必须,否则中文界面显示英文)。
3. `lib/views/server/auto_start_settings.dart`(新增)— 公开内容 widget `AutoStartSettingsContent`。
4. `lib/views/server/server_view.dart` — import 新文件;`_body()` 的 ExpansionTileGroup 末尾 collection-if 插入 `autoStart(context)`(桌面守卫);新增构建 ExpansionTileItem 的方法。
5. `lib/views/settings/settings_view.dart` — 移除 `_AutoStartWidget`、`_AutoRunScriptsWidget` 及 Column 中的两行引用;移除因此不再使用的 import(`auto_start_service.dart`、`script_service.dart`、`platform_utils.dart`)。
6. `test/views/server/auto_start_settings_test.dart`(新增)— 见测试策略。

服务层(`auto_start_service.dart`、`script_service.dart`)、控制器(`ctrl_nav.dart`)、持久化键**均不改动**。已知备注:`main.dart:87` 的 `Get.putAsync(AutoStartService)` 未被 await,理论存在极短未注册窗口,与原设置页暴露一致,按现状接受。

### 测试策略

- **Widget 测试(新增,`test/views/server/auto_start_settings_test.dart`)**:直接 pump `AutoStartSettingsContent`,用 `MaterialApp(home: Scaffold(...))` 包裹(ListTile 系需要 Material/Directionality 祖先;项目未用 flutter_screenutil,无额外顾虑)。断言文案用 `I18n` 常量值匹配(`.tr` 未加载翻译时回退键值,而键值即英文文案)。用例:
  1. `ScriptService` 未注册 → 渲染登录提示文案,不渲染 CheckboxListTile;
  2. 注册 fake ScriptService(注入假脚本)→ 渲染多选列表,勾选触发 `updateAutoScript` 且持久化;
  3. `isApplying=true` → 开机自启开关禁用(onChanged 为 null)。
- **测试替身(关键,两个 service 都要 fake)**:
  - `AutoStartService.onInit` 会执行 `PackageInfo.fromPlatform` 并在桌面 `refresh()`(真实运行 `schtasks /Query`)→ 用 fake 子类覆写 `onInit` 为 no-op(响应式字段继承基类直接可用)。三个用例的公共 setUp 都注册该 fake(内容 widget 无条件渲染开关)。测试中不 tap 开关的启用态(会真实执行 schtasks),用例 3 只断言禁用。
  - `ScriptService.onInit` 会发真实 HTTP(`getScriptList`)并跑 5×500ms 轮询,`Get.put` 必触发 onInit 导致 pending Timer 使 `testWidgets` 必败 → 同样用 fake 子类覆写 `onInit`(与 `onClose`)为 no-op;沿用现有测试先注册 `WebSocketService` 的做法(`ScriptService` 字段初始化即 `Get.find<WebSocketService>`),假脚本用 `addScriptModel` 手动灌入。
- **GetX/GetStorage 初始化**:沿用 `test/service/script_service_auto_test.dart` 的既有模式(`Get.testMode = true` + mock path_provider MethodChannel + `GetStorage.init()`);tearDown 中 `Get.delete(force: true)` 清理注册。
- **回归**:`flutter analyze` 无新告警;`test/service/script_service_auto_test.dart` 等现有测试通过。
- **手动验证(桌面 Windows)**:Server 页展开「OASX自启动设置」,开关与多选行为与原设置页一致;设置页不再出现相关项。

### 风险与缓解

| 风险 | 缓解 |
| --- | --- |
| **可达性回归(HIGH,需求方需知晓)**:`/server` 唯一入口为登录页 FAB(仅 Windows 显示),登录后无路径再进;正常流程中脚本多选多数呈现为登录提示,完整列表需「登录→登出→进 /server」;macOS/Linux 失去自启 UI 入口 | 按用户指定位置执行;如实记录,建议后续在 `/main` 侧补 Server 页入口(独立需求,本次不做) |
| 登录前进入 Server 页时 ScriptService 未注册导致崩溃 | `Get.isRegistered` 守卫 + 登录提示文案(核心决策 1) |
| 已注册但 `scriptModelMap` 为空时区块只剩小节标题,观感略空 | 已知取舍,保持最小改动,不加空态文案 |
| 测试中 ServerController / 真实 service 依赖导致测试失败 | 内容区抽独立 widget + 两个 service 均用 no-op onInit 的 fake 子类 |
| 非桌面平台进入 Server 页 | 整个 tile 桌面守卫,不渲染,无副作用 |
| 用户习惯迁移(原设置页找不到入口) | 属产品决策,本次按需求执行;i18n 名称「OASX自启动设置」语义清晰 |
