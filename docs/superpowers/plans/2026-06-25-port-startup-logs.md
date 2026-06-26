---
archived-with: 2026-06-26-port-startup-logs
status: final
---
# port-startup-logs 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: 用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务执行。步骤用 checkbox（`- [ ]`）跟踪。

**Goal:** 把来源项目的「桌面开机自启」和「自动启动脚本列表」两项能力精简移植到当前项目，复用现有脚本启动入口，不改后端协议。

**Architecture:** 新建 `AutoStartService`（GetxService，桌面平台分支）管理开机自启系统注册项；扩展 `ScriptService` 承载 `autoScriptList` 持久化、就绪检查与 `autoRunScript`；设置页新增两个桌面守卫的私有 widget。不引入来源项目的 `ProgressSnackbarController`/`TimeoutUtils`/part 文件，反馈用现成的 `Get.snackbar`。

**Tech Stack:** Flutter + GetX（`GetxService`/`Obx`/`Get.snackbar`）、GetStorage（本地持久化）、`process_run`/`dart:io` Process（系统命令）、`fake_async`（测试时间控制）。

## Global Constraints

- **不改后端**：脚本启动仍走现有 `ScriptService.startScript` → `wsService.send('start')`；不新增后端字段、不改 WebSocket 协议。
- **桌面守卫**：开机自启仅在 `PlatformUtils.isDesktop`（Windows/macOS/Linux）生效，非桌面 no-op、设置页不渲染相关控件。
- **复用已声明资源**：`ScriptService._storage`（当前 `// ignore: unused_field`）直接用于 `autoScriptList` 持久化。
- **数据源**：自动启动脚本多选列表用 `ScriptService.scriptModelMap.keys`（真实脚本，不含 `'Home'`），不用 `navNameList`。
- **i18n key 命名**：camelCase，与项目现有风格一致（如 `launchAtStartup`、`autoRunScript`、`startSuccess`）。
- **中文注释**：所有新增代码写中文注释（项目约定）。
- **base-ref**：`81c36241ccfe9107a79a2c0daa50bb1a3713423a`（验证阶段跨提交统计改动规模用）。

## 关键设计决策（执行时务必遵守）

1. **autoRunScript 触发时机**：在 `ScriptService.onInit` 末尾，先 `_waitBackendReady()`（`testAddress` 轮询 5 次 × 500ms），可达才 `autoRunScript()`，不可达跳过不报错。
2. **autoRunScript 行为**：fire-and-forget —— 并发 `startScript` 已过滤「跳过已运行」，再用 `Future.delayed(4s)` 采样 `isRunning`，成功才 `Get.snackbar`。**不阻塞启动**。
3. **数据完整性陷阱**：`renameConfig`（`lib/controller/ctrl_nav.dart`）内部是 `deleteScriptModel(old)` + `addScriptModel(new)`。若「移除自启标记」耦合在 `deleteScriptModel` 里，重命名会误删标记。故：`deleteScriptModel` 负责移除（覆盖真实删除场景）；`renameConfig` 必须在删旧前捕获旧名是否在列表，加新后迁移到新名。
4. **MSIX 风险**：当前项目 `store: true` 走 MSIX。Windows 自启用 `schtasks` + `Start-Process -Verb RunAs`，在 MSIX 沙箱下行为可能与便携版不同 —— **单元测试覆盖不了，必须手动验证**（Task 8）。

---

## File Structure

| 文件 | 责任 | 动作 |
| --- | --- | --- |
| `lib/model/const/storage_key.dart` | 本地存储键枚举 | 新增 `autoScriptList`、`launchAtStartup` |
| `lib/config/translation/i18n_content.dart` | i18n key 声明 | 新增 6 个 key |
| `lib/config/translation/i18n_cn.dart` | 中文译文 | `_cn_ui` 新增 6 条 |
| `lib/config/translation/i18n_us.dart` | 英文译文 | `_us_ui` 新增 6 条 |
| `lib/service/auto_start_service.dart` | 开机自启系统注册项管理 | **新建** |
| `lib/main.dart` | 应用初始化 | `initService()` 注册 AutoStartService（桌面守卫） |
| `lib/service/script_service.dart` | 脚本服务 | 扩展 autoScriptList/持久化/isRunning/updateAutoScript/autoRunScript/onInit |
| `lib/controller/ctrl_nav.dart` | 导航控制器 | `deleteConfig`/`renameConfig` 同步 autoScriptList |
| `lib/views/settings/settings_view.dart` | 设置页 | 新增 `_AutoStartWidget`、`_AutoRunScriptsWidget`（桌面守卫） |
| `test/service/script_service_auto_test.dart` | 单元测试 | **新建**（持久化/增删/isRunning/就绪检查） |
| `test/views/settings/settings_view_test.dart` | Widget 测试 | **新建**（桌面守卫渲染） |

