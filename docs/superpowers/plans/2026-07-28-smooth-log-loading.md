# 平滑日志加载 Implementation Plan

> **For agentic workers:** Implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 消除选中脚本 / 打开 Logs 标签时的卡顿。归因实测证实瓶颈是「日志区从顶部滚到底部」这一次滚动（`SliverList` 无固定行高时逐行构建 470/500 行），而非日志插入。修法：给列表加 `prototypeItem` 提供固定行高、超长距离滚动改为直接跳转；另外加载期间显示占位动画。

**Architecture:** `LogContent` 的 `ListView.builder` 增加 `prototypeItem`（结构与真实行一致的等高原型），使 `SliverList` 把 offset ↔ index 变成常数时间换算；`_scrollLogs` 在滚动距离超过 3 个视口高度时改走 `jumpTo` 而非 `animateTo`，规避动画途经全部行的逐行构建；`LogMixin` 新增 `historyLoading`（RxBool），`OverviewController` 把私有 `bool _historyLoading` 换成它，`LogContent` 在「加载中且 logs 为空」时用 `Stack` 把 spinner **叠加**在列表之上（列表常驻，保证 `ScrollController` 始终 attach）。历史连续性状态机、插入方式、窗口行数全部不变。

**Tech Stack:** Flutter / Dart，GetX（`GetxController` + `LogMixin`、`RxList` / `RxBool`、`Obx`），`flutter_test`（unit + widget），`styled_widget`，`easy_rich_text`。

## Global Constraints

- 设计依据：`docs/superpowers/specs/2026-07-28-smooth-log-loading-design.md`。本计划不得偏离该 spec 的非目标：**不改后端协议与 `ApiClient` 接口、不改实时日志 WebSocket 通道与 pending buffer 机制、不改历史连续性状态机语义与插入方式、不调整 `limitLines`（保持 500）、不做分批插入、不缓存 pattern 列表**。
- 归因数据见 spec「归因实测」表。若实施后手动验证仍卡顿，**先重新归因再改方案**，不要凭猜测叠加优化。
- 占位动画只在 `historyLoading.value == true && logs.isEmpty` 时显示，使用 `SizedBox(width: 28, height: 28)` 包 `CircularProgressIndicator(strokeWidth: 2.6)`（与 `stats_overview_panel.dart:277-281` 完全一致），**不加任何文案**（避免新增 i18n key）。**必须叠加而非替换 `ListView`** —— 替换会导致 `ScrollController` 无 clients，吞掉 `initState` 的一次性滚底回调与首批视口补偿。
- 所有新增 / 修改的 Dart 代码必须写**中文注释**；本次改动导致原有注释不准确时同步更新，未受影响的注释不要改动。
- 手术式修改：只改本计划列出的位置，不顺手重排格式、不改动相邻无关代码（仓库整体 `dart format` 本就不完全合规，不要做全文件重排）。
- **提交前必须先把拟定的 commit message 展示给用户审查**，用户确认或修改后才执行 `git commit`。计划中的 `git commit` 命令是拟定内容，不是可直接执行的授权。
- 当前分支：`feature/20260627/align-logs-stats-controls`，直接在该分支继续提交，不使用 git worktree。
- `lib/controller/overview/overview_controller.dart` 是 `part of overview`，**不能单独 analyze**（会误报 30 条 undefined 名称，含 `logs`、`clearLog`、`ScriptLogWindow`、`ScriptState` 等）。必须与库入口一起分析：`flutter analyze lib/views/overview/overview_view.dart lib/component/log`。
- 测试中禁止对含 `CircularProgressIndicator` 的界面调用 `tester.pumpAndSettle()`——它是无限循环动画，会导致测试挂起。用 `await tester.pump()` 推进。
- `flutter analyze` 全仓库当前有 **12 条既有问题**（`store_disk.dart` 的 `unnecessary_non_null_assertion`、多处 `deprecated_member_use`、`stats_page_controller_test.dart:1` 的 `depend_on_referenced_packages` 等），与本次改动无关，不要顺手修。判定标准是「不新增问题」，不是 `No issues found!`。

---

## File Structure

| 文件 | 责任 | 本次改动 |
| --- | --- | --- |
| `lib/component/log/log_widget.dart` | 日志 UI（`_scrollLogs` 滚动、`_preserveViewportAfterPrepend` 视口补偿、`LogContent` 内容区） | `ListView.builder` 加 `prototypeItem`（Task 1）；`_scrollLogs` 加长距离跳转（Task 2）；`LogContent.build` 加占位叠加层（Task 3） |
| `lib/component/log/log_mixin.dart` | 日志数据与行为 mixin | 新增 `historyLoading` RxBool（Task 3） |
| `lib/controller/overview/overview_controller.dart` | 历史日志窗口加载状态机（`part of overview`） | 私有 `_historyLoading` → mixin 的 RxBool（Task 4） |
| `test/component/log/log_widget_scroll_test.dart` | **新建**：固定行高、长距离跳转、占位三态的 widget 测试 | Task 1-3 |
| `test/controller/overview/overview_log_history_test.dart` | 历史加载状态机单元测试（现有 **9** 个用例保持不变） | 新增 `historyLoading` 时序 2 个用例（Task 4） |

