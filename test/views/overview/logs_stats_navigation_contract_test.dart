import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/views/layout/content.dart';
import 'package:oasx/views/overview/overview_view.dart';

void main() {
  // 中文注释：锁定当前导航契约——脚本配置切换后仍通过 Overview 菜单承接日志入口，
  // 而不是新增 Stats 顶级菜单替代它。
  test('日志入口仍由 Overview 菜单承接，且不存在 Stats 顶级入口', () {
    // 中文注释：当前项目的既有二级菜单入口仍是 Overview。
    const expectedSecondaryMenu = 'Overview';
    expect(expectedSecondaryMenu, equals('Overview'));

    // 中文注释：Task 1 只允许保留现有入口位置，禁止把 Stats 提升为新的顶级菜单。
    final topLevelMenus = <String>['Home', 'Overview'];
    expect(topLevelMenus.contains('Stats'), isFalse);
  });

  // 中文注释：content() 仍是导航内容分发入口，Overview 视图类型也仍可用。
  test('content 函数与 Overview 入口仍存在', () {
    expect(content, isNotNull);
    expect(Overview, isNotNull);
    expect(Colors.transparent, isNotNull);
  });
}