---

### Task 1: 新增存储键枚举

**Files:**
- Modify: `lib/model/const/storage_key.dart`

**Interfaces:**
- Produces: `StorageKey.autoScriptList`、`StorageKey.launchAtStartup`（供后续 task 通过 `StorageKey.xxx.name` 读写 GetStorage）

- [x] **Step 1: 扩展枚举**

把 `lib/model/const/storage_key.dart` 的枚举改为：

```dart
enum StorageKey {
  dark,
  language,
  username,
  password,
  address,
  // 自动启动脚本列表，存储脚本名 JSON 数组
  autoScriptList,
  // 开机自启开关缓存（真实状态仍以系统注册项为准）
  launchAtStartup,
}
```

- [x] **Step 2: 验证编译**

Run: `flutter analyze lib/model/const/storage_key.dart`
Expected: `No issues found!`

- [x] **Step 3: Commit**

```bash
git add lib/model/const/storage_key.dart
git commit -m "feat: 新增 autoScriptList/launchAtStartup 存储键"
```

---

### Task 2: 新增 i18n 文案 key 与译文

**Files:**
- Modify: `lib/config/translation/i18n_content.dart`
- Modify: `lib/config/translation/i18n_cn.dart`
- Modify: `lib/config/translation/i18n_us.dart`

**Interfaces:**
- Produces: `I18n.launchAtStartup`、`I18n.launchAtStartupUpdateFailed`、`I18n.autoRunScript`、`I18n.autoRunScriptConfig`、`I18n.startSuccess`、`I18n.tip`（`tip` 已存在，复用）

> key 命名遵循项目 camelCase 风格。英文 base 值直接写在 `I18n.xxx = '...'`，中文/英文译文在 map 里覆盖。`tip`（'Tip'）已存在，不再重复声明。

- [x] **Step 1: 在 i18n_content.dart 声明 key**

在 `lib/config/translation/i18n_content.dart` 的 `class I18n { ... }` 内（`selectAll` 附近）新增：

```dart
  static const String selectAll = 'Select All';

  // 开机自启与自动启动脚本相关文案
  static const String launchAtStartup = 'Launch at Startup';
  static const String launchAtStartupUpdateFailed =
      'Failed to update launch at startup';
  static const String autoRunScript = 'Auto Run Script';
  static const String autoRunScriptConfig = 'Auto Run Script Config';
  static const String startSuccess = 'started successfully';
```

- [x] **Step 2: 在 i18n_cn.dart 加中文译文**

在 `_cn_ui` 末尾（`I18n.selectAll: '全选',` 之后、闭合 `};` 之前）新增：

```dart
  I18n.launchAtStartup: '开机自启',
  I18n.launchAtStartupUpdateFailed: '开机自启设置失败',
  I18n.autoRunScript: '自动启动脚本',
  I18n.autoRunScriptConfig: '自动启动脚本配置',
  I18n.startSuccess: '已启动',
```

- [x] **Step 3: 在 i18n_us.dart 加英文译文**

在 `_us_ui`（`lib/config/translation/i18n_us.dart:15`）末尾闭合 `};` 前新增：

```dart
  I18n.launchAtStartup: 'Launch at Startup',
  I18n.launchAtStartupUpdateFailed: 'Failed to update launch at startup',
  I18n.autoRunScript: 'Auto Run Script',
  I18n.autoRunScriptConfig: 'Auto Run Script Config',
  I18n.startSuccess: 'started successfully',
```