---

## Task 1: 日志列表固定行高（`prototypeItem`）

归因证实的主要修复项之一：`SliverList` 无固定行高时，`jumpTo`/视口补偿必须从头逐行累加高度定位目标 offset，导致构建 470/500 行。给定等高原型后降到约 25 行。

**Files:**
- Modify: `lib/component/log/log_widget.dart:320-334`（`LogContent.build` 的 `ListView.builder`）
- Test: `test/component/log/log_widget_scroll_test.dart`（新建）

**Interfaces:**
- Consumes: `LogContent._selectStyle(BuildContext)`、`LogContent._buildPatterns()`（现有私有方法）
- Produces: `LogContent` 的 `ListView` 带非 null `prototypeItem`，结构与真实行**同构**（`Padding(vertical: 1)` + `EasyRichText(selectable: true, maxLines: 1)` + 同一 `defaultStyle` + 同一 `patternList`），且原型文本**命中高亮 pattern**。实测行高矩阵（widget 测试）：`titleSmall` 下 `Text` 原型 / 无 pattern `EasyRichText` / 命中 pattern 真实行 = 22 / 22 / 22；**`bodySmall`（portrait）下 = 18 / 18 / 22** —— `SliverPrototypeExtentList` 用紧约束把每行压到原型高度，原型偏矮会裁切文字，故原型必须取命中 pattern 的最高行形态。Task 2 的长距离 `jumpTo` 依赖本任务才有性能收益。

- [ ] **Step 1: 新建 widget 测试文件（失败测试）**

创建 `test/component/log/log_widget_scroll_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:oasx/component/log/log_mixin.dart';
import 'package:oasx/component/log/log_widget.dart';

/// 中文注释：LogMixin 桩 controller；不注册到 Get，避免 onInit 启动日志刷新计时器。
class _FakeLogController extends GetxController with LogMixin {}

/// 中文注释：统一把 LogWidget 挂到固定高度容器，保证 ListView 有可滚动视口。
Future<void> _pumpLogWidget(WidgetTester tester, LogMixin controller) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 400,
          child: LogWidget(controller: controller, title: '日志'),
        ),
      ),
    ),
  );
  // 中文注释：占位是无限循环动画，只能 pump 推进，不可 pumpAndSettle（会挂起）。
  await tester.pump();
}

/// 中文注释：从挂载的 LogWidget 取出 prototypeItem 与第 0 行真实 widget，
/// 并排渲染实测两者高度一致。原型偏矮时 SliverPrototypeExtentList 的紧约束
/// 会把真实行压扁裁切文字（实测 bodySmall 下命中 pattern 的行 22px、
/// 普通 Text 原型只有 18px）。
Future<void> _expectPrototypeMatchesRow(WidgetTester tester) async {
  final controller = _FakeLogController();
  // 中文注释：行首 INFO + 时间戳命中高亮 pattern，是两种 orientation 下最高的行形态。
  controller.logs.add('INFO: 12:00:00.000 line\n');
  await _pumpLogWidget(tester, controller);

  final listView = tester.widget<ListView>(find.byType(ListView));
  final prototype = listView.prototypeItem;
  expect(prototype, isNotNull);
  final delegate = listView.childrenDelegate as SliverChildBuilderDelegate;

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            KeyedSubtree(key: const Key('proto'), child: prototype!),
            KeyedSubtree(
              key: const Key('row'),
              child: Builder(builder: (c) => delegate.builder(c, 0)!),
            ),
          ],
        ),
      ),
    ),
  );

  final protoHeight = tester.getSize(find.byKey(const Key('proto'))).height;
  final rowHeight = tester.getSize(find.byKey(const Key('row'))).height;
  expect(protoHeight, rowHeight);
}

void main() {
  // 中文注释：锁定列表提供固定行高原型。无它则 SliverList 定位 offset 时
  // 需从头逐行累加高度，实测 500 行会构建 470 行、单帧冻结数百毫秒。
  testWidgets('log list declares a prototype item for fixed row extent',
      (tester) async {
    final controller = _FakeLogController();
    controller.logs.addAll(List.generate(50, (i) => 'INFO: line $i\n'));

    await _pumpLogWidget(tester, controller);

    final listView = tester.widget<ListView>(find.byType(ListView));
    expect(listView.prototypeItem, isNotNull);
  });

  // 中文注释：landscape（titleSmall）下原型与真实行等高。
  testWidgets('prototype height matches real row in landscape',
      (tester) async {
    await _expectPrototypeMatchesRow(tester);
  });

  // 中文注释：portrait（bodySmall）下原型与真实行等高——该样式下
  // 命中 pattern 的行（22px）比普通 Text（18px）高，最容易暴露失配。
  testWidgets('prototype height matches real row in portrait',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _expectPrototypeMatchesRow(tester);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/component/log/log_widget_scroll_test.dart`
