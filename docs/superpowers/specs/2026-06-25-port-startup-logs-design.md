---
comet_change: port-startup-logs
role: technical-design
canonical_spec: openspec
---

# port-startup-logs 技术设计

## 概述与范围

把来源项目（`C:\Users\lu\Desktop\yys\OnmyojiAutoScript-easy-install\OASX`）的两项启动能力**精简移植**到当前项目：

1. 桌面开机自启（系统登录时启动 OASX）
2. 自动启动脚本列表（应用启动后自动运行选中的脚本）

**精简移植策略**：只移植行为本身，**不引入** 来源项目的附属机制（`ProgressSnackbarController`、`TimeoutUtils`、`part` 文件拆分等）。`autoRunScript` 直接内联进 `script_service.dart`，反馈用现成的 `Get.snackbar`。

canonical spec 为 OpenSpec delta：`openspec/changes/port-startup-logs/specs/startup-auto-run/spec.md`。本设计不重复需求，只描述实现方案。

## 当前项目集成锚点（已核对）

| 锚点 | 位置 | 现状 | 本次改动 |
| --- | --- | --- | --- |
| 服务初始化 | `lib/main.dart:74` `initService()` | 注册 Locale/Theme/Window，lazyPut WebSocket | 新增注册 `AutoStartService`（桌面守卫，permanent） |
| 脚本服务注册 | `lib/views/layout/binding.dart:12` `LayoutBinding` | `Get.putAsync(() => ScriptService(), permanent: true)` | 保持不变（autoRun 在 ScriptService 内部触发） |
| 脚本服务 | `lib/service/script_service.dart` | `_storage`(GetStorage，当前 `unused_field`)、`scriptModelMap`、`onInit` 连接脚本 | 新增 `autoScriptList`、持久化、`isRunning`、`updateAutoScript`、`autoRunScript`，扩展 `onInit` |
| 后端就绪检查 | `lib/api/api_client.dart:92` `testAddress()` | 返回 `bool`，登录流程已用（`login_controller.dart:35`） | 复用做 autoRun 前的就绪轮询 |
| 删除脚本 | `lib/controller/ctrl_nav.dart:107` `deleteConfig` → `deleteScriptModel(name)` | 删除本地 model | 同步移除 autoScriptList |
| 重命名脚本 | `lib/controller/ctrl_nav.dart:139` `renameConfig` → `deleteScriptModel(old)` + `addScriptModel(new)` | 删旧加新 | 迁移 autoScriptList 旧名→新名 |
| 设置页 | `lib/views/settings/settings_view.dart` | `SettingsView` 用私有小 widget 组合 Column（`styled_widget` + `Obx`） | 新增「开机自启开关」+「自动启动脚本多选」私有 widget，桌面守卫 |
| 平台守卫 | `lib/utils/platform_utils.dart` `PlatformUtils.isDesktop` | 已有 | UI 与自启服务的桌面守卫 |
| i18n | `lib/config/translation/i18n_content.dart` `class I18n` | `static const String key = '...'`，用 `I18n.key.tr` | 新增自启/自动启动相关键 |

> 已核对：`AutoStartService`、`autoScriptList`、`isRunning` 在当前 `lib/` 源码中**均不存在**，无半成品实现，干净移植。

## 架构设计

### 1. AutoStartService（开机自启）

- 新建 `lib/service/auto_start_service.dart`，`extends GetxService`，移植来源项目实现。
- 在 `main.dart initService()` 中按平台守卫注册：仅 `PlatformUtils.isDesktop` 时 `Get.putAsync(() => AutoStartService(), permanent: true)`；非桌面不注册（no-op）。
- 职责：读取/写入系统自启注册项，暴露响应式 `enabled` 状态供设置页 `Obx` 绑定。
- 平台实现分支（来源项目已验证）：
  - Windows：`schtasks` 创建计划任务 + `Start-Process -Verb RunAs` 提权；任务名 `_windowsTaskName = 'OASX'`。
  - macOS：LaunchAgent plist。
  - Linux：autostart desktop file。
- 启动时 `refresh`：读取系统真实注册项，回写可见状态（覆盖 spec「Refresh launch state」）。
- 使用运行时可执行文件路径（避免打包/开发模式路径差异）。

### 2. ScriptService 扩展（自动启动脚本）

在 `lib/service/script_service.dart` 内新增（复用已声明但未用的 `_storage`）：