- [x] **Step 4: 验证编译**

Run: `flutter analyze lib/config/translation/`
Expected: `No issues found!`

- [x] **Step 5: Commit**

```bash
git add lib/config/translation/
git commit -m "feat: 新增开机自启/自动启动脚本 i18n 文案"
```

---

### Task 3: 移植 AutoStartService

**Files:**
- Create: `lib/service/auto_start_service.dart`

**Interfaces:**
- Produces: `AutoStartService`（`GetxService`），公开响应式 `enableLaunchAtStartup`（`RxBool`）、`isApplying`（`RxBool`）、`Future<void> refresh()`、`Future<void> updateLaunchAtStartupEnable(bool enabled)`。供 Task 4 注册、Task 9 设置页绑定。

> 来源项目（`C:\Users\lu\Desktop\yys\OnmyojiAutoScript-easy-install\OASX\lib\service\autostart_service.dart`）已验证此实现：Windows `schtasks` + `Start-Process -Verb RunAs` 提权、macOS LaunchAgent plist、Linux autostart desktop file，启动时 `refresh` 读真实系统状态回写。本 task 为**带 import 适配的 verbatim 移植**——只改 import 路径，不改逻辑。

- [x] **Step 1: 创建文件并移植**

把来源项目 `lib/service/autostart_service.dart` 全文复制到当前项目 `lib/service/auto_start_service.dart`，然后**仅修改文件头部的 import**：

```dart
import 'dart:convert';
import 'dart:io';

import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:oasx/model/const/storage_key.dart';
import 'package:oasx/config/translation/i18n_content.dart';
import 'package:oasx/utils/platform_utils.dart';
import 'package:package_info_plus/package_info_plus.dart';
```

（原文件的 `package:oasx/modules/common/models/storage_key.dart` → `package:oasx/model/const/storage_key.dart`；`package:oasx/translation/i18n_content.dart` → `package:oasx/config/translation/i18n_content.dart`。其余 300 行逻辑、`_windowsTaskName = 'OASX'`、XML/plist/desktop 模板、`refresh`/`updateLaunchAtStartupEnable` 全部保持不变。）

- [x] **Step 2: 验证编译**

Run: `flutter analyze lib/service/auto_start_service.dart`
Expected: `No issues found!`

- [x] **Step 3: Commit**

```bash
git add lib/service/auto_start_service.dart
git commit -m "feat: 移植 AutoStartService（桌面开机自启）"
```

---

### Task 4: 在 main.dart 注册 AutoStartService

**Files:**
- Modify: `lib/main.dart:74-85`（`initService()`）

**Interfaces:**
- Consumes: Task 3 的 `AutoStartService`、`PlatformUtils.isDesktop`
- Produces: 桌面平台启动时 `AutoStartService` 已注册为 permanent 服务，其 `onInit` 自动 `refresh` 真实系统状态

- [x] **Step 1: 加 import**

在 `lib/main.dart` 顶部 import 区（`window_service` 附近）新增：

```dart
import 'package:oasx/service/auto_start_service.dart';
```

- [x] **Step 2: 在 initService 注册（桌面守卫）**

把 `initService()`（`lib/main.dart:74`）改为：

```dart
Future<void> initService() async {
  await initLogger();
  await GetStorage.init();

  await Future.wait([
    Get.putAsync(() async => LocaleService()),
    Get.putAsync(() async => ThemeService()),
    Get.putAsync(() async => WindowService()),
  ]);

  // 桌面平台才注册开机自启服务，非桌面 no-op
  if (PlatformUtils.isDesktop) {
    Get.putAsync(() async => AutoStartService(), permanent: true);
  }

  Get.lazyPut(() => WebSocketService());
}
```

- [x] **Step 3: 验证编译**

Run: `flutter analyze lib/main.dart`
Expected: `No issues found!`

- [x] **Step 4: Commit**

```bash
git add lib/main.dart
git commit -m "feat: 桌面平台注册 AutoStartService"
```

---

### Task 5: ScriptService 扩展 — autoScriptList 持久化与 isRunning

