import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:oasx/component/log/log_mixin.dart';
import 'package:oasx/component/log/log_widget.dart';

class _FakeLogController extends GetxController with LogMixin {}

void main() {
  // 中文注释：锁定顶部切换改为标签页形式，同时保留右侧操作按钮区域。
  testWidgets('shows tab-style logs and stats switch with trailing actions in top log panel', (tester) async {
    final controller = _FakeLogController();

    final tabController = TabController(length: 2, vsync: const TestVSync());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LogWidget(
            controller: controller,
            title: '日志',
            topPanelLeading: Theme(
              data: ThemeData(),
              child: TabBar(
                controller: tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                dividerColor: Colors.transparent,
                tabs: const [
                  Tab(text: '日志'),
                  Tab(text: '统计'),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.widgetWithText(Tab, '日志'), findsOneWidget);
    expect(find.widgetWithText(Tab, '统计'), findsOneWidget);
    expect(find.byType(TabBar), findsOneWidget);
    expect(find.byIcon(Icons.flash_on), findsOneWidget);
    expect(find.byIcon(Icons.content_copy_rounded), findsOneWidget);
    expect(find.byIcon(Icons.delete_outlined), findsOneWidget);

    final TabBar tabBar = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabBar.isScrollable, isTrue);
    expect(tabBar.dividerColor, Colors.transparent);

    tabController.dispose();
  });
}
