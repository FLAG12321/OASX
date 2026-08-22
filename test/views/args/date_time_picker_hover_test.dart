import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/views/args/args_view.dart';

// 中文注释：锁住时间选择组件的 hover 行为——hover 只改颜色，不改任何影响布局的量。
//
// 原实现用字号做 hover 反馈（16 → 17），而 Text 是内容定高的，行高随字号线性
// 变化，hover 时整行被纵向撑开、顶动同行控件。视觉反馈必须与布局解耦。
void main() {
  /// 挂载一个 TimePicker 并返回其渲染高度。
  Future<double> heightUnderHover(WidgetTester tester,
      {required bool hover}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: TimePicker(value: '12:34:56', onChange: (_) {}),
          ),
        ),
      ),
    );
    await tester.pump();

    if (hover) {
      // 造一个鼠标指针移到组件中心，触发 MouseRegion.onEnter
      final gesture =
          await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.text('12:34:56')));
      await tester.pump();
    }
    return tester.getSize(find.byType(TimePicker)).height;
  }

  testWidgets('hover 不改变组件高度', (tester) async {
    final idle = await heightUnderHover(tester, hover: false);
    final hovered = await heightUnderHover(tester, hover: true);
    expect(hovered, idle,
        reason: 'hover 撑高说明又用字号/尺寸做反馈了，会顶动同行控件');
  });

  testWidgets('hover 时变色，确认 hover 真的生效了', (tester) async {
    // 若 hover 未触发，上一条「高度不变」会因两边都是 idle 态而假通过
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: TimePicker(value: '12:34:56', onChange: (_) {}),
          ),
        ),
      ),
    );
    await tester.pump();
    final before = tester.widget<Text>(find.text('12:34:56')).style?.color;

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.text('12:34:56')));
    await tester.pump();
    final after = tester.widget<Text>(find.text('12:34:56')).style?.color;

    expect(after, isNot(before), reason: 'hover 应改变颜色');
  });

  testWidgets('hover 前后字号恒定', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: TimePicker(value: '12:34:56', onChange: (_) {}),
          ),
        ),
      ),
    );
    await tester.pump();
    final before = tester.widget<Text>(find.text('12:34:56')).style?.fontSize;

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.text('12:34:56')));
    await tester.pump();
    final after = tester.widget<Text>(find.text('12:34:56')).style?.fontSize;

    expect(after, before, reason: 'hover 不得改字号，那是撑开布局的直接原因');
    // 字号已比原先的 16 小一号
    expect(before, lessThan(16.0), reason: '时间数字应比原先的 16 小一号');
  });
}