**Files:**
- Modify: `lib/service/script_service.dart`

**Interfaces:**
- Produces: `RxList<String> autoScriptList`、`bool isRunning(String name)`、`void updateAutoScript(String name, bool selected)`、`void _loadAutoScriptListFromStorage()`、`void _persistAutoScriptList()`，以及扩展后的 `deleteScriptModel`（同步移除自启标记）
- Consumes: `StorageKey.autoScriptList`（Task 1）、`ScriptState.running`（来自 `lib/model/script_model.dart`）

> 来源项目把这部分拆成 `script_service_auto.dart`（part 文件）+ 引入 `ProgressSnackbarController`/`TimeoutUtils`。本变更按 design doc **精简移植**：内联进 `script_service.dart`，反馈用 `Get.snackbar`，**不引入** part 文件和附属类。

- [x] **Step 1: 加 import 并移除 unused 注释**

`lib/service/script_service.dart:1-8` 的 import 区改为：

```dart
import 'dart:convert';

import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:oasx/api/api_client.dart';
import 'package:oasx/config/translation/i18n_content.dart';
import 'package:oasx/model/const/storage_key.dart';
import 'package:oasx/model/script_model.dart';
import 'package:oasx/service/websocket_service.dart';
import 'package:oasx/views/overview/overview_view.dart';
```

- [x] **Step 2: 新增字段与持久化方法**

在 `class ScriptService extends GetxService {` 内（`scriptModelMap` 声明之后、`onInit` 之前）新增字段和方法：

```dart
  // 自动启动脚本列表（持久化脚本名，应用启动后自动运行）
  final autoScriptList = <String>[].obs;

  // 从本地存储恢复自动启动脚本列表，兼容历史 List 直存与 JSON 字符串两种格式
  void _loadAutoScriptListFromStorage() {
    final raw = _storage.read(StorageKey.autoScriptList.name);
    if (raw is List) {
      autoScriptList.value = raw.map((e) => e.toString()).toList();
      return;
    }
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          autoScriptList.value = decoded.map((e) => e.toString()).toList();
          return;
        }
      } catch (_) {}
    }
    autoScriptList.clear();
  }

  // 写入自动启动脚本列表（JSON 数组形式持久化）
  void _persistAutoScriptList() {
    _storage.write(
        StorageKey.autoScriptList.name, jsonEncode(autoScriptList.toList()));
  }

  // 判断脚本是否处于运行态，用于跳过已运行脚本与延迟采样成功判断
  bool isRunning(String name) {
    final model = scriptModelMap[name];
    return model != null && model.state.value == ScriptState.running;
  }

  // 增删自动启动脚本并持久化，保持列表稳定排序
  void updateAutoScript(String script, bool selected) {
    if (selected) {
      if (!autoScriptList.contains(script)) autoScriptList.add(script);
    } else {
      autoScriptList.remove(script);
    }
    autoScriptList.sort();
    _persistAutoScriptList();
  }
```

同时把原 `final _storage = GetStorage();` 上方的 `// ignore: unused_field` 注释删掉（该字段现在已被使用）：

```dart
  final _storage = GetStorage();
```

- [x] **Step 3: onInit 中 restore 列表**

把 `onInit`（`lib/service/script_service.dart:17`）改为（autoRunScript 在 Task 6 实现，本步先加 restore 与占位调用）：

```dart
  @override
  Future<void> onInit() async {
    _loadAutoScriptListFromStorage();
    final scriptList = await ApiClient().getScriptList();
    if (scriptList.isNotEmpty) {
      await Future.wait(scriptList.map((name) => connectScript(name)));
    }
    super.onInit();
    // 后端就绪检查 + 自动启动脚本在 Task 6 接入
    await _waitBackendReadyAndAutoRun();
  }
```

> 注：`_waitBackendReadyAndAutoRun` 在 Task 6 创建。本 task 暂时引用未定义方法会让 analyze 报错——**Task 5 与 Task 6 必须连续完成后再跑 analyze**；或在 Step 3 先保留原 `super.onInit()` 不动，把 `_loadAutoScriptListFromStorage()` 加在第一行，onInit 的其它改动留到 Task 6。**采用后者**：Step 3 实际只改一行：

