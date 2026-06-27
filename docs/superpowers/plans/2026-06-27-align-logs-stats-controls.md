# align-logs-stats-controls 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 Logs 标签加载脚本历史日志（打开时加载最新窗口，向上滚动懒加载更早窗口），Stats 标签移除手动刷新按钮但保留自动刷新，日志操作按钮仅在 Logs 标签显示。

**Architecture:** 历史日志使用已实测存在的 `GET /logs/{script_name}` HTTP 窗口接口；实时日志继续使用现有 WebSocket，不切 SSE。历史窗口状态放在 `OverviewController`，由 `LogWidget` 的滚动钩子触发 `LogMixin.loadOlderLogs()`，prepend 后通过轻量 offset 补偿保持视口。

**Tech Stack:** Flutter / Dart, GetX, flutter_test, `flutter_nb_net`。

## Global Constraints

- 所有新增/修改代码写中文注释；受影响旧注释同步更新，未受影响注释不改动。
- 不新增后端协议；只封装已实测 `GET /logs/{script_name}`。
- 实时日志保持现有 WebSocket（`ScriptService.wsListener` → `OverviewController.addLog`），不使用 `/logs/{script_name}/stream`。
- 历史日志失败 fallback：不抛异常、不清空已有 `logs` / pending 实时日志、不阻塞 Logs。
- 打开 Logs 恢复现有 `savedScrollOffset` 行为；prepend 历史日志后保持当前阅读视口，至少不跳到底部。
- `Overview.showLogActions` 默认 `true`，只在 Stats tab 传 `false`。
- 提交前必须先展示拟定 commit message 给用户审查；用户确认后才能执行 `git commit`。

## File Structure

| 文件 | 职责 | 动作 |
| --- | --- | --- |
| `lib/api/script_log_models.dart` | 解析日志窗口、保留行级 key 与 text | 新建 |
| `lib/api/api_client.dart` | 封装 `getScriptLogWindow`，并暴露可测 query/path helper | 修改 |
| `lib/component/log/log_mixin.dart` | 增加历史懒加载钩子、pending 去重辅助、视口保持回调 | 修改 |
| `lib/component/log/log_widget.dart` | 顶部滚动触发懒加载，注册 prepend 视口补偿 | 修改 |
| `lib/controller/overview/overview_controller.dart` | 管理历史 cursor/loading/reachedStart、加载 latest/older、去重 | 修改 |
| `lib/views/overview/overview_view.dart` | `Overview.showLogActions` 转发给 `LogWidget` | 修改 |
| `lib/views/overview/overview_logs_stats_view.dart` | 按 tab 传 `showLogActions: !showStats` | 修改 |
| `lib/views/overview/stats_overview_panel.dart` | 删除手动刷新按钮与 `onRefresh` | 修改 |
| `test/api/script_log_window_api_test.dart` | model/helper 纯单测，不触真实网络 | 新建 |
| `test/controller/overview/overview_log_history_test.dart` | controller 历史加载/fallback/去重/older 单测 | 新建 |
| `test/views/overview/overview_log_actions_test.dart` | `Overview` 转发与 `LogWidget` 行为测试 | 新建 |
| `test/views/overview/stats_overview_panel_test.dart` | Stats 无手动刷新按钮测试 | 修改 |

---

### Task 1: 日志窗口 Model 与纯 helper 契约

**Files:**
- Create: `lib\api\script_log_models.dart`
- Modify: `lib\api\api_client.dart`
- Test: `test\api\script_log_window_api_test.dart`

**Interfaces:**
- Produces: `ScriptLogLine.key`, `ScriptLogLine.text`, `ScriptLogWindow.fromWindowJson(...)`。
- Produces: `ApiClient.buildScriptLogWindowPath(String scriptName)` 与 `ApiClient.buildScriptLogWindowQuery({String? cursor, int limitLines = 500})`，供测试纯校验，不触发网络。

- [ ] **Step 1: 写失败测试**