- `final autoScriptList = <String>[].obs;` — 自动启动脚本名列表（响应式，供多选 UI 绑定）。
- 持久化键：`'auto_script_list'`（GetStorage）。构造/初始化时 `restore`，每次增删后 `write`。
- `bool isRunning(String name)` — 基于 `scriptModelMap[name]?.state` 判断运行态（运行态枚举值在 build 阶段对照 `lib/model/script_model.dart` 的 `ScriptState` 确认）。
- `void updateAutoScript(String name, bool selected)` — 增/删并持久化；保持稳定顺序（按现有 `scriptModelMap.keys` 顺序或插入顺序）。
- `Future<void> autoRunScript()` — 启动时自动运行（见下方流程）。

多选列表数据源：`scriptModelMap.keys`（仅真实脚本，不含 `'Home'`），**不用** `navNameList`（含 `'Home'` 等导航项）。

### 3. 设置页 UI

在 `settings_view.dart` 的 Column 中新增两个私有 widget，整体用 `PlatformUtils.isDesktop` 守卫（非桌面不渲染）：

- `_AutoStartWidget`：`Obx` 绑定 `AutoStartService.enabled`，开关切换调用 service 更新；更新失败展示反馈（snackbar/提示）。
- `_AutoRunScriptsWidget`：`Obx` 遍历 `ScriptService.scriptModelMap.keys` 渲染多选项，勾选状态绑定 `autoScriptList`，切换调用 `updateAutoScript`。

沿用现有风格：私有 `StatelessWidget` + `styled_widget`（`.paddingAll` / `.toColumn`）+ `Obx`。

## 关键流程

### 启动时自动运行（onInit 就绪检查 + autoRunScript）

扩展 `ScriptService.onInit`：现有「拉取脚本列表 → 逐个 connectScript」之后，新增后端就绪检查再触发自动运行。

```dart
@override
Future<void> onInit() async {
  final scriptList = await ApiClient().getScriptList();
  if (scriptList.isNotEmpty) {
    await Future.wait(scriptList.map((name) => connectScript(name)));
  }
  super.onInit();
  await _waitBackendReady();   // testAddress 轮询重试（3~5 次 × 500ms）
  await autoRunScript();       // 可达才跑；不可达跳过不报错
}

Future<void> autoRunScript() async {
  if (autoScriptList.isEmpty) return;
  // 已在运行的脚本视为成功，跳过
  final pending = autoScriptList.where((n) => !isRunning(n)).toList();
  await Future.wait(pending.map((n) => startScript(n)));
  // 延迟采样运行状态，成功则提示（fire-and-forget，不阻塞启动）
  Future.delayed(const Duration(seconds: 4), () {
    final ok = autoScriptList.where(isRunning).toList();
    if (ok.isNotEmpty) {
      Get.snackbar(I18n.auto_run_script.tr, '$ok ${I18n.start_success.tr}');
    }
  });
}
```

设计要点：
- **触发时机**：来源项目真实触发点是「确认连上后端后」（`dashboard_controller_startup.dart:127`）。当前项目无对应 controller，改在 `onInit` 末尾用 `testAddress` 轮询就绪检查**近似达成**同等语义。
- **就绪检查**：`testAddress()` 轮询 3~5 次、每次间隔 500ms；任一次可达即继续；全部不可达则跳过 autoRun 且**不报错**。
- **跳过已运行**：`isRunning(n)` 过滤，覆盖 spec「Skip already running script」。
- **失败不阻塞**：`Future.wait` 并发 `startScript`；启动是异步过程，调用返回 ≠ 运行成功，故用延迟 4s 采样 `isRunning` 判断成功并提示，覆盖 spec「Continue after failed script start」（超时/失败的脚本不阻塞其他、不改后端协议）。
- **重跑语义**：`ScriptService` 为 permanent + onInit 单次；`killServer` 后 `Get.delete<ScriptService>` 再登录会重建并重跑 `onInit` → 重跑 `autoRunScript`，语义合理。

### 数据完整性：删除 / 重命名同步（重点设计决策）

`renameConfig`（`ctrl_nav.dart:139`）内部实现为 `deleteScriptModel(old)` + `addScriptModel(new)`。若把 autoScriptList 的移除逻辑直接耦合进 `deleteScriptModel`，**重命名会顺带抹掉自启标记**。处理策略：

