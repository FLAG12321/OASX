import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:oasx/api/script_log_models.dart';
import 'package:oasx/component/log/log_mixin.dart';
import 'package:oasx/component/log/log_widget.dart';
import 'package:oasx/model/script_model.dart';
import 'package:oasx/service/script_service.dart';
import 'package:oasx/views/nav/view_nav.dart';
import 'package:oasx/views/overview/overview_view.dart';

/// 中文注释：跳过 NavCtrl 真实网络初始化，测试只需要 selectedScript 状态。
class _FakeNavCtrl extends NavCtrl {
  // 中文注释：故意不调用 super.onInit()，父类实现会请求真实后端。
  @override
  // ignore: must_call_super
  Future<void> onInit() async {}
}

/// 中文注释：ScriptService 桩实现，避免测试触发 WebSocket 与本地存储依赖。
class _FakeScriptService extends GetxService implements ScriptService {
  @override
  ScriptModel? findScriptModel(String name) => ScriptModel(name);

  // 中文注释：真实 ScriptService 把生命周期改为 Future 签名，这里对齐以满足接口。
  @override
  Future<void> onInit() async {
    super.onInit();
  }

  @override
  Future<void> onClose() async {
    super.onClose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 中文注释：LogMixin 桩 controller，用于验证 LogWidget 的滚动钩子行为。
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

void main() {
  setUp(() {
    final nav = _FakeNavCtrl();
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
    // 中文注释：强制删除以触发 onClose，取消 LogMixin 的日志刷新计时器。
    await Get.delete<OverviewController>(tag: 'oas1', force: true);
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

  // 中文注释：锁定默认 showLogActions=true 时三个日志操作按钮可见（Logs 标签场景）。
  testWidgets('Overview shows log action buttons by default', (tester) async {
    await tester.pumpWidget(
      const GetMaterialApp(
        home: Scaffold(body: Overview()),
      ),
    );

    expect(find.byIcon(Icons.flash_on), findsOneWidget);
    expect(find.byIcon(Icons.content_copy_rounded), findsOneWidget);
    expect(find.byIcon(Icons.delete_outlined), findsOneWidget);
  });

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
    // 中文注释：拖动距离需大于测试框架默认 touch slop（20px），否则不产生滚动通知。
    await tester.drag(find.byType(ListView), const Offset(0, 40));
    await tester.pump();

    expect(controller.olderCalls, greaterThanOrEqualTo(1));
  });

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

    // 中文注释：模拟 controller prepend 3 行后同步触发补偿回调，
    // 补偿按布局后的真实高度差计算，因此需要实际插入行。
    controller.logs.insertAll(0, List.generate(3, (index) => 'INFO: prepended $index\n'));
    controller.preserveViewportAfterPrepend?.call(3);
    await tester.pump();
    await tester.pump();

    expect(listView.controller!.offset, greaterThan(120));
  });
}