创建 `test\api\script_log_window_api_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/api/api_client.dart';
import 'package:oasx/api/script_log_models.dart';

void main() {
  // 中文注释：锁定日志窗口 model 保留后端行级 key，避免相同文本被误判重复。
  test('ScriptLogWindow parses text cursors and stable line keys', () {
    final window = ScriptLogWindow.fromWindowJson({
      'older_cursor': 'older-token',
      'live_cursor': 'live-token',
      'reached_start': false,
      'lines': [
        {
          'file_name': '2026-06-27_oas1.txt',
          'line_no': 1,
          'offset': 10,
          'byte_length': 8,
          'text': 'INFO: same\n',
        },
        {
          'file_name': '2026-06-27_oas1.txt',
          'line_no': 2,
          'offset': 20,
          'byte_length': 8,
          'text': 'INFO: same\n',
        },
      ],
    });

    expect(window.olderCursor, 'older-token');
    expect(window.liveCursor, 'live-token');
    expect(window.reachedStart, isFalse);
    expect(window.lines.map((line) => line.text), ['INFO: same\n', 'INFO: same\n']);
    expect(window.lines[0].key, isNot(window.lines[1].key));
  });

  // 中文注释：锁定 reached_start=true 时不再暴露 olderCursor。
  test('reached start clears older cursor', () {
    final window = ScriptLogWindow.fromWindowJson({
      'older_cursor': 'older-token',
      'reached_start': true,
      'lines': [],
    });

    expect(window.reachedStart, isTrue);
    expect(window.olderCursor, isNull);
  });

  // 中文注释：ApiClient helper 纯构造路径与 query，不实例化网络客户端。
  test('ApiClient builds log window path and query without network', () {
    expect(ApiClient.buildScriptLogWindowPath('oas 1'), '/logs/oas%201');
    expect(ApiClient.buildScriptLogWindowQuery(), {'limit_lines': 500});
    expect(
      ApiClient.buildScriptLogWindowQuery(cursor: 'older', limitLines: 200),
      {'limit_lines': 200, 'cursor': 'older'},
    );
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/api/script_log_window_api_test.dart -r expanded`
Expected: FAIL，`script_log_models.dart` / helper 不存在。

- [ ] **Step 3: 实现 model**

创建 `lib\api\script_log_models.dart`：

```dart
/// 单条脚本运行日志行。
class ScriptLogLine {
  const ScriptLogLine({required this.key, required this.text});

  /// 后端文件位置组合成的稳定 key，用于历史窗口与实时日志去重。
  final String key;

  /// 日志原始文本（含换行），用于 LogWidget 渲染。
  final String text;

  factory ScriptLogLine.fromJson(Map<String, dynamic> json) {
    final fileName = (json['file_name'] ?? '').toString();
    final lineNo = (json['line_no'] ?? '').toString();
    final offset = (json['offset'] ?? '').toString();
    final byteLength = (json['byte_length'] ?? '').toString();
    final text = (json['text'] ?? '').toString();
    final key = [fileName, lineNo, offset, byteLength]
        .where((part) => part.isNotEmpty)
        .join(':');
    return ScriptLogLine(key: key.isEmpty ? text : key, text: text);
  }
}

/// 脚本历史日志窗口。
class ScriptLogWindow {
  const ScriptLogWindow({
    required this.lines,
    required this.olderCursor,
    required this.liveCursor,
    required this.reachedStart,
  });

  final List<ScriptLogLine> lines;
  final String? olderCursor;
  final String? liveCursor;
  final bool reachedStart;

  factory ScriptLogWindow.fromWindowJson(Map<String, dynamic> json) {
    final rawLines = json['lines'];
    final lines = <ScriptLogLine>[];
    if (rawLines is List) {
      lines.addAll(rawLines
          .whereType<Map<String, dynamic>>()
          .map(ScriptLogLine.fromJson));
    }
    final reachedStart = json['reached_start'] == true;
    return ScriptLogWindow(
      lines: lines,
      // 中文注释：到达起点时清空 olderCursor，避免上层继续请求更早窗口。
      olderCursor: reachedStart ? null : json['older_cursor']?.toString(),
      liveCursor: json['live_cursor']?.toString(),
      reachedStart: reachedStart,
    );
  }
}
```

- [ ] **Step 4: 实现 ApiClient helper 与方法封装**

在 `lib\api\api_client.dart` 顶部加入：

```dart
import 'package:oasx/api/script_log_models.dart';
```

在 `ApiClient` 类内、stats 方法后加入：

```dart
  /// 构造脚本日志窗口路径；单测只覆盖此纯 helper，避免触发真实网络。
  static String buildScriptLogWindowPath(String scriptName) {
    return '/logs/${Uri.encodeComponent(scriptName)}';
  }

  /// 构造脚本日志窗口 query；cursor 为空表示打开最新窗口。
  static Map<String, dynamic> buildScriptLogWindowQuery({
    String? cursor,
    int limitLines = 500,
  }) {
    final query = <String, dynamic>{'limit_lines': limitLines};
    if (cursor != null && cursor.isNotEmpty) {
      query['cursor'] = cursor;
    }
    return query;
  }

  /// 拉取脚本历史日志窗口；失败返回 null，由上层保留 WebSocket 实时日志。
  Future<ScriptLogWindow?> getScriptLogWindow(
    String scriptName, {
    String? cursor,
    int limitLines = 500,
  }) async {
    final res = await request(
      () => get(
        buildScriptLogWindowPath(scriptName),
        queryParameters: buildScriptLogWindowQuery(
          cursor: cursor,
          limitLines: limitLines,
        ),
      ),
    );
    if (!res.isSuccess || res.data is! Map) {
      return null;
    }
    return ScriptLogWindow.fromWindowJson(
      Map<String, dynamic>.from(res.data as Map),
    );
  }
```