1. **真实删除**（`deleteConfig` → `deleteScriptModel`）：`deleteScriptModel(name)` 同步 `autoScriptList.removeWhere(name)` + 持久化。
2. **重命名**（`renameConfig`）：因其内部复用 `deleteScriptModel(old)` 会触发上面的移除，必须在 `renameConfig` 中**先捕获** `old` 是否在 `autoScriptList`，重命名完成（addScriptModel(new) 之后）**再恢复** `new` 的勾选并持久化，实现旧名→新名迁移。
3. **风险提示**：删除与重命名共用 `deleteScriptModel`，build 阶段必须用测试验证「重命名后自启标记保留」与「删除后自启标记移除」两条路径都正确。

## 数据模型与持久化

| 数据 | 类型 | 存储 | 生命周期 |
| --- | --- | --- | --- |
| 自动启动脚本列表 | `RxList<String>` | GetStorage 键 `'auto_script_list'` | 初始化 restore，增删即写 |
| 开机自启开关 | `RxBool`（AutoStartService） | 系统注册项（计划任务/LaunchAgent/desktop file） | 启动 refresh 真实状态 |

无后端字段新增、无 WebSocket 协议改动（spec Non-Goal 保持）。

## 平台差异与 no-op

- 非桌面平台：不注册 `AutoStartService`、设置页不渲染相关 widget——整体 no-op，无副作用。
- 自动启动脚本能力本身与平台无关（仅依赖现有脚本启动入口），各平台一致可用。

## 测试策略

- **单元测试**：`autoScriptList` 持久化读写、`updateAutoScript` 增删与顺序、`isRunning` 状态判断、`testAddress` 就绪重试逻辑、删除/重命名时 autoScriptList 同步与迁移。
- **Widget 测试**：设置页开机自启开关 + 多选列表渲染（桌面）、勾选触发持久化、非桌面不渲染守卫、`autoRunScript` 跳过已运行脚本。
- **静态/回归**：`flutter analyze` 通过，现有脚本启动相关测试不回归。
- **手动测试（必做，自动化覆盖不到）**：
  1. **MSIX 安装版**下 `schtasks` 提权 + 开关自启（当前项目 `store: true` 走 MSIX/Microsoft Store，沙箱行为可能与便携版不同）。
  2. 桌面平台开关自启后系统真实注册项的创建/删除与状态同步、失败提示。
  3. 后端慢启动场景：就绪检查重试期间自动运行脚本是否正确触发。
  4. 删除/重命名脚本后 `autoScriptList` 同步正确（重命名保留标记、删除移除标记）。

## 风险与缓解

| 风险 | 缓解 |
| --- | --- |
| MSIX 沙箱下 `schtasks` + `Start-Process -Verb RunAs` 行为与便携版不同 | 必须在 MSIX 安装包上手动验证，作为发布前门槛 |
| `_windowsTaskName` 硬编码 `'OASX'` 可能与同名任务冲突 | 直接移植可接受，记录已知项；冲突时由 refresh 真实状态暴露 |
| Windows 计划任务触发 UAC / 权限失败 | 更新后刷新真实系统状态，失败时向用户提示 |
| 启动时列表中脚本已不存在 | 跳过无效脚本，不阻塞其他脚本（autoRun 仅对 `scriptModelMap` 中存在的运行/启动） |
| `autoRunScript` 并发 `start` 对后端压力 | 用户通常勾 1~2 个，低风险；保持 `Future.wait` 并发即可 |
| 自动启动脚本较多导致启动反馈时间长 | 延迟采样不阻塞启动；必要时 build 阶段可加当前脚本名进度提示 |

## 与 spec 验收场景 / tasks 的映射

| spec 验收场景 | 实现承载 | tasks |
| --- | --- | --- |
| Enable / Disable launch at startup | `AutoStartService` 写系统注册项 + 持久化 | 1.2、1.3 |
| Refresh launch state | 启动时 `AutoStartService.refresh` 回写可见状态 | 1.2 |
| Add / Remove script to automatic run list | `updateAutoScript` + GetStorage 持久化 | 2.2 |
| Restore automatic run list | ScriptService 初始化时 restore | 2.1 |
| Start configured scripts | `autoRunScript` 复用 `startScript` + 进度反馈 | 2.3 |
| Skip already running script | `isRunning` 过滤 | 2.3 |
| Continue after failed script start | `Future.wait` 并发 + 延迟采样，不改协议 | 2.3 |

## Spec Patch

**无。** 现有 `startup-auto-run` delta spec 的验收场景已完整覆盖本设计。`onInit` 触发时机的就绪检查（`testAddress` 轮询）属实现决策，不改变 spec 验收场景，无需回写 delta spec。