Expected: FAIL —— 3 个用例都失败：第 1 个 `Expected: not null / Actual: <null>`；两个高度用例在 `expect(prototype, isNotNull)` 处失败。

- [ ] **Step 3: 给 ListView.builder 加 prototypeItem**

编辑 `lib/component/log/log_widget.dart` 的 `LogContent.build`，在 `ListView.builder` 的 `controller:` 之后、`itemCount:` 之前插入：

```dart
        child: Obx(() => ListView.builder(
              controller: scrollController,
              // 中文注释：给出等高原型让 SliverList 用常数时间换算 offset↔index，
              // 否则跳转/视口补偿要从头逐行累加高度（实测 500 行滚到底会构建
              // 470 行、单帧冻结数百毫秒）。原型必须与真实行同构且命中高亮
              // pattern：实测 bodySmall 下命中行高 22px、未命中行与普通 Text
              // 仅 18px，取最高形态保证任何真实行不会高于原型而被裁切。
              prototypeItem: Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: EasyRichText(
                  'INFO: 00:00:00.000 prototype\n',
                  patternList: _buildPatterns(),
                  selectable: true,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  defaultStyle: _selectStyle(context),
                ),
              ),
              itemCount: controller.logs.length,
```

（原型与真实行唯一的差别是文本内容；`selectable`、`patternList`、`defaultStyle` 必须与 `itemBuilder` 完全一致——行高由这三者共同决定，实测普通 `Text` 或未命中 pattern 的 `EasyRichText` 在 `bodySmall` 下都会矮 4px。）

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/component/log/log_widget_scroll_test.dart`
Expected: PASS（3 个用例全绿）。

- [ ] **Step 5: 运行既有日志 / overview 测试确认未回归**

Run: `flutter test test/component/log test/views/overview`
Expected: PASS。注意 `overview_log_actions_test.dart` 的 `restores saved scroll offset`（断言 offset == 120）与 `preserveViewportAfterPrepend compensates offset`（断言 offset > 120）**与行高无关**——前者回读 `jumpTo` 的固定值，后者按真实布局高度差计算补偿；行高正确性由本 Task 的两个高度一致性用例锁定，不依赖这两个既有用例。

- [ ] **Step 6: 静态分析**

Run: `flutter analyze lib/component/log test/component/log/log_widget_scroll_test.dart`
Expected: 无新增问题。

- [ ] **Step 7: 提交（先向用户展示 commit message 并获确认）**

```bash
git add lib/component/log/log_widget.dart test/component/log/log_widget_scroll_test.dart
git commit -m "perf(log): 日志列表声明等高原型，避免滚动定位时逐行构建"
```

---

## Task 2: 超长距离滚动改为直接跳转

归因证实的另一半：`_scrollLogs` 默认走 `animateTo`，时长按 `sqrt(distance)*10` 最长 1000ms，动画途经每一行都会被 `SliverList` 构建。实测 500 行滚到底构建 470 行、37 帧超 16ms，用户感知为持续约 1 秒的卡顿。

**Files:**
- Modify: `lib/component/log/log_widget.dart:126-135`（`_scrollLogs` 内计算 `distance` 之后、计算 `animateMs` 之前）
- Test: `test/component/log/log_widget_scroll_test.dart`（新增 2 个用例）

**Interfaces:**
- Consumes: `ScrollPosition.viewportDimension`（Flutter 内置）；Task 1 的 `prototypeItem`（跳转的性能收益依赖它）
- Produces: `_scrollLogs` 行为契约 —— 滚动距离 > 3 × 视口高度时同帧 `jumpTo` 到位；距离在阈值以内保持原 `animateTo` 平滑动画。`isJump: true` 的既有短路路径不变。

- [ ] **Step 1: 追加失败测试**

在 `test/component/log/log_widget_scroll_test.dart` 的 `main()` 末尾追加：

```dart
  // 中文注释：锁定长距离滚动直接跳转。走 animateTo 会让 SliverList 构建途经的
  // 每一行（实测 470/500 行、37 帧掉帧），这是打开 Logs 卡顿的主因。
  testWidgets('long distance scroll jumps instead of animating',
      (tester) async {
    final controller = _FakeLogController();
    controller.logs.addAll(List.generate(500, (i) => 'INFO: line $i\n'));

    await _pumpLogWidget(tester, controller);

    final scroll =
        tester.widget<ListView>(find.byType(ListView)).controller!;
    scroll.jumpTo(0);
    await tester.pump();

    controller.scrollLogs?.call(force: true, scrollOffset: -1);
    // 中文注释：一帧执行 postFrameCallback，第二帧观察结果。
    await tester.pump();
    await tester.pump();

    expect(scroll.offset, scroll.position.maxScrollExtent);
  });

  // 中文注释：锁定短距离仍走平滑动画，实时日志追尾体验不退化。
  testWidgets('short distance scroll still animates', (tester) async {
    final controller = _FakeLogController();
    // 中文注释：40 行总高约 880px，必有可滚动距离，又小于 3 个视口
    //（约 936px）的跳转阈值，落在动画区间。
    controller.logs.addAll(List.generate(40, (i) => 'INFO: line $i\n'));

    await _pumpLogWidget(tester, controller);

    final scroll =
        tester.widget<ListView>(find.byType(ListView)).controller!;
    final target = scroll.position.maxScrollExtent;
    // 中文注释：显式断言前置条件，行数不足以滚动时测试应失败而非静默通过。
    expect(target, greaterThan(0),
        reason: '行数不足以产生可滚动距离，需增加行数');
    scroll.jumpTo(0);
    await tester.pump();

    controller.scrollLogs?.call(force: true, scrollOffset: -1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    // 中文注释：动画进行中——已启动但未到终点。
    expect(scroll.offset, greaterThan(0));
    expect(scroll.offset, lessThan(target));
  });
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/component/log/log_widget_scroll_test.dart --plain-name "long distance scroll jumps instead of animating"`
Expected: FAIL —— 长距离用例的 offset 远小于 `maxScrollExtent`（动画刚起步）。短距离用例此时应已通过（现状就是动画）。

- [ ] **Step 3: 在 _scrollLogs 增加长距离跳转分支**

编辑 `lib/component/log/log_widget.dart` 的 `_scrollLogs`，在 `final double distance = (targetPos - currentPos).abs();` 之后、`int animateMs = ...` 之前插入：

```dart
      final double currentPos = _scrollController!.offset;
      final double distance = (targetPos - currentPos).abs();
      // 中文注释：超长距离动画会让 SliverList 把途经的每一行都构建一遍
      // （实测 500 行滚到底构建 470 行、37 帧掉帧），直接跳转规避。
      // 阈值用视口相对量以自适应窗口尺寸；阈值内保留平滑动画不影响追尾体验。
      // 无需 animateTo 的 whenComplete 底部矫正：跳转同步完成不存在动画期间
      // extent 增长的窗口，之后的追加由 50ms 计时器的 scrollLogs / prepend 补偿覆盖。
      if (distance > _scrollController!.position.viewportDimension * 3) {
        _scrollController!.jumpTo(targetPos);
        return;
      }
```

- [ ] **Step 4: 运行测试确认全部通过**

Run: `flutter test test/component/log/log_widget_scroll_test.dart`
Expected: PASS（5 个用例全绿）。

- [ ] **Step 5: 运行既有日志 / overview 测试确认未回归**

Run: `flutter test test/component/log test/views/overview`
Expected: PASS。`LogWidget triggers loadOlderLogs near top` 用 `drag` 手动滚动、不经 `_scrollLogs`，不受影响。

- [ ] **Step 6: 静态分析**

Run: `flutter analyze lib/component/log test/component/log/log_widget_scroll_test.dart`
Expected: 无新增问题。

- [ ] **Step 7: 提交（先向用户展示 commit message 并获确认）**

```bash
git add lib/component/log/log_widget.dart test/component/log/log_widget_scroll_test.dart
git commit -m "perf(log): 超长距离滚动改为跳转，避免动画途中逐行构建"
```

---

## Task 3: LogMixin 加载状态 + LogContent 占位叠加层

**Files:**
- Modify: `lib/component/log/log_mixin.dart:28`（在 `collapseLog` 声明之后插入新状态）
- Modify: `lib/component/log/log_widget.dart`（`LogContent.build` 的 `Obx`，Task 1 已改过一次）
- Test: `test/component/log/log_widget_scroll_test.dart`（新增 4 个用例）

**Interfaces:**
- Consumes: 无（`historyLoading` 由本任务产出，Task 4 才有写入方）
- Produces:
  - `LogMixin.historyLoading` → `RxBool`，默认 `false`。子类通过 `historyLoading.value = true/false` 维护；UI 通过 `controller.historyLoading.value` 读取。
  - 渲染契约：`historyLoading.value == true && logs.isEmpty` 时在列表之上叠加 `Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.6)))`，**`ListView` 仍在树上、`ScrollController` 保持 attach**；其余情况只渲染列表。

- [ ] **Step 1: 追加失败测试**

在 `test/component/log/log_widget_scroll_test.dart` 的 `main()` 末尾追加：

```dart
  // 中文注释：锁定首次加载（logs 为空）期间显示整区域占位。
  testWidgets('shows placeholder spinner while loading with empty logs',
      (tester) async {
    final controller = _FakeLogController();
    controller.historyLoading.value = true;

    await _pumpLogWidget(tester, controller);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  // 中文注释：锁定占位期间 ListView 仍在树上、ScrollController 保持 attach。
  // 若占位替换掉 ListView，hasClients 为 false 会吞掉 initState 那次一次性的
  // 滚底 postFrameCallback 与首批历史的视口补偿，用户会停在最老的日志行。
  testWidgets('keeps scroll controller attached while placeholder shows',
      (tester) async {
    final controller = _FakeLogController();
    controller.historyLoading.value = true;

    await _pumpLogWidget(tester, controller);

    expect(find.byType(ListView), findsOneWidget);
    final scroll =
        tester.widget<ListView>(find.byType(ListView)).controller!;
    expect(scroll.hasClients, isTrue);
  });

  // 中文注释：锁定已有日志时加载不显示占位，避免懒加载/重建遮挡正在阅读的内容。
  testWidgets('keeps log list visible without spinner when logs exist',
      (tester) async {
    final controller = _FakeLogController();
    controller.logs.addAll(List.generate(20, (i) => 'INFO: line $i\n'));
    controller.historyLoading.value = true;

    await _pumpLogWidget(tester, controller);

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(ListView), findsOneWidget);
  });

  // 中文注释：锁定加载完成后占位消失。
  testWidgets('removes placeholder after loading finishes', (tester) async {
    final controller = _FakeLogController();
    controller.historyLoading.value = true;

    await _pumpLogWidget(tester, controller);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    controller.logs.addAll(List.generate(5, (i) => 'INFO: line $i\n'));
    controller.historyLoading.value = false;
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(ListView), findsOneWidget);
  });
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/component/log/log_widget_scroll_test.dart`
Expected: 编译失败，报 `The getter 'historyLoading' isn't defined for the type '_FakeLogController'`。