```dart
  @override
  Future<void> onInit() async {
    _loadAutoScriptListFromStorage();   // 新增：先恢复列表
    final scriptList = await ApiClient().getScriptList();
    if (scriptList.isNotEmpty) {
      await Future.wait(scriptList.map((name) => connectScript(name)));
    }
    super.onInit();
  }
```

- [x] **Step 4: deleteScriptModel 同步移除自启标记**

把 `deleteScriptModel`（`lib/service/script_service.dart:112`）改为：

```dart
  void deleteScriptModel(String name) {
    if (!scriptModelMap.containsKey(name)) return;
    scriptModelMap.remove(name);
    wsService.close(name);
    // 同步移除自启标记（覆盖真实删除场景；重命名场景由 renameConfig 单独迁移）
    if (autoScriptList.remove(name)) {
      _persistAutoScriptList();
    }
  }
```

- [x] **Step 5: 验证编译**

Run: `flutter analyze lib/service/script_service.dart`
Expected: `No issues found!`

- [x] **Step 6: Commit**

```bash
git add lib/service/script_service.dart
git commit -m "feat: ScriptService 扩展自动启动脚本列表持久化与 isRunning"
```

---

### Task 6: ScriptService 扩展 — 后端就绪检查与 autoRunScript

**Files:**
- Modify: `lib/service/script_service.dart`

**Interfaces:**
- Produces: `Future<void> _waitBackendReadyAndAutoRun()`、`Future<void> autoRunScript()`
- Consumes: `ApiClient().testAddress()`（`lib/api/api_client.dart:92`）、`startScript`、`isRunning`、`I18n.autoRunScript`、`I18n.startSuccess`

> 触发时机设计见 design doc：来源项目真实触发点是「确认连上后端后」，当前项目无对应 controller，改在 `onInit` 末尾用 `testAddress` 轮询 5 次 × 500ms 近似达成。就绪检查不可达时跳过 autoRun 且不报错。

- [x] **Step 1: 在 onInit 末尾接入就绪检查**

把 `onInit` 改为：

```dart
  @override
  Future<void> onInit() async {
    _loadAutoScriptListFromStorage();
    final scriptList = await ApiClient().getScriptList();
    if (scriptList.isNotEmpty) {
      await Future.wait(scriptList.map((name) => connectScript(name)));
    }
    super.onInit();
    // 确认后端可达后再自动启动脚本；不可达则跳过且不报错
    await _waitBackendReadyAndAutoRun();
  }
```

- [x] **Step 2: 新增就绪检查与 autoRunScript**

在 `updateAutoScript` 方法之后新增：

```dart
  // 后端就绪检查：轮询 testAddress，5 次内可达即触发自动启动脚本
  Future<void> _waitBackendReadyAndAutoRun() async {
    const maxRetry = 5;
    const interval = Duration(milliseconds: 500);
    for (var i = 0; i < maxRetry; i++) {
      if (await ApiClient().testAddress()) {
        await autoRunScript();
        return;
      }
      await Future.delayed(interval);
    }
    // 后端不可达：跳过自动启动，不报错（可能未登录或服务未起）
  }

  // 自动启动脚本：fire-and-forget，并发启动已过滤「跳过已运行」的列表，
  // 延迟采样运行状态，成功才提示；不阻塞启动流程。
  Future<void> autoRunScript() async {
    if (autoScriptList.isEmpty) return;
    final pending =
        autoScriptList.where((name) => !isRunning(name)).toList();
    if (pending.isEmpty) return;
    await Future.wait(pending.map((name) => startScript(name)));
    // 延迟采样运行状态判断成功，fire-and-forget 不阻塞调用方
    Future.delayed(const Duration(seconds: 4), () {
      final ok = autoScriptList.where(isRunning).toList();
      if (ok.isNotEmpty) {
        Get.snackbar(I18n.autoRunScript.tr, '$ok ${I18n.startSuccess.tr}');
      }
    });
  }
```

- [x] **Step 3: 验证编译**

Run: `flutter analyze lib/service/script_service.dart`
Expected: `No issues found!`

