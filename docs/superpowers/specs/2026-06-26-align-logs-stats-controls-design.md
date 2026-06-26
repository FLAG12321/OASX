---
comet_change: align-logs-stats-controls
role: technical-design
canonical_spec: openspec
---

# align-logs-stats-controls 技术设计

## 目标与范围

本变更对齐 Logs / Stats 标签体验：

1. Logs 能加载脚本运行历史日志：初始加载最近一段，用户向上翻阅接近顶部时继续懒加载更早日志。
2. Stats 不再显示手动刷新按钮，继续依赖现有自动刷新流。
3. 日志操作按钮（复制、自动滚动、清空）仅在 Logs 标签显示，Stats 标签隐藏，切回 Logs 自动恢复。

非目标：
- 不新增后端协议。
- 不读取 OASX GUI 自身 app log（`lib/utils/logger.dart` 写出的 cache logs），因为 Logs 面板语义是脚本运行日志。
- 不重写 Stats 编排或日志渲染核心，只补齐历史窗口加载与操作可见性。

## 当前项目锚点

| 现有锚点 | 现状 | 本次改动 |
| --- | --- | --- |
| `lib/component/log/log_widget.dart` | `LogWidget` 已有 `enableCopy` / `enableAutoScroll` / `enableClear` 参数，默认显示操作按钮 | 复用这些参数，不新增操作栏组件 |
| `lib/component/log/log_mixin.dart` | 有 `logs`、pending buffer、`savedScrollOffset`、copy/clear/autoScroll 能力 | 扩展历史窗口加载所需状态/方法，或新增协作 controller 后让现有 LogWidget 消费 |
| `lib/views/overview/overview_logs_stats_view.dart` | `TabController` 切 Logs/Stats，但未驱动日志操作按钮可见性 | 根据 tab index 传 `showLogActions` |
| `lib/views/overview/overview_view.dart` | `Overview` 统一创建 `LogWidget`，Stats 通过 `logChild` 替换日志主体 | 新增 `showLogActions`，转发给 `LogWidget.enableCopy/enableAutoScroll/enableClear` |
| `lib/views/overview/stats_overview_panel.dart` | `_HeaderSection` 仍传 `onRefresh` 并显示 `Icons.refresh_rounded` | 移除手动刷新按钮与 `onRefresh` 参数，保留自动刷新 |
| `lib/controller/stats/stats_page_controller.dart` | `startAutoRefresh()` / `stopAutoRefresh()` 已存在 | 保持不变 |
| 来源项目 `lib/modules/log/script_log_browser_*` | 有日志窗口 cursor、懒加载 older、live stream、viewport preserve 策略 | 作为实现参照，精简移植必要状态与算法 |

## 架构设计

### 1. Logs / Stats 操作栏可见性

在 `Overview` 增加：

```dart
final bool showLogActions;
```

默认 `true`，避免影响其它调用点。

`OverviewLogsStatsView`：

```dart
final showStats = _tabController.index == 1;
return Overview(
  logTopPanelLeading: ...,
  logChild: showStats ? StatsOverviewPanel(scriptName: widget.scriptName) : null,
  showLogActions: !showStats,
);
```

`Overview` 创建 `LogWidget` 时：

```dart
enableCopy: showLogActions,
enableAutoScroll: showLogActions,
enableClear: showLogActions,
enableCollapse: false,
```

这样 Stats tab 顶部仍保留 TabBar 布局，但右侧日志操作按钮消失；切回 Logs 后参数变回 true，按钮恢复。

### 2. Stats 手动刷新按钮移除

`StatsOverviewPanel` 当前在 build 中传：

```dart
_HeaderSection(
  controller: controller,
  onRefresh: controller.refreshCurrentDate,
),
```

设计改为：

```dart
_HeaderSection(controller: controller),
```

并删除 `_HeaderSection.onRefresh` 字段与 refresh `IconButton`。

`StatsPageController` 的自动刷新保持不变：
- `initState()` 后 `controller.bootstrap(...)` + `controller.startAutoRefresh()`
- `dispose()` 时 `controller.stopAutoRefresh()`
- `Timer.periodic` 中 `unawaited(refreshCurrentDate())`

### 3. 脚本历史日志窗口懒加载

#### 3.1 数据源

历史日志指 **脚本运行日志**，不读取 OASX app 自身日志文件。

在当前 `ApiClient` 补来源项目既有端点的前端封装：

- `Future<ScriptLogWindow> getScriptLogWindow(String scriptName, {String? cursor, int limitLines = 100})`
- `Uri buildScriptLogStreamUri(String scriptName, {String? cursor, int limitLines = 100})`

这些方法只封装来源项目已有日志窗口 / SSE 能力；如果当前后端版本不支持，前端捕获错误并 fallback，不新增协议。

需要新增轻量 model：

```dart
class ScriptLogLine {
  final String key;
  final String text;
}

class ScriptLogWindow {
  final List<ScriptLogLine> lines;
  final String? olderCursor;
  final String liveCursor;
  final bool reachedStart;
}
```

具体 JSON 字段以来源项目 `log_browser_models.dart` 为准；build 阶段优先精简移植必要字段。

#### 3.2 状态位置