- [ ] **Step 5: 运行测试确认通过**

Run: `flutter test test/api/script_log_window_api_test.dart -r expanded`
Expected: PASS，3 个测试通过且不依赖后端运行。

- [ ] **Step 6: 展示提交信息等待用户确认**

拟定 message：

```text
feat(log): add historical log window model and api helper
```

用户确认后执行：

```bash
git add lib/api/script_log_models.dart lib/api/api_client.dart test/api/script_log_window_api_test.dart
git commit -m "feat(log): add historical log window model and api helper"
```

---

### Task 2: Stats 移除手动刷新按钮

**Files:**
- Modify: `lib\views\overview\stats_overview_panel.dart`
- Test: `test\views\overview\stats_overview_panel_test.dart`

**Interfaces:**
- Consumes: `StatsPageController.startAutoRefresh()` / `stopAutoRefresh()` 不变。
- Produces: `_HeaderSection({required controller})`，无 `onRefresh` 字段；无 `Icons.refresh_rounded`。

- [ ] **Step 1: 写失败测试**

在 `test\views\overview\stats_overview_panel_test.dart` 的 `main` 内追加：

```dart
  // 中文注释：锁定 Stats 面板不再渲染手动刷新按钮，刷新由自动流负责。
  testWidgets('stats panel renders no manual refresh button', (tester) async {
    final controller = StatsPageController(
      loadDates: (_) async => ['2026-06-24'],
      loadDay: (_, __) async => _buildDayRaw(totalSeconds: 5),
    );
    Get.put(controller, tag: 'oas1');

    await tester.pumpWidget(
      const GetMaterialApp(
        home: Scaffold(body: StatsOverviewPanel(scriptName: 'oas1')),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byIcon(Icons.refresh_rounded), findsNothing);
  });
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/views/overview/stats_overview_panel_test.dart -r expanded`
Expected: FAIL，当前仍找到 `Icons.refresh_rounded`。

- [ ] **Step 3: 删除按钮和 onRefresh**

把 `StatsOverviewPanel.build` 中 `_HeaderSection` 调用改为：

```dart
          _HeaderSection(controller: controller),
```

把 `_HeaderSection` 整体改为：

```dart
/// 头部：状态图标 + 日期下拉 + 总耗时。
class _HeaderSection extends StatelessWidget {
  const _HeaderSection({required this.controller});

  final StatsPageController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Obx(() {
      final statistics = controller.statistics.value;
      final totalDuration = statistics?.totalRuntimeSeconds ?? 0;
      final isLoading = controller.statisticsLoading.value;
      final tone = isLoading ? scheme.primary : scheme.onSurfaceVariant;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _HeaderStatusIcon(
            loading: isLoading,
            hasData: statistics != null,
            isError: controller.lastErrorMessage.value.isNotEmpty,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _DateDropdown(
              dates: controller.availableDateKeys.toList(),
              selected: controller.selectedDateKey.value,
              onChanged: controller.selectDate,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            formatStatisticsDuration(totalDuration),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: tone,
                ),
          ),
        ],
      );
    });
  }
}
```

- [ ] **Step 4: 验证**

Run: `flutter test test/views/overview/stats_overview_panel_test.dart -r expanded`
Expected: PASS。

Run: `flutter analyze lib/views/overview/stats_overview_panel.dart`
Expected: 无新增 warning/error。

- [ ] **Step 5: 展示提交信息等待用户确认**

```text
feat(stats): remove manual refresh button
```

用户确认后执行对应 `git add` / `git commit`。

---

### Task 3: Logs/Stats 标签控制日志操作按钮

**Files:**
- Modify: `lib\views\overview\overview_view.dart`
- Modify: `lib\views\overview\overview_logs_stats_view.dart`
- Test: `test\views\overview\overview_log_actions_test.dart`

**Interfaces:**
- Produces: `Overview({..., bool showLogActions = true})`。
- Produces: Stats tab 时 `showLogActions=false`，Logs tab/default 时 `true`。

- [ ] **Step 1: 写失败测试（Overview 真实转发 enable 参数）**

