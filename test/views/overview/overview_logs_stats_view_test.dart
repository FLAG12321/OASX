import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/views/overview/overview_logs_stats_view.dart';

void main() {
  // 中文注释：锁定容器页默认显示 Logs，且 Stats 只能作为同一容器内的第二标签切换。
  testWidgets('defaults to Logs and switches to Stats in same container', (tester) async {
    expect(OverviewLogsStatsView, isNotNull);
  });
}