推荐扩展 `OverviewController`（它已 mixin `LogMixin` 并绑定脚本名），而不是新建独立页面 controller：

- `olderCursor`
- `liveCursor`
- `reachedStart`
- `historyLoading`
- `_historyLineKeys`
- `Future<void> loadLatestHistoricalLogs()`
- `Future<void> loadOlderHistoricalLogs()`

理由：当前 Logs 面板已经由 `OverviewController` 管理 `logs` 和 WebSocket 实时追加；历史窗口与实时日志需要进入同一个 `logs` 列表并共享 copy/clear/auto-scroll 行为。

#### 3.3 初始化加载

首次进入 Logs tab 或创建 `OverviewController` 后：

1. 调用 `loadLatestHistoricalLogs()`。
2. 成功：用最近窗口初始化 `logs`，设置 `olderCursor/liveCursor/reachedStart`，记录 `_historyLineKeys`。
3. 失败：不阻塞 UI，保留现有 WebSocket 实时日志路径；错误只记录到 debug / controller 状态，不弹阻断式错误。

为避免覆盖已收到的实时日志：
- 若 `logs` 已有 WebSocket 新日志，加载历史后先合并去重，再保持新日志在后。
- 去重优先用 `ScriptLogLine.key`；若后端没有稳定 key，则以 `text` + 窗口位置 fallback。

#### 3.4 向上懒加载

在 `LogContent` / `_LogWidgetState._handleUserScroll` 增加接近顶部检测：

```dart
if (currentOffset <= 80) {
  controller.loadOlderLogs?.call();
}
```

为了不把 `LogWidget` 绑定死到 `OverviewController`，推荐在 `LogMixin` 增加可选 callback：

```dart
Future<void> Function()? loadOlderLogs;
void Function(int insertedCount)? preserveViewportAfterPrepend;
```

或者更简单：在 `LogMixin` 定义空实现方法：

```dart
Future<void> loadOlderLogs() async {}
bool get canLoadOlderLogs => false;
```

`OverviewController` override / 实现即可。

prepend 更早日志后必须保持视口：
- 记录加载前第一条可见日志或当前 offset。
- prepend 后通过 `ScrollController.jumpTo(oldOffset + insertedHeightEstimate)` 或来源项目 anchor 方案恢复。
- 若无法精确计算高度，至少保证不会自动跳到底部（`autoScroll=false` 时不触发底部滚动）。

#### 3.5 实时日志 append

现有 WebSocket `addLog` 继续 append：

- 如果历史窗口已加载，新实时日志追加到 `logs` 尾部。
- 如果重复，按 `_historyLineKeys` 过滤。
- `autoScroll=true` 时继续滚到底部；用户向上翻阅历史时 `autoScroll=false`，新日志不打断阅读。

### 4. Fallback 策略

如果 `getScriptLogWindow` 或 stream uri 请求失败：

- Logs 页面仍显示现有实时 WebSocket 日志。
- 不清空已有 `logs`。
- `historyLoading=false`，`reachedStart=true` 或保留可重试状态，避免无限请求。
- 测试覆盖失败时不抛异常。

## Spec Patch

已回写 `openspec/changes/align-logs-stats-controls/specs/logs-stats-experience/spec.md`：

- 打开 Logs 时加载最近一段脚本历史日志。
- 向上滚动接近顶部时加载更早日志。
- 无更多历史时停止加载。
- 历史日志源不可用时降级为现有实时日志显示。

## 测试策略

### Widget / contract 测试

更新 `test/views/overview/overview_logs_stats_view_test.dart`：

- Logs tab 初始显示 `Icons.flash_on`、`Icons.content_copy_rounded`、`Icons.delete_outlined`。
- 切到 Stats tab 后这些按钮不可见。
- 切回 Logs tab 后按钮恢复。

更新 `test/views/overview/stats_overview_panel_test.dart`：

- 不再查找 `Icons.refresh_rounded`。
- 保持现有自动刷新相关 controller 测试不变。

### 单元测试

新增或更新历史日志窗口纯 Dart 测试：

- `loadLatestHistoricalLogs` 初始加载最近窗口。
- `loadOlderHistoricalLogs` prepend 更早窗口。
- `reachedStart=true` 后不再请求。
- API 失败 fallback 不抛异常、不清空已有实时日志。
- WebSocket append 与历史窗口去重。

### 手动验证

- 打开 Logs 可看到最近历史日志。
- 向上滚动接近顶部可继续加载更早日志。
- 切 Stats 后日志操作按钮隐藏。
- 切回 Logs 后按钮恢复。
- Stats 无手动刷新按钮，但数据自动刷新仍工作。

## 风险与缓解

| 风险 | 缓解 |
| --- | --- |
| 当前 OAS 后端版本不支持来源日志窗口端点 | fallback 到现有实时日志，不阻塞 Logs 页面 |
| prepend 更早日志导致视口跳动 | 使用 saved offset / anchor 策略，至少禁止自动滚到底部 |
| 历史窗口与实时流重复 | 用 line key 去重；无 key 时用文本 fallback |
| 日志量过大 | 窗口化加载，限制保留行数（参考来源项目 100/300 行窗口） |
| 移除 Stats 手动刷新导致用户无法强制刷新 | 保留自动刷新 timer，并用测试确认自动刷新仍工作 |