创建 `test\views\overview\overview_log_actions_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:oasx/api/script_log_models.dart';
import 'package:oasx/controller/ctrl_nav.dart';
import 'package:oasx/model/script_model.dart';
import 'package:oasx/service/script_service.dart';
import 'package:oasx/views/overview/overview_view.dart';

class _FakeScriptService extends GetxService implements ScriptService {
  @override
  ScriptModel? findScriptModel(String name) => ScriptModel(name);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() {
    final nav = NavCtrl();
    nav.selectedScript.value = 'oas1';
    Get.put<NavCtrl>(nav);
    Get.put<ScriptService>(_FakeScriptService());
    Get.put<OverviewController>(
      OverviewController(
        name: 'oas1',
        scriptModelOverride: ScriptModel('oas1'),
        loadLogWindow: (_, {cursor, limitLines = 500}) async {
          return const ScriptLogWindow(
            lines: [],
            olderCursor: null,
            liveCursor: null,
            reachedStart: true,
          );
        },
      ),
      tag: 'oas1',
    );
  });

  tearDown(() async {
    Get.reset();
  });

  // 中文注释：锁定 Overview.showLogActions=false 会隐藏复制、自动滚动、清空三个按钮。
  testWidgets('Overview hides log action buttons when showLogActions is false', (tester) async {
    await tester.pumpWidget(
      const GetMaterialApp(
        home: Scaffold(body: Overview(showLogActions: false)),
      ),
    );

    expect(find.byIcon(Icons.flash_on), findsNothing);
    expect(find.byIcon(Icons.content_copy_rounded), findsNothing);
    expect(find.byIcon(Icons.delete_outlined), findsNothing);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/views/overview/overview_log_actions_test.dart -r expanded`
Expected: FAIL，`Overview.showLogActions` / `scriptModelOverride` 不存在。

- [ ] **Step 3: 改 OverviewController 构造以支持测试注入**

在 `lib\controller\overview\overview_controller.dart` 中把构造改为：

```dart
  final LoadScriptLogWindow _loadLogWindow;
  final ScriptService? _scriptServiceOverride;
  final ScriptModel? _scriptModelOverride;

  late final scriptService = _scriptServiceOverride ?? Get.find<ScriptService>();
  late final scriptModel = _scriptModelOverride ?? scriptService.findScriptModel(name)!;

  OverviewController({
    required this.name,
    LoadScriptLogWindow? loadLogWindow,
    ScriptService? scriptServiceOverride,
    ScriptModel? scriptModelOverride,
  })  : _loadLogWindow = loadLogWindow ??
            ((scriptName, {cursor, limitLines = 500}) => ApiClient()
                .getScriptLogWindow(scriptName, cursor: cursor, limitLines: limitLines)),
        _scriptServiceOverride = scriptServiceOverride,
        _scriptModelOverride = scriptModelOverride;
```

> `LoadScriptLogWindow` typedef 会在 Task 5 引入；如果先执行本 Task，则先把 typedef 与 `ApiClient` import 一起加入，Task 5 复用即可。

- [ ] **Step 4: 给 Overview 加 showLogActions 并转发**

`lib\views\overview\overview_view.dart`：

```dart
class Overview extends StatelessWidget {
  const Overview({
    Key? key,
    this.logTopPanelLeading,
    this.logChild,
    this.showLogActions = true,
  }) : super(key: key);

  final Widget? logTopPanelLeading;
  final Widget? logChild;

  // 中文注释：Stats 标签传 false，用于隐藏日志操作按钮。
  final bool showLogActions;
```

竖屏/横屏两处 `LogWidget` 都补充：

```dart
                  enableCopy: showLogActions,
                  enableAutoScroll: showLogActions,
                  enableClear: showLogActions,
```

`lib\views\overview\overview_logs_stats_view.dart` 的 `Overview(...)` 加：

```dart
      showLogActions: !showStats,
```

- [ ] **Step 5: 验证**

Run: `flutter test test/views/overview/overview_log_actions_test.dart -r expanded`
Expected: PASS。

Run: `flutter analyze lib/views/overview/overview_view.dart lib/views/overview/overview_logs_stats_view.dart lib/controller/overview/overview_controller.dart`
Expected: 无新增 warning/error。

- [ ] **Step 6: 展示提交信息等待用户确认**

```text
feat(log): hide log actions outside Logs tab
```

用户确认后提交。

---

### Task 4: LogMixin / LogWidget 接入向上懒加载与视口恢复

**Files:**
- Modify: `lib\component\log\log_mixin.dart`
- Modify: `lib\component\log\log_widget.dart`
- Test: `test\views\overview\overview_log_actions_test.dart`

**Interfaces:**
- Produces: `canLoadOlderLogs` / `loadOlderLogs()` / `preserveViewportAfterPrepend` / `estimatedLogLineHeight`。
- Preserves: 现有 `savedScrollOffsetVal` 恢复逻辑不删不改。