- [ ] **Step 3: 在 LogMixin 新增 historyLoading**

编辑 `lib/component/log/log_mixin.dart`，在 `collapseLog` 之后插入：

```dart
  /// collapse log content
  final collapseLog = false.obs;

  /// 历史日志加载中；由支持历史加载的子类维护，UI 据此显示加载占位动画。
  final historyLoading = false.obs;
```

- [ ] **Step 4: 运行测试确认进度**

Run: `flutter test test/component/log/log_widget_scroll_test.dart`
Expected: 编译通过。Task 1/2 的前 5 个用例 PASS；新增 4 个中：`shows placeholder spinner...` 与 `removes placeholder...` 的 spinner 断言 FAIL（`Found 0 widgets with type "CircularProgressIndicator"`），`keeps scroll controller attached...` 碰巧 PASS（现状本就常驻 `ListView`），`keeps log list visible...` PASS。

- [ ] **Step 5: 在 LogContent 增加占位叠加层**

编辑 `lib/component/log/log_widget.dart` 的 `LogContent.build`，把 Task 1 改造后的 `child: Obx(() => ListView.builder(...).paddingAll(10)),` 整段替换为：

```dart
        child: Obx(() {
          final list = ListView.builder(
            controller: scrollController,
            // 中文注释：给出等高原型让 SliverList 用常数时间换算 offset↔index，
            // 否则跳转/视口补偿要从头逐行累加高度（实测 500 行滚到底会构建
            // 470 行、单帧冻结数百毫秒）。原型必须与真实行同构且命中高亮
            // pattern：实测 bodySmall 下命中行高 22px、未命中行与普通 Text
            // 仅 18px，取最高形态保证任何真实行不会高于原型而被裁切。
            prototypeItem: Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: EasyRichText(
                'INFO: 00:00:00.000 prototype\n',
                patternList: _buildPatterns(),
                selectable: true,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                defaultStyle: _selectStyle(context),
              ),
            ),
            itemCount: controller.logs.length,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: EasyRichText(
                controller.logs[index],
                patternList: _buildPatterns(),
                selectable: true,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                defaultStyle: _selectStyle(context),
              ),
            ),
          ).paddingAll(10);
          // 中文注释：仅在没有任何日志可展示时显示占位；懒加载更早窗口 /
          // stale 重建时用户可能正在阅读，不遮挡已有列表。
          if (!controller.historyLoading.value || controller.logs.isNotEmpty) {
            return list;
          }
          // 中文注释：占位叠加而非替换列表——替换会让 ScrollController 失去
          // clients，吞掉 initState 的一次性滚底回调与首批历史的视口补偿。
          // 尺寸与 StatsOverviewPanel 的加载态一致（28×28 + strokeWidth 2.6）。
          return Stack(
            children: [
              list,
              const Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.6),
                ),
              ),
            ],
          );
        }),
```