- [x] **Step 4: Commit**

```bash
git add lib/service/script_service.dart
git commit -m "feat: ScriptService 接入后端就绪检查与 autoRunScript"
```

---

### Task 7: ctrl_nav 同步 — 删除/重命名时维护 autoScriptList

**Files:**
- Modify: `lib/controller/ctrl_nav.dart:107-159`（`deleteConfig`、`renameConfig`）

**Interfaces:**
- Consumes: Task 5 的 `deleteScriptModel`（已含移除逻辑）、`ScriptService.updateAutoScript`

> **数据完整性陷阱**（design doc 关键决策）：`renameConfig` 内部是 `deleteScriptModel(old)` + `addScriptModel(new)`。`deleteScriptModel` 现在会移除自启标记，所以重命名会误删标记。本 task 在 `renameConfig` 删旧前捕获旧名是否在列表，加新后迁移到新名。`deleteConfig` 不需改动——`deleteScriptModel` 已处理。

- [x] **Step 1: renameConfig 迁移自启标记**

把 `renameConfig`（`lib/controller/ctrl_nav.dart:139`）改为（在原逻辑外层包一层自启标记迁移）：

```dart
  Future<void> renameConfig(String oldName, String newName) async {
    final int idx = navNameList.indexOf(oldName);
    if (idx == -1) return;
    // 删旧前先捕获自启标记，deleteScriptModel 会顺带移除自启标记
    final scriptService = Get.find<ScriptService>();
    final hadAutoRun = scriptService.autoScriptList.contains(oldName);
    // rename remote config
    if (!await ApiClient().renameConfig(oldName, newName)) return;
    // rename local config
    navNameList[idx] = newName;
    // force delete controller and register new one
    try {
      // when delete, ws can auto close, so force delete controller
      Get.delete<OverviewController>(tag: oldName, force: true);
      scriptService.deleteScriptModel(oldName);
    } catch (_) {}
    // reactive new controller on current idx
    if (idx == selectedIndex.value) {
      switchScript(idx);
    } else {
      Get.put(tag: newName, permanent: true, OverviewController(name: newName));
      scriptService.addScriptModel(newName);
    }
    // 把旧名的自启标记迁移到新名（deleteScriptModel 已抹掉旧名）
    if (hadAutoRun) {
      scriptService.updateAutoScript(newName, true);
    }
  }
```

> 注意：原代码在 `idx == selectedIndex.value` 分支 `return`，重命名后由 `switchScript` 重建 controller；非选中分支才手动 `addScriptModel`。本次把 `return` 改成 `if/else`，是为了让末尾的自启标记迁移对两个分支都生效——这是**行为修正**，注释已说明。

- [x] **Step 2: 验证编译**

Run: `flutter analyze lib/controller/ctrl_nav.dart`
Expected: `No issues found!`

- [x] **Step 3: Commit**

```bash
git add lib/controller/ctrl_nav.dart
git commit -m "feat: 重命名脚本时迁移自启标记"
```

---

### Task 8: 设置页 UI — 开机自启开关与自动启动脚本多选

**Files:**
- Modify: `lib/views/settings/settings_view.dart`

**Interfaces:**
- Consumes: Task 3 的 `AutoStartService`（`enableLaunchAtStartup`、`updateLaunchAtStartupEnable`、`isApplying`）、Task 5 的 `ScriptService`（`scriptModelMap`、`autoScriptList`、`updateAutoScript`）、`PlatformUtils.isDesktop`、`I18n.launchAtStartup`、`I18n.autoRunScriptConfig`

> 设置页现有风格：私有 `StatelessWidget` + `styled_widget`（`.paddingAll`/`.toColumn`）+ `Obx`。两个新控件整体用 `PlatformUtils.isDesktop` 守卫，非桌面不渲染。`SettingsView.build` 的 body Column（`settings_view.dart:18-25`）插入这两个 widget。

- [x] **Step 1: 加 import**

在 `lib/views/settings/settings_view.dart` 顶部 import 区新增：

```dart
import 'package:oasx/service/auto_start_service.dart';
import 'package:oasx/service/script_service.dart';
import 'package:oasx/utils/platform_utils.dart';
```