- [ ] **Step 1: 写失败测试（saved offset 仍恢复）**

在 `overview_log_actions_test.dart` 增加本地 fake controller（或新 test 文件亦可）：

```dart
class _FakeLogController extends GetxController with LogMixin {
  bool enabled = false;
  int olderCalls = 0;

  @override
  bool get canLoadOlderLogs => enabled;

  @override
  Future<void> loadOlderLogs() async {
    olderCalls += 1;
  }
}
```

追加测试：

```dart
  // 中文注释：锁定 LogWidget 重新创建后继续恢复 LogMixin 保存的滚动 offset。
  testWidgets('LogWidget restores saved scroll offset after rebuild', (tester) async {
    final controller = _FakeLogController();
    controller.logs.addAll(List.generate(100, (index) => 'INFO: line $index\n'));
    controller.saveScrollOffset(120);
    controller.autoScroll.value = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 240, child: LogWidget(controller: controller, title: '日志')),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final listView = tester.widget<ListView>(find.byType(ListView));
    expect(listView.controller!.offset, 120);
  });
```

- [ ] **Step 2: 写失败测试（顶部触发 older）**

```dart
  // 中文注释：锁定用户滚动接近顶部时触发历史日志懒加载钩子。
  testWidgets('LogWidget triggers loadOlderLogs near top', (tester) async {
    final controller = _FakeLogController()..enabled = true;
    controller.logs.addAll(List.generate(80, (index) => 'INFO: line $index\n'));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 240, child: LogWidget(controller: controller, title: '日志')),
        ),
      ),
    );
    await tester.pump();

    final listView = tester.widget<ListView>(find.byType(ListView));
    listView.controller!.jumpTo(60);
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, 20));
    await tester.pump();

    expect(controller.olderCalls, greaterThanOrEqualTo(1));
  });
```

- [ ] **Step 3: 写失败测试（prepend offset 补偿）**

```dart
  // 中文注释：锁定 prepend 后通过回调补偿 offset，避免视口被打断。
  testWidgets('preserveViewportAfterPrepend compensates offset', (tester) async {
    final controller = _FakeLogController();
    controller.logs.addAll(List.generate(80, (index) => 'INFO: line $index\n'));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 240, child: LogWidget(controller: controller, title: '日志')),
        ),
      ),
    );
    await tester.pump();

    final listView = tester.widget<ListView>(find.byType(ListView));
    listView.controller!.jumpTo(120);
    await tester.pump();

    controller.preserveViewportAfterPrepend?.call(3);
    await tester.pump();

    expect(listView.controller!.offset, greaterThan(120));
  });
```

- [ ] **Step 4: 运行测试确认失败**

Run: `flutter test test/views/overview/overview_log_actions_test.dart -r expanded`
Expected: FAIL，钩子/回调尚未定义。

- [ ] **Step 5: 修改 LogMixin**

在 `log_mixin.dart` 中增加：

```dart
  /// prepend 历史日志后由 LogWidget 保持当前阅读视口。
  void Function(int insertedCount)? preserveViewportAfterPrepend;

  /// 日志行高度估算，用于 prepend 后轻量补偿滚动 offset。
  int get estimatedLogLineHeight => 20;

  /// 是否允许继续加载更早历史日志。
  bool get canLoadOlderLogs => false;

  /// 接近顶部时触发的历史日志加载钩子。
  Future<void> loadOlderLogs() async {}

  /// 当前 UI 与 pending 中是否已经包含该日志文本。
  bool containsVisibleOrPendingLog(String log) {
    return logs.contains(log) || _pendingLogs.contains(log);
  }
```

- [ ] **Step 6: 修改 LogWidget**

`log_widget.dart` 顶部加：

```dart
import 'dart:async';
```

`initState()` 中 `scrollLogs` 注册后加：

```dart
    widget.controller.preserveViewportAfterPrepend = _preserveViewportAfterPrepend;
```

`dispose()` 中 `_scrollController?.dispose();` 前加：

```dart
    if (widget.controller.preserveViewportAfterPrepend == _preserveViewportAfterPrepend) {
      widget.controller.preserveViewportAfterPrepend = null;
    }
```

新增方法：

```dart
  void _preserveViewportAfterPrepend(int insertedCount) {
    if (_scrollController == null || !_scrollController!.hasClients) return;
    final currentOffset = _scrollController!.offset;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController == null || !_scrollController!.hasClients) return;
      final targetOffset = currentOffset +
          insertedCount * widget.controller.estimatedLogLineHeight;
      final maxExtent = _scrollController!.position.maxScrollExtent;
      _scrollController!.jumpTo(targetOffset.clamp(0.0, maxExtent));
    });
  }
```