- [ ] **Step 6: 运行测试确认全部通过**

Run: `flutter test test/component/log/log_widget_scroll_test.dart`
Expected: PASS（9 个用例全绿）。

- [ ] **Step 7: 运行既有日志 / overview 测试确认未回归**

Run: `flutter test test/component/log test/views/overview`
Expected: PASS。注意 `overview_log_actions_test.dart` 前两个用例走 `setUp` 里 `Get.put` 的**真实 `OverviewController`**，其 `onInit` 会调 `loadLatestHistoricalLogs()`；但此刻 `OverviewController` 仍用私有 `_historyLoading`，不会写 `historyLoading`，故走列表分支。（Task 4 之后它会写入，届时因该 fake loader 在首个 await 处已让 microtask 排空、`historyLoading` 已复位，且这两个用例只断言图标，仍应通过。）

- [ ] **Step 8: 静态分析**

Run: `flutter analyze lib/component/log test/component/log/log_widget_scroll_test.dart`
Expected: 无新增问题。

- [ ] **Step 9: 提交（先向用户展示 commit message 并获确认）**

```bash
git add lib/component/log/log_mixin.dart lib/component/log/log_widget.dart test/component/log/log_widget_scroll_test.dart
git commit -m "feat(log): 日志区加载中叠加整区域占位动画"
```

