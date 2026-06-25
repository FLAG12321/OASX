# Brainstorm Summary

- Change: port-startup-logs
- Date: 2026-06-25

## 确认的技术方案

精简移植来源项目（`C:\Users\lu\Desktop\yys\OnmyojiAutoScript-easy-install\OASX`）的开机自启与自动启动脚本能力到当前项目。**不引入** ProgressSnackbarController、TimeoutUtils、part 文件等附属机制；autoRunScript 直接写进 `script_service.dart`。

架构：
- `main.dart initService()` 注册 `AutoStartService`（permanent，桌面守卫）。
- `LayoutBinding` 注册 `ScriptService`；`onInit` 改为「连接脚本 → `testAddress()` 重试确认后端可达 → `autoRunScript()`」。
- 设置页 `/settings` 用 `PlatformUtils.isDesktop` 包裹新增「开机自启总开关」+「自动启动脚本多选列表」。

autoRunScript（fire-and-forget + 延迟采样）：
```dart
Future<void> autoRunScript() async {
  if (autoScriptList.isEmpty) return;
  final pending = autoScriptList.where((n) => !isRunning(n)).toList();
  await Future.wait(pending.map((n) => startScript(n)));
  Future.delayed(const Duration(seconds: 4), () {
    final ok = autoScriptList.where(isRunning).toList();
    if (ok.isNotEmpty) Get.snackbar(I18n.autoRunScript.tr, '$ok ${I18n.startSuccess.tr}');
  });
}
```
后端就绪检查：onInit 连接后用 `ApiClient().testAddress()` 轮询重试（3-5 次 × 500ms），可达才 autoRunScript，不可达跳过不报错。

多选列表数据源：`ScriptService.scriptModelMap.keys`（只含真实脚本，不含 'Home'），**不用 navNameList**。

## 关键取舍与风险

- **触发时机修正**：来源项目 autoRunScript 真实触发点是 `dashboard_controller_startup.dart:127`（确认连上后端后），不是 onInit。当前项目无该 controller，改在 onInit 加 testAddress 就绪检查近似达成「确认连上后端后」语义。
- **ScriptService 是 permanent + onInit 单次**：killServer 后 `Get.delete<ScriptService>` 再登录会重跑 onInit → 重跑 autoRunScript，语义合理。
- **数据完整性**：`deleteScriptModel` 必须同步 `autoScriptList.removeWhere` + 持久化；`renameConfig` 链路顺手迁移 autoScriptList 旧名→新名。
- **MSIX 分发风险**：当前项目 `store: true` 走 Microsoft Store/MSIX。来源项目 Windows 自启用 `schtasks` + `Start-Process -Verb RunAs` 提权，在 MSIX 沙箱下行为可能与便携版不同。**必须在 MSIX 安装包上手动验证**，单元测试覆盖不了。
- **_windowsTaskName 硬编码 'OASX'**：直接移植可接受，但知悉存在同名任务冲突可能。
- **autoRunScript 并发 start**：`Future.wait` 并发发 start，脚本多时对后端有压力；用户通常勾 1-2 个，低风险。

## 测试策略

- 单元测试：`autoScriptList` 持久化读写、`updateAutoScript` 增删排序、`testAddress` 就绪重试逻辑。
- Widget 测试：设置页开关 + 多选列表渲染（桌面）、勾选触发持久化、`isRunning` 跳过逻辑、非桌面不渲染开关。
- `flutter analyze` + 现有测试不回归。
- 手动测试（必做）：① MSIX 安装版下 schtasks 提权 + 开关自启；② 桌面平台开关自启真实注册项；③ 后端慢启动场景自动跑脚本；④ 删除/重命名脚本后 autoScriptList 同步。

## Spec Patch

无。现有 `startup-auto-run` delta spec 的验收场景已覆盖，无需回写。但 build 阶段需补充：onInit 触发时机的实现细节（testAddress 就绪检查）属于实现决策，不改变 spec 验收场景。