`_handleUserScroll()` 在 `currentOffset` 后加：

```dart
    // 中文注释：接近顶部时请求更早历史日志；默认 controller 不支持时不会触发。
    if (currentOffset <= 80 && widget.controller.canLoadOlderLogs) {
      unawaited(widget.controller.loadOlderLogs());
    }
```

- [ ] **Step 7: 验证**

Run: `flutter test test/views/overview/overview_log_actions_test.dart -r expanded`
Expected: PASS。

Run: `flutter analyze lib/component/log/log_mixin.dart lib/component/log/log_widget.dart`
Expected: 无新增 warning/error。

- [ ] **Step 8: 展示提交信息等待用户确认**

```text
feat(log): add scroll hooks for historical log loading
```

用户确认后提交。

---

### Task 5: OverviewController 加载 latest / older 历史窗口

**Files:**
- Modify: `lib\controller\overview\overview_controller.dart`
- Modify: `lib\views\overview\overview_view.dart`（library import）
- Test: `test\controller\overview\overview_log_history_test.dart`

**Interfaces:**
- Consumes: `ScriptLogWindow`, `ScriptLogLine`, `LogMixin.containsVisibleOrPendingLog()`。
- Produces: `loadLatestHistoricalLogs()` / `loadOlderHistoricalLogs()` / `loadOlderLogs()` override。

- [ ] **Step 1: 写 controller 测试**

创建 `test\controller\overview\overview_log_history_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/api/script_log_models.dart';
import 'package:oasx/model/script_model.dart';
import 'package:oasx/views/overview/overview_view.dart';

void main() {
  // 中文注释：锁定打开 Logs 时加载最新历史窗口。
  test('loadLatestHistoricalLogs prepends latest history before existing live logs', () async {
    final controller = OverviewController(
      name: 'oas1',
      scriptModelOverride: ScriptModel('oas1'),
      loadLogWindow: (_, {cursor, limitLines = 500}) async {
        expect(cursor, isNull);
        return const ScriptLogWindow(
          lines: [ScriptLogLine(key: 'k1', text: 'INFO: history\n')],
          olderCursor: 'older-token',
          liveCursor: 'live-token',
          reachedStart: false,
        );
      },
    );
    controller.logs.add('INFO: live\n');

    await controller.loadLatestHistoricalLogs();

    expect(controller.logs, ['INFO: history\n', 'INFO: live\n']);
    expect(controller.canLoadOlderLogs, isTrue);
  });

  // 中文注释：锁定历史加载失败时保留已有日志并停止当前失败轮次，避免顶部滚动无限重试。
  test('latest history failure keeps existing logs and disables older loading for that window', () async {
    final controller = OverviewController(
      name: 'oas1',
      scriptModelOverride: ScriptModel('oas1'),
      loadLogWindow: (_, {cursor, limitLines = 500}) async => null,
    );
    controller.logs.add('INFO: live\n');

    await controller.loadLatestHistoricalLogs();

    expect(controller.logs, ['INFO: live\n']);
    expect(controller.canLoadOlderLogs, isFalse);
  });

  // 中文注释：锁定 olderCursor 存在时加载更早窗口并 prepend。
  test('loadOlderHistoricalLogs prepends older window and stops at start', () async {
    final cursors = <String?>[];
    final controller = OverviewController(
      name: 'oas1',
      scriptModelOverride: ScriptModel('oas1'),
      loadLogWindow: (_, {cursor, limitLines = 500}) async {
        cursors.add(cursor);
        if (cursor == null) {
          return const ScriptLogWindow(
            lines: [ScriptLogLine(key: 'latest', text: 'INFO: latest\n')],
            olderCursor: 'older-token',
            liveCursor: null,
            reachedStart: false,
          );
        }
        return const ScriptLogWindow(
          lines: [ScriptLogLine(key: 'older', text: 'INFO: older\n')],
          olderCursor: null,
          liveCursor: null,
          reachedStart: true,
        );
      },
    );

    await controller.loadLatestHistoricalLogs();
    await controller.loadOlderHistoricalLogs();

    expect(cursors, [null, 'older-token']);
    expect(controller.logs, ['INFO: older\n', 'INFO: latest\n']);
    expect(controller.canLoadOlderLogs, isFalse);
  });

  // 中文注释：锁定相同文本但不同 key 的历史行允许共存，相同 key 或已在 UI/pending 中则跳过。
  test('deduplicates by key and visible or pending logs', () async {
    final controller = OverviewController(
      name: 'oas1',
      scriptModelOverride: ScriptModel('oas1'),
      loadLogWindow: (_, {cursor, limitLines = 500}) async {
        return const ScriptLogWindow(
          lines: [
            ScriptLogLine(key: 'k1', text: 'INFO: same\n'),
            ScriptLogLine(key: 'k2', text: 'INFO: same\n'),
            ScriptLogLine(key: 'k3', text: 'INFO: live\n'),
          ],
          olderCursor: null,
          liveCursor: null,
          reachedStart: true,
        );
      },
    );
    controller.logs.add('INFO: live\n');

    await controller.loadLatestHistoricalLogs();

    expect(controller.logs, ['INFO: same\n', 'INFO: same\n', 'INFO: live\n']);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/controller/overview/overview_log_history_test.dart -r expanded`