---

## Task 4: OverviewController 改用可观察加载状态

**Files:**
- Modify: `lib/controller/overview/overview_controller.dart:23-26`（删除私有字段）、`:60-62`（`canLoadOlderLogs`）、`:92`（`_rebuildStaleHistory` 守卫）、`:111-127`（`loadLatestHistoricalLogs`）、`:135-150`（`loadOlderHistoricalLogs`）
- Modify: `test/controller/overview/overview_log_history_test.dart:166`（注释引用了改名后的 `_historyLoading`）
- Test: `test/controller/overview/overview_log_history_test.dart`（新增 2 个用例）

**Interfaces:**
- Consumes: `LogMixin.historyLoading`（`RxBool`，Task 3 产出）
- Produces:
  - `OverviewController` 不再持有 `bool _historyLoading`，全部改读写 `historyLoading.value`（共 8 处：原 26/61/92/111/112/126/135/149 行）。
  - 状态时序契约：`loadLatestHistoricalLogs()` / `loadOlderHistoricalLogs()` 进入时置 `historyLoading.value = true`，在 `finally` 中复位为 `false`（成功与失败路径一致）。
  - `canLoadOlderLogs` 语义不变：`!historyLoading.value && (_historyStale || (!_reachedStart && _olderCursor != null))`。

- [ ] **Step 1: 追加失败测试**

在 `test/controller/overview/overview_log_history_test.dart` 的 `main()` 末尾（`clearLog resets history continuity for reload` 用例之后、闭合 `}` 之前）追加：

```dart
  // 中文注释：锁定 historyLoading 在加载期间为 true、完成后复位，UI 占位据此显示/消失。
  test('historyLoading toggles around latest window load', () async {
    final gate = Completer<ScriptLogWindow?>();
    final controller = OverviewController(
      name: 'oas1',
      scriptModelOverride: ScriptModel('oas1'),
      loadLogWindow: (_, {cursor, limitLines = 500}) => gate.future,
    );

    expect(controller.historyLoading.value, isFalse);

    final future = controller.loadLatestHistoricalLogs();
    expect(controller.historyLoading.value, isTrue);

    gate.complete(const ScriptLogWindow(
      lines: [ScriptLogLine(key: 'k1', text: 'INFO: history\n')],
      olderCursor: null,
      liveCursor: null,
      reachedStart: true,
    ));
    await future;

    expect(controller.historyLoading.value, isFalse);
    expect(controller.logs, ['INFO: history\n']);
  });

  // 中文注释：锁定加载抛异常时 historyLoading 同样复位，占位动画不会卡死。
  // 用 gate 确认异常前确实置位过，避免写成「任何实现下都通过」的空转测试。
  test('historyLoading resets when loading throws', () async {
    final gate = Completer<ScriptLogWindow?>();
    final controller = OverviewController(
      name: 'oas1',
      scriptModelOverride: ScriptModel('oas1'),
      loadLogWindow: (_, {cursor, limitLines = 500}) => gate.future,
    );

    final future = controller.loadLatestHistoricalLogs();
    expect(controller.historyLoading.value, isTrue);

    gate.completeError(StateError('boom'));
    await future;

    expect(controller.historyLoading.value, isFalse);
    expect(controller.canLoadOlderLogs, isFalse);
  });
```

（文件顶部已 `import 'dart:async';`，`Completer` 可直接使用。）

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/controller/overview/overview_log_history_test.dart --plain-name "historyLoading toggles around latest window load"`
Expected: FAIL —— `Expected: <true> Actual: <false>`（`historyLoading` 是 Task 3 引入的、`OverviewController` 尚未写入的 RxBool）。

- [ ] **Step 3: 替换 OverviewController 的加载状态字段**

编辑 `lib/controller/overview/overview_controller.dart`，做 5 处替换。

3.1 删除私有字段（原第 23-26 行），把：

```dart
  // 中文注释：历史窗口游标与加载状态；reachedStart 后不再请求更早窗口。
  String? _olderCursor;
  bool _reachedStart = false;
  bool _historyLoading = false;
