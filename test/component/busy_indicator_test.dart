import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/component/busy_indicator.dart';

// 中文注释：锁定「等待后端响应」中间态的表现契约。
// BusyTransition 是脚本启停按钮图标与参数落盘指示共用的动画载体：
// busy 时必须出现转圈并移除原内容，常态必须只剩原内容。
//
// 注意：这里一律用 pump(duration) 而不是 pumpAndSettle。
// CircularProgressIndicator 是无限动画，pumpAndSettle 会等到超时而非等到稳定。
void main() {
  Widget wrap(Widget child) =>
      MaterialApp(home: Scaffold(body: Center(child: child)));

  // AnimatedSwitcher 交叉淡入 250ms，推进 400ms 确保旧 child 已被移除
  const settle = Duration(milliseconds: 400);

  testWidgets('BusyTransition 在 busy 时显示转圈、常态显示原内容', (tester) async {
    await tester.pumpWidget(wrap(const BusyTransition(
      busy: false,
      child: Icon(Icons.power_settings_new_rounded),
    )));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.power_settings_new_rounded), findsOneWidget);

    await tester.pumpWidget(wrap(const BusyTransition(
      busy: true,
      child: Icon(Icons.power_settings_new_rounded),
    )));
    await tester.pump(settle);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.power_settings_new_rounded), findsNothing);
  });

  testWidgets('BusyTransition 退出 busy 后恢复原内容', (tester) async {
    await tester.pumpWidget(wrap(const BusyTransition(
      busy: true,
      child: Icon(Icons.delete),
    )));
    await tester.pump(settle);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpWidget(wrap(const BusyTransition(
      busy: false,
      child: Icon(Icons.delete),
    )));
    await tester.pump(settle);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.delete), findsOneWidget);
  });

  testWidgets('BusyTransition 的转圈尺寸跟随 size，避免切换时布局跳动', (tester) async {
    await tester.pumpWidget(wrap(const BusyTransition(
      busy: true,
      size: 12,
      child: SizedBox(width: 12, height: 12),
    )));
    await tester.pump(settle);
    final box = tester.getSize(find.ancestor(
      of: find.byType(CircularProgressIndicator),
      matching: find.byType(SizedBox),
    ).first);
    expect(box.width, 12);
    expect(box.height, 12);
  });

  testWidgets('BusyOverlay 渲染转圈与提示文案', (tester) async {
    await tester.pumpWidget(wrap(const BusyOverlay(label: '正在处理...')));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('正在处理...'), findsOneWidget);
  });

  testWidgets('BusyOverlay 无文案时只渲染转圈', (tester) async {
    await tester.pumpWidget(wrap(const BusyOverlay()));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(Text), findsNothing);
  });
}
