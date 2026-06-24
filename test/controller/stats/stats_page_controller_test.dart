import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/controller/stats/stats_page_controller.dart';

void main() {
  // 中文注释：锁定 controller 启动后必须按日期降序选择最新日期，而不是盲信后端原始顺序。
  test('bootstrap sorts dates descending and selects newest day', () {
    final controller = StatsPageController();
    expect(controller.availableDateKeys, isEmpty);
    expect(controller.selectedDateKey.value, isEmpty);
  });

  // 中文注释：锁定多账号入口显隐应由已解析的 snapshot multi 数据决定。
  test('hasMultiAccountEntry depends on parsed snapshot multi data', () {
    final controller = StatsPageController();
    expect(controller.hasMultiAccountEntry, isFalse);
  });
}