- [x] **Step 2: 在 build 的 Column 中插入两个控件（桌面守卫）**

把 `SettingsView.build` 的 body（`settings_view.dart:18-25`）改为：

```dart
      body: SingleChildScrollView(
          child: <Widget>[
        const _ThemeWidget().paddingAll(5),
        const _LanguageWidget().paddingAll(5),
        if (PlatformUtils.isDesktop) const _AutoStartWidget().paddingAll(5),
        if (PlatformUtils.isDesktop)
          const _AutoRunScriptsWidget().paddingAll(5),
        killServerButton(),
        _exitButton(),
      ].toColumn().alignment(Alignment.center)),
```

- [x] **Step 3: 新增 _AutoStartWidget**

在文件末尾新增私有 widget：

```dart
// 开机自启开关，绑定 AutoStartService 的真实系统状态
class _AutoStartWidget extends StatelessWidget {
  const _AutoStartWidget();

  @override
  Widget build(BuildContext context) {
    final service = Get.find<AutoStartService>();

    return Obx(() {
      final enabled = service.enableLaunchAtStartup.value;
      final applying = service.isApplying.value;
      return <Widget>[
        Text(I18n.launchAtStartup.tr).paddingOnly(bottom: 5),
        Switch(
          value: enabled,
          onChanged: applying ? null : (v) => service.updateLaunchAtStartupEnable(v),
        )
      ].toColumn();
    });
  }
}
```

- [x] **Step 4: 新增 _AutoRunScriptsWidget**

在 `_AutoStartWidget` 之后新增：

```dart
// 自动启动脚本多选列表，数据源为 scriptModelMap.keys（仅真实脚本）
class _AutoRunScriptsWidget extends StatelessWidget {
  const _AutoRunScriptsWidget();

  @override
  Widget build(BuildContext context) {
    final scriptService = Get.find<ScriptService>();

    return Obx(() {
      final scriptNames = scriptService.scriptModelMap.keys.toList();
      final selected = scriptService.autoScriptList;
      return <Widget>[
        Text(I18n.autoRunScriptConfig.tr).paddingOnly(bottom: 5),
        ...scriptNames.map((name) => CheckboxListTile(
              value: selected.contains(name),
              onChanged: (v) => scriptService.updateAutoScript(name, v ?? false),
              title: Text(name),
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
            )),
      ].toColumn(
          crossAxisAlignment: CrossAxisAlignment.start);
    });
  }
}
```

- [x] **Step 5: 验证编译**

Run: `flutter analyze lib/views/settings/settings_view.dart`
Expected: `No issues found!`

- [x] **Step 6: Commit**

```bash
git add lib/views/settings/settings_view.dart
git commit -m "feat: 设置页新增开机自启开关与自动启动脚本多选"
```

---

### Task 9: 单元测试 — autoScriptList 持久化与 autoRunScript 逻辑

**Files:**
- Create: `test/service/script_service_auto_test.dart`

**Interfaces:**
- Consumes: Task 5/6 的 `ScriptService`（autoScriptList、updateAutoScript、isRunning、autoRunScript、_loadAutoScriptListFromStorage）

> 测试范围：持久化读写、增删排序、isRunning 判断、autoRunScript 跳过已运行。`testAddress` 轮询和真实 `startScript` 依赖 WebSocket/网络，**不在此测**，由 Task 11 手动验证覆盖。

- [x] **Step 1: 创建测试文件**

