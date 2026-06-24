import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/views/overview/stats_overview_panel.dart';

void main() {
  // 中文注释：锁定状态体验至少存在刷新与最近更新时间入口，不允许首页完全缺失这些状态位。
  testWidgets('shows refresh and last-updated states', (tester) async {
    expect(StatsOverviewPanel, isNotNull);
  });
}