Expected: FAIL，方法/typedef/import 不存在。

- [ ] **Step 3: 加 imports 与 typedef**

`lib\views\overview\overview_view.dart` 顶部新增：

```dart
import 'package:oasx/api/api_client.dart';
import 'package:oasx/api/script_log_models.dart';
```

`lib\controller\overview\overview_controller.dart` 的 `part of overview;` 后新增：

```dart
typedef LoadScriptLogWindow = Future<ScriptLogWindow?> Function(
  String scriptName, {
  String? cursor,
  int limitLines,
});
```

- [ ] **Step 4: 实现 controller 状态与加载方法**

将 `OverviewController` 改为：

```dart
class OverviewController extends GetxController with LogMixin {
  String name;
  final LoadScriptLogWindow _loadLogWindow;
  final ScriptService? _scriptServiceOverride;
  final ScriptModel? _scriptModelOverride;

  late final scriptService = _scriptServiceOverride ?? Get.find<ScriptService>();
  late final scriptModel = _scriptModelOverride ?? scriptService.findScriptModel(name)!;

  String? _olderCursor;
  bool _reachedStart = false;
  bool _historyLoading = false;
  final Set<String> _historyLineKeys = <String>{};

  OverviewController({
    required this.name,
    LoadScriptLogWindow? loadLogWindow,
    ScriptService? scriptServiceOverride,
    ScriptModel? scriptModelOverride,
  })  : _loadLogWindow = loadLogWindow ??
            ((scriptName, {cursor, limitLines = 500}) => ApiClient()
                .getScriptLogWindow(scriptName, cursor: cursor, limitLines: limitLines)),
        _scriptServiceOverride = scriptServiceOverride,
        _scriptModelOverride = scriptModelOverride;

  @override
  void onInit() {
    super.onInit();
    // 中文注释：打开日志页后加载最新历史窗口，失败时保留现有 WebSocket 实时日志。
    unawaited(loadLatestHistoricalLogs());
  }

  @override
  bool get canLoadOlderLogs =>
      !_reachedStart && !_historyLoading && _olderCursor != null;

  @override
  Future<void> loadOlderLogs() => loadOlderHistoricalLogs();

  Future<void> loadLatestHistoricalLogs() async {
    if (_historyLoading) return;
    _historyLoading = true;
    try {
      final window = await _loadLogWindow(name, limitLines: 500);
      if (window == null) {
        _olderCursor = null;
        _reachedStart = true;
        return;
      }
      _applyHistoricalWindow(window);
    } catch (_) {
      _olderCursor = null;
      _reachedStart = true;
    } finally {
      _historyLoading = false;
    }
  }

  Future<void> loadOlderHistoricalLogs() async {
    if (!canLoadOlderLogs) return;
    final cursor = _olderCursor;
    if (cursor == null) return;
    _historyLoading = true;
    try {
      final window = await _loadLogWindow(name, cursor: cursor, limitLines: 500);
      if (window == null) {
        _olderCursor = null;
        _reachedStart = true;
        return;
      }
      _applyHistoricalWindow(window);
    } catch (_) {
      _olderCursor = null;
      _reachedStart = true;
    } finally {
      _historyLoading = false;
    }
  }

  void _applyHistoricalWindow(ScriptLogWindow window) {
    _olderCursor = window.olderCursor;
    _reachedStart = window.reachedStart;
    _prependUniqueHistoricalLines(window.lines);
  }

  void _prependUniqueHistoricalLines(List<ScriptLogLine> lines) {
    final uniqueLines = <String>[];
    for (final line in lines) {
      if (line.text.isEmpty ||
          _historyLineKeys.contains(line.key) ||
          containsVisibleOrPendingLog(line.text)) {
        continue;
      }
      _historyLineKeys.add(line.key);
      uniqueLines.add(line.text);
    }
    if (uniqueLines.isEmpty) return;
    logs.insertAll(0, uniqueLines);
    preserveViewportAfterPrepend?.call(uniqueLines.length);
  }
```