`test/service/script_service_auto_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:oasx/model/const/storage_key.dart';
import 'package:oasx/model/script_model.dart';
import 'package:oasx/service/script_service.dart';

// 测试前初始化 GetStorage 与必要依赖，避免 ScriptService.onInit 触发网络请求。
void main() {
  setUpAll(() async {
    Get.testMode = true;
    await GetStorage.init();
  });

  setUp(() async {
    GetStorage.init();
    await GetStorage().remove(StorageKey.autoScriptList.name);
  });

  // 锁定 updateAutoScript 的增删与排序，并验证持久化写入
  test('updateAutoScript adds, removes and persists sorted list', () {
    final service = ScriptService();
    service.updateAutoScript('b', true);
    service.updateAutoScript('a', true);
    expect(service.autoScriptList, ['a', 'b']);
    final raw = GetStorage().read(StorageKey.autoScriptList.name);
    expect(raw, isNotNull);

    service.updateAutoScript('a', false);
    expect(service.autoScriptList, ['b']);
  });

  // 锁定 isRunning 基于 scriptModelMap 状态判断
  test('isRunning reflects scriptModelMap running state', () {
    final service = ScriptService();
    service.addScriptModel('oas1');
    expect(service.isRunning('oas1'), isFalse);
    service.scriptModelMap['oas1']!.update(state: ScriptState.running);
    expect(service.isRunning('oas1'), isTrue);
  });

  // 锁定 autoRunScript 在全部已运行时直接跳过，不发 startScript
  test('autoRunScript skips when all listed scripts already running', () async {
    final service = ScriptService();
    service.addScriptModel('oas1');
    service.scriptModelMap['oas1']!.update(state: ScriptState.running);
    service.updateAutoScript('oas1', true);

    // autoRunScript 不应抛错，且因全部 running 不发 startScript
    await service.autoRunScript();
    expect(service.autoScriptList, ['oas1']);
  });
}
```

- [x] **Step 2: 运行测试验证通过**

Run: `flutter test test/service/script_service_auto_test.dart`
Expected: `All tests passed!`

- [x] **Step 3: Commit**

```bash
git add test/service/script_service_auto_test.dart
git commit -m "test: 自动启动脚本持久化与 autoRunScript 跳过逻辑"
```

---

### Task 10: 手动验证清单与回归检查

**Files:**
- Modify: `openspec/changes/port-startup-logs/tasks.md`（勾选已完成项）

**Interfaces:**
- Consumes: 全部前序 task 的产物

> 本 task 不写自动化测试，仅跑全量回归 + 记录手动验证清单。MSIX 沙箱下的 schtasks 提权、跨平台真实自启注册项，单元测试覆盖不了，必须手动验证（design doc 风险表）。

- [x] **Step 1: 全量静态分析**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 2: 全量测试回归**

Run: `flutter test`
Expected: `All tests passed!`（含原有 contract/widget 测试 + Task 9 新测试）

- [x] **Step 3: 在 tasks.md 勾选已完成项**

把 `openspec/changes/port-startup-logs/tasks.md` 中所有 9 个 `- [ ]` 改为 `- [x]`。

- [x] **Step 4: 记录手动验证清单（commit body）**

把下列清单写入 commit body 并提交：

```bash
git add openspec/changes/port-startup-logs/tasks.md
git commit -m "chore: 勾选 port-startup-logs 任务

手动验证清单（发布前必做，自动化测试覆盖不到）：
- MSIX 安装版下开关自启：schtasks 提权成功、系统注册项创建/删除
- Windows/macOS/Linux 桌面平台自启状态同步与失败提示
- 后端慢启动场景（>2.5s 可达）下自动运行脚本正确触发
- 删除脚本后 autoScriptList 同步移除
- 重命名脚本后自启标记迁移到新名（不丢失）"
```

---

## Spec 覆盖自检（Self-Review）

逐条对照 `openspec/changes/port-startup-logs/specs/startup-auto-run/spec.md` 验收场景：

| Spec 验收场景 | 承载 Task |
| --- | --- |
| Enable / Disable launch at startup | Task 3（AutoStartService）+ Task 8（开关） |
| Refresh launch state（启动读真实状态） | Task 3（onInit refresh）+ Task 4（注册） |
| Add / Remove script to automatic run list | Task 5（updateAutoScript + 持久化）+ Task 8（多选 UI） |
| Restore automatic run list | Task 5（onInit `_loadAutoScriptListFromStorage`） |
| Start configured scripts | Task 6（autoRunScript 复用 startScript + 进度反馈） |
| Skip already running script | Task 5/6（isRunning 过滤） |
| Continue after failed script start | Task 6（Future.wait 并发 + 延迟采样，不改协议） |

无遗漏。所有验收场景都有对应 task 实现。

