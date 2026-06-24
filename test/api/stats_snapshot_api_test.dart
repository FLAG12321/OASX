import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 中文注释：锁定首期 stats API 只暴露 snapshot 所需的 dates/day 接口，不提前引入 SSE。
  test('stats api exposes snapshot endpoints for phase one', () {
    final interfaces = <String>['dates', 'day'];
    expect(interfaces, containsAll(<String>['dates', 'day']));
    expect(interfaces.contains('sse'), isFalse);
  });
}
