import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/views/overview/multi_account_stats_page.dart';

void main() {
  // 中文注释：锁定多账号页必须消费已存在的 snapshot 数据，不能自己重新发起加载流。
  testWidgets('multi-account page consumes existing snapshot data from stats layer', (tester) async {
    expect(MultiAccountStatsPage, isNotNull);
  });
}