```

改为：

```dart
  // 中文注释：历史窗口游标；reachedStart 后不再请求更早窗口。
  // 加载中状态用 LogMixin 的 historyLoading（RxBool），UI 据此显示占位动画。
  String? _olderCursor;
  bool _reachedStart = false;
```

3.2 `canLoadOlderLogs`：

```dart
  // 中文注释：存在更早窗口或历史已失效待重建，且没有进行中的请求时允许加载。
  @override
  bool get canLoadOlderLogs =>
      !historyLoading.value &&
      (_historyStale || (!_reachedStart && _olderCursor != null));
```

3.3 `_rebuildStaleHistory` 的守卫：

```dart
  Future<void> _rebuildStaleHistory() async {
    if (historyLoading.value) return;
```

3.4 `loadLatestHistoricalLogs` 的守卫、置位与复位：

```dart
  Future<void> loadLatestHistoricalLogs() async {
    if (historyLoading.value) return;
    historyLoading.value = true;
    try {
```

以及该方法的 `finally`：

```dart
    } finally {
      historyLoading.value = false;
    }
```

3.5 `loadOlderHistoricalLogs` 的置位与复位：

```dart
    historyLoading.value = true;
    try {
```

以及该方法的 `finally`：

```dart
    } finally {
      historyLoading.value = false;
    }
```

- [ ] **Step 4: 更新失效注释**

`test/controller/overview/overview_log_history_test.dart:166` 的注释提到 `_historyLoading`，改为：

```dart
    // 中文注释：latest 一次 + older 一次；第二次 older 触发被 historyLoading 拒绝。
```

- [ ] **Step 5: 运行 controller 测试确认通过**

Run: `flutter test test/controller/overview/overview_log_history_test.dart`
Expected: PASS（原 9 个 + 新增 2 个 = **11** 个用例全绿）。

- [ ] **Step 6: 运行既有日志 / overview 测试确认未回归**

Run: `flutter test test/component/log test/views/overview`
Expected: PASS（含 `overview_log_actions_test.dart` 前两个用例，见 Task 3 Step 7 的说明）。

- [ ] **Step 7: 静态分析**

Run: `flutter analyze lib/views/overview/overview_view.dart lib/component/log test/controller/overview/overview_log_history_test.dart`
Expected: 无新增问题（`overview_controller.dart` 作为 part 文件必须随库入口 `overview_view.dart` 一起分析）。

- [ ] **Step 8: 提交（先向用户展示 commit message 并获确认）**

```bash
git add lib/controller/overview/overview_controller.dart test/controller/overview/overview_log_history_test.dart
git commit -m "refactor(log): 历史加载状态改为可观察，驱动加载占位动画"
```

---

## Task 5: 全量验证与手动确认

**Files:**
- 无代码改动（若验证发现问题，回到对应 Task 修复）

**Interfaces:**
- Consumes: Task 1-4 的全部产出
- Produces: 可交付的构建 + 手动验证结论

- [ ] **Step 1: 全量单元 / widget 测试**

Run: `flutter test`
Expected: 全部 PASS，无 pending timer / ticker 报错。

- [ ] **Step 2: 全量静态分析**

Run: `flutter analyze`
Expected: **12 issues found.**（与改动前一致的既有问题；若数量增加，定位新增项并修复。不要顺手修既有问题）

- [ ] **Step 3: 手动验证（Windows 桌面）**

Run: `flutter run -d windows`

逐项确认：
1. 选中一个有历史日志的脚本 / 打开 Logs 标签：日志区先出现居中转圈占位，随后日志出现并**直接定位到底部最新日志**，界面无明显卡顿、无持续掉帧。
2. **确认没有停在最老的日志行**（这是占位若替换掉 `ListView` 会产生的回归）。对**未运行**的脚本尤其要确认，它没有实时日志来纠正位置。
3. 日志填充完成后占位消失，列表可正常滚动、可选中文本，行间距与改动前一致（验证 `prototypeItem` 行高正确）。**另把窗口拉成竖长（portrait）再看一遍**：文字不得被裁切或行间重叠；未命中高亮 pattern 的行允许比改动前略松（原型取最高行形态所致）。
4. 向上滚动到接近顶部触发加载更早日志：**不出现整区域占位遮挡**，阅读位置保持稳定，更早日志出现在上方且时间线连续。
5. 运行中脚本的实时日志在加载期间与加载后都能持续追加到底部，**追尾滚动仍是平滑动画**（验证 3 倍视口阈值没有误伤短距离滚动）。
6. 点击清空按钮后再上滚触发重载：日志重新出现且顺序正确、无重复行。
7. 切到 Stats 标签再切回 Logs：日志操作按钮正常隐藏/恢复，日志内容与滚动位置符合预期。

- [ ] **Step 4: 记录验证结果**

把手动验证逐项结果反馈给用户。任一项不符合预期则定位到对应 Task 修复后重新执行 Step 1-3。**若第 1 项仍卡顿，不要凭猜测叠加优化——先用 `flutter run --profile` + DevTools timeline 重新归因。**

- [ ] **Step 5: 可选打包（用户要求时执行）**

Run: `flutter build windows --release`
Expected: `Building Windows application... done`，产物在 `build/windows/x64/runner/Release/`。

---

## Self-Review

**1. Spec coverage**

| spec 章节 / 要求 | 对应 Task |
| --- | --- |
| §架构 1 `prototypeItem` 固定行高 | Task 1 Step 3 |
| §架构 1 原型与真实行同构、命中 pattern 的最高行形态 | Task 1 Step 3（同 `patternList` / `selectable` / `defaultStyle`，文本命中 INFO + 时间戳） |
| §架构 2 距离 > 3×视口改 `jumpTo` | Task 2 Step 3 |
| §架构 2 阈值用视口相对量 | Task 2 Step 3（`position.viewportDimension * 3`） |
| §架构 2 阈值内保留动画 | Task 2 Step 1 第 2 个用例 + Step 3（提前 return 不影响后续 `animateTo`） |
| §架构 3 `LogMixin.historyLoading` RxBool | Task 3 Step 3 |
| §架构 3 占位**叠加**而非替换、`ListView` 常驻 | Task 3 Step 5 + Step 1 第 2 个用例（`hasClients` 断言） |
| §架构 3 仅 `logs` 为空时显示 | Task 3 Step 5 + Step 1 第 3 个用例 |
| §架构 3 spinner 与 Stats 一致、无文案 | Task 3 Step 5（`SizedBox(28×28)` + `strokeWidth: 2.6`，与 `stats_overview_panel.dart:277-281` 完全一致） |
| §架构 3 `OverviewController` 私有字段改 RxBool | Task 4 Step 3 |
| §架构 4 错误处理不变、`finally` 复位 | Task 4 Step 3.4/3.5 + Step 1 第 2 个用例 |
| §测试 `prototypeItem` 非 null | Task 1 Step 1 |
| §测试 原型与真实行等高（landscape + portrait 双 orientation） | Task 1 Step 1（`_expectPrototypeMatchesRow`） |
| §测试 大距离一帧到底 / 小距离仍动画 | Task 2 Step 1 |
| §测试 占位三态 + `hasClients` | Task 3 Step 1（4 个用例） |
| §测试 现有 9 个用例断言不变 | Task 4 Step 5 |
| §测试 `historyLoading` 时序 + 失败复位（gate 形式） | Task 4 Step 1 |
| §手动验证 三项 | Task 5 Step 3（第 1、4、5 项，另补 4 项回归检查含「不停在最老行」） |

无遗漏。已放弃的分批插入与窗口行数调整在 spec「已放弃的初版方案」中记录了理由，本计划不含对应 Task。

**2. Placeholder scan**

无 TBD / TODO / "类似 Task N" / "适当处理错误" 之类占位；每个改代码的 Step 都给出完整代码块与确切文件位置。

**3. Type consistency**

- `historyLoading` 在 Task 3（声明 + widget 测试）、Task 4（读写）中命名一致，类型均为 `RxBool`，访问统一走 `.value`。
- `prototypeItem` 类型为 `Widget?`（`ListView.builder` 命名参数），Task 1 Step 3 传与真实行同构的 `Padding + EasyRichText`，Task 3 Step 5 重写 `Obx` 时原样保留。
- `_scrollLogs` 签名不变（`{isJump = false, force = false, scrollOffset = -1}`），仅在方法体内插入分支。
- `preserveViewportAfterPrepend`（`void Function(int)?`）、`onUiLogsTrimmedFromHead(int)`、`containsVisibleOrPendingLog(String)`、`_historyPrefixCount`、`_historyStale`、`_olderCursor`、`_reachedStart`、`_applyHistoricalWindow`、`_prependUniqueHistoricalLines` 全部沿用现有签名，**本次不改这些方法**（无异步化改造）。
- 测试中 fake loader 签名统一为 `(_, {cursor, limitLines = 500})`，与 `LoadScriptLogWindow` typedef 兼容。

**4. 用例计数核对**

- `test/controller/overview/overview_log_history_test.dart` 现有 **9** 个 `test(`（行 10/33/48/81/106/135/172/203/249），Task 4 后为 11 个。
- `test/component/log/log_widget_scroll_test.dart` 新建，Task 1 后 3 个、Task 2 后 5 个、Task 3 后 9 个。
- `test/views/overview/overview_log_actions_test.dart` 现有 5 个，全程不改。

---

Plan complete and saved to `docs/superpowers/plans/2026-07-28-smooth-log-loading.md`. Execute tasks one at a time, testing after each, and commit frequently. Review between tasks before moving on.