保留原 `onClose()` 与 `toggleScript()`（`toggleScript()` 仍在启动脚本时 `clearLog()`）。

- [ ] **Step 5: 验证**

Run: `flutter test test/controller/overview/overview_log_history_test.dart -r expanded`
Expected: PASS。

Run: `flutter analyze lib/views/overview/overview_view.dart lib/controller/overview/overview_controller.dart test/controller/overview/overview_log_history_test.dart`
Expected: 无新增 warning/error。

- [ ] **Step 6: 明确历史日志触发边界**

本计划把 `loadLatestHistoricalLogs()` 放在 `OverviewController.onInit()`，原因是当前 `OverviewController` 只在脚本概览/日志容器相关入口按脚本创建（生产构造点为 `lib\controller\ctrl_nav.dart` 的脚本选中逻辑），不会在纯 Stats controller 或后台 service 中创建。若实施时发现 controller 生命周期比 Logs/Overview 更广，应把触发点从 `onInit()` 移到 `Overview`/`OverviewLogsStatsView` 首次 build 后再调用；不得在不可见后台循环请求历史日志。

- [ ] **Step 7: 展示提交信息等待用户确认**

```text
feat(log): load historical windows in overview controller
```

用户确认后提交。

---

### Task 6: 端到端验证与 OpenSpec tasks 勾选

**Files:**
- Modify: `openspec\changes\align-logs-stats-controls\tasks.md`

**Interfaces:**
- Consumes: Tasks 1-5 全部产出。
- Produces: 测试/分析/手动验证记录完成；OpenSpec tasks 勾选。

- [ ] **Step 1: 运行相关测试**

```bash
flutter test test/api/script_log_window_api_test.dart -r expanded
flutter test test/controller/overview/overview_log_history_test.dart -r expanded
flutter test test/views/overview/overview_log_actions_test.dart -r expanded
flutter test test/views/overview/overview_logs_stats_view_test.dart -r expanded
flutter test test/views/overview/stats_overview_panel_test.dart -r expanded
flutter test test/controller/stats/stats_page_controller_test.dart -r expanded
```

Expected: 全部 PASS。

- [ ] **Step 2: 运行静态分析**

```bash
flutter analyze lib/api/api_client.dart lib/api/script_log_models.dart lib/component/log/log_mixin.dart lib/component/log/log_widget.dart lib/controller/overview/overview_controller.dart lib/views/overview/overview_view.dart lib/views/overview/overview_logs_stats_view.dart lib/views/overview/stats_overview_panel.dart
```

Expected: 无新增 warning/error。

- [ ] **Step 3: 手动验证 Windows UI**

Run: `flutter run -d windows`

Expected:
- Logs 打开后显示最近历史日志。
- Logs 向上滚到顶部附近加载更早日志，视口不明显跳动。
- Logs 滚动后切走再回到 Logs，保留现有 saved offset 行为。
- Stats tab 不显示复制、自动滚动、清空按钮。
- 切回 Logs 后三个日志操作按钮恢复。
- Stats 不显示手动刷新按钮，等待自动刷新周期后仍能更新。

- [ ] **Step 4: 勾选 OpenSpec tasks**

把 `openspec\changes\align-logs-stats-controls\tasks.md` 中全部条目改为 `[x]`。

- [ ] **Step 5: 展示提交信息等待用户确认**

```text
chore: mark align logs stats controls tasks complete

历史日志窗口加载、Stats 手动刷新按钮移除、Logs 专属操作按钮显示条件及验证均完成，
同步勾选 OpenSpec tasks 作为收尾记录。
```

用户确认后执行提交。

---

## Self-Review

### Spec coverage

- 打开 Logs 加载最新历史窗口：Task 1 + Task 5。
- 向上滚动懒加载 older：Task 4 + Task 5。
- 到起点停止请求：Task 1 `olderCursor=null` + Task 5 `canLoadOlderLogs=false`。
- 重新打开恢复滚动位置：Task 4 明确保留并测试现有 `savedScrollOffset` 行为。
- prepend 保持视口：Task 4 `preserveViewportAfterPrepend`。
- 历史源不可用 fallback：Task 5 覆盖 null/异常，并设置 reachedStart 避免无限重试。
- Stats 无手动刷新：Task 2。
- 日志操作仅 Logs tab：Task 3。

### Placeholder scan

无 TBD/TODO/implement later。所有任务包含明确文件、接口、测试命令、期望结果和核心代码。

### Type consistency

`ScriptLogWindow` / `ScriptLogLine`、`LoadScriptLogWindow`、`OverviewController` 构造参数、`LogMixin` 钩子、`Overview.showLogActions` 的命名在所有任务中保持一致。
