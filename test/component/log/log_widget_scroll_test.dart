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

/// 中文注释：覆盖多种字符集与日志级别的真实行形态。SliverPrototypeExtentList
/// 用原型高度作紧约束，任何真实行高于原型都会被压扁裁切且无溢出告警，
/// 因此需要按形态逐一比对，而不是只验证一条 ASCII 行。
const _rowSamples = <String>[
  'INFO: 12:00:00.000 line\n',
  'INFO: 12:00:00.000 脚本启动成功，开始执行任务\n',
  'INFO: 12:00:00.000 【御魂】（完成）：结算界面\n',
  'INFO: 12:00:00.000 done ✅🎉\n',
  'ERROR: 12:00:00.000 识别失败：找不到模板\n',
  'CRITICAL: 12:00:00.000 致命错误\n',
  '──────────────────\n',
  'INFO: 12:00:00.000 [御魂] Àÿ ĝ True None (1)\n',
];

/// 中文注释：从挂载的 LogWidget 取出 prototypeItem 与各样本行的真实 widget，
/// 并排渲染实测原型不矮于任何真实行。实测 bodySmall（portrait）下命中高亮
/// pattern 的行比普通 Text 高 4px，是最容易出现失配的样式。
Future<void> _expectPrototypeMatchesRow(WidgetTester tester) async {
  final controller = _FakeLogController();
  controller.logs.addAll(_rowSamples);
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
            for (int i = 0; i < _rowSamples.length; i++)
              KeyedSubtree(
                key: Key('row$i'),
                child: Builder(builder: (c) => delegate.builder(c, i)!),
              ),
          ],
        ),
      ),
    ),
  );

  final protoHeight = tester.getSize(find.byKey(const Key('proto'))).height;
  // 中文注释：第 0 条是最常见的行形态，要求与原型严格等高，
  // 防止原型被改成远超真实行的高度而白白拉大行距。
  expect(tester.getSize(find.byKey(const Key('row0'))).height, protoHeight,
      reason: '常规 INFO 行应与原型等高');
  // 中文注释：其余形态只要不高于原型即可——矮行被撑高只是多出空隙，不会裁切。
  for (int i = 1; i < _rowSamples.length; i++) {
    expect(tester.getSize(find.byKey(Key('row$i'))).height,
        lessThanOrEqualTo(protoHeight),
        reason: '样本行高于原型会被紧约束裁切：${_rowSamples[i].trim()}');
  }
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

    // 中文注释：显式断言前置条件落在跳转区间（距离 > 3 倍视口），
    // 否则行数不足时用例会在动画路径上「碰巧」通过而失去意义。
    final position = scroll.position;
    expect(position.maxScrollExtent,
        greaterThan(position.viewportDimension * 3),
        reason: '距离未超过跳转阈值，需增加行数');

    controller.scrollLogs?.call(force: true, scrollOffset: -1);
    // 中文注释：_scrollLogs 只注册 postFrameCallback、不主动调度帧；真实运行时
    // 日志更新总伴随新帧，测试环境静止无帧，需手动调度一帧让回调执行。
    tester.binding.scheduleFrame();
    // 中文注释：一帧执行 postFrameCallback，第二帧观察结果。
    await tester.pump();
    await tester.pump();

    expect(scroll.offset, position.maxScrollExtent);
    // 中文注释：直接锁定「没有启动动画」这一语义，而非依赖动画时长恰好未走完；
    // 若实现退回 animateTo，会留下运行中的 ticker 使该断言失败。
    // 前提：本用例 historyLoading 为 false，不渲染占位 spinner——它的
    // CircularProgressIndicator 是常驻 ticker，会让该计数永不为 0。
    expect(tester.binding.transientCallbackCount, 0,
        reason: '长距离滚动不应启动动画');
  });

  // 中文注释：锁定短距离仍走平滑动画，实时日志追尾体验不退化。
  testWidgets('short distance scroll still animates', (tester) async {
    final controller = _FakeLogController();
    // 中文注释：40 行需同时满足「有可滚动距离」与「不超过 3 倍视口阈值」，
    // 具体行数与视口尺寸相关，故用下面的前置断言而非硬编码像素值来保证。
    controller.logs.addAll(List.generate(40, (i) => 'INFO: line $i\n'));

    await _pumpLogWidget(tester, controller);

    final scroll =
        tester.widget<ListView>(find.byType(ListView)).controller!;
    final position = scroll.position;
    final target = position.maxScrollExtent;
    // 中文注释：显式断言前置条件，让「阈值关系」而非行数成为用例契约；
    // 行数不足或越过阈值时测试应失败而非静默通过。
    expect(target, greaterThan(0),
        reason: '行数不足以产生可滚动距离，需增加行数');
    expect(target, lessThanOrEqualTo(position.viewportDimension * 3),
        reason: '距离已超过跳转阈值，会走 jumpTo，需减少行数');
    scroll.jumpTo(0);
    await tester.pump();

    controller.scrollLogs?.call(force: true, scrollOffset: -1);
    // 中文注释：同上，手动调度一帧让 postFrameCallback 执行并启动动画。
    // ticker 的首个 tick 只记录时间基准（offset 不动），再推进 50ms 观察中间态。
    tester.binding.scheduleFrame();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 50));

    // 中文注释：动画进行中——已启动但未到终点。
    expect(scroll.offset, greaterThan(0));
    expect(scroll.offset, lessThan(target));
    // 中文注释：与长距离用例对称，锁定这里确实是动画而非跳转。
    // 同样以「本用例不渲染占位 spinner」为前提。
    expect(tester.binding.transientCallbackCount, greaterThan(0),
        reason: '短距离滚动应处于动画中');
  });

  // 中文注释：锁定首次加载（logs 为空）期间显示整区域占位。
  testWidgets('shows placeholder spinner while loading with empty logs',
      (tester) async {
    final controller = _FakeLogController();
    controller.historyLoading.value = true;

    await _pumpLogWidget(tester, controller);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(ListView), findsOneWidget);
    // 中文注释：几何校验「叠加而非替换」——spinner 必须落在列表区域之内。
    // 不用「spinner 有 Stack 祖先」这类断言：Scaffold 与 Card 本身就带 Stack，
    // 那样写在替换实现下也会通过，属于空转。
    final listRect = tester.getRect(find.byType(ListView));
    final spinnerRect = tester.getRect(find.byType(CircularProgressIndicator));
    expect(spinnerRect.left, greaterThanOrEqualTo(listRect.left));
    expect(spinnerRect.top, greaterThanOrEqualTo(listRect.top));
    expect(spinnerRect.right, lessThanOrEqualTo(listRect.right));
    expect(spinnerRect.bottom, lessThanOrEqualTo(listRect.bottom));
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

  // 中文注释：锁定 child 切换（Logs↔Stats 标签）往返后恢复阅读位置。
  // 列表被 child 替换时离树、ScrollPosition 销毁，切回时 initState 的
  // 一次性滚动回调早已消耗，无恢复机制则停在最顶端（最老的行）。
  testWidgets('restores bottom position after child swap when autoScroll on',
      (tester) async {
    final controller = _FakeLogController();
    controller.logs.addAll(List.generate(500, (i) => 'INFO: line $i\n'));

    Widget build({Widget? child}) => MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: LogWidget(controller: controller, title: '日志', child: child),
            ),
          ),
        );

    await tester.pumpWidget(build());
    tester.binding.scheduleFrame();
    await tester.pump();
    await tester.pump();
    final scroll = tester.widget<ListView>(find.byType(ListView)).controller!;
    expect(scroll.offset, scroll.position.maxScrollExtent,
        reason: '前置条件：初始已滚到底');

    // 中文注释：切到 Stats（child 非空），列表离树。
    await tester.pumpWidget(build(child: const Center(child: Text('STATS'))));
    await tester.pump();
    expect(find.byType(ListView), findsNothing);

    // 中文注释：切回 Logs，autoScroll=true 应恢复到底部。
    await tester.pumpWidget(build());
    await tester.pump();
    final scroll2 = tester.widget<ListView>(find.byType(ListView)).controller!;
    expect(scroll2.offset, scroll2.position.maxScrollExtent);
  });

  // 中文注释：autoScroll 关闭（用户正在回看）时，child 切换往返应恢复
  // 离开时的阅读位置而非跳底。
  testWidgets('restores reading position after child swap when autoScroll off',
      (tester) async {
    final controller = _FakeLogController();
    controller.logs.addAll(List.generate(500, (i) => 'INFO: line $i\n'));
    controller.autoScroll.value = false;

    Widget build({Widget? child}) => MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: LogWidget(controller: controller, title: '日志', child: child),
            ),
          ),
        );

    await tester.pumpWidget(build());
    await tester.pump();
    final scroll = tester.widget<ListView>(find.byType(ListView)).controller!;
    scroll.jumpTo(1234);
    await tester.pump();

    await tester.pumpWidget(build(child: const Center(child: Text('STATS'))));
    await tester.pump();

    await tester.pumpWidget(build());
    await tester.pump();
    final scroll2 = tester.widget<ListView>(find.byType(ListView)).controller!;
    expect(scroll2.offset, 1234);
  });
}
