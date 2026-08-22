import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:oasx/views/args/args_view.dart';

// 中文注释：锁住参数表单里 bool 勾选框与其他控件的左缘对齐。
//
// 故障现象：勾选框画出来的描边方块只有 Checkbox.width(18px)，却被居中摆在
// 48px 的点击热区中央（SDK checkbox.dart 里 origin = size/2 - 18/2），
// 于是方块左缘比同列其他控件（输入框 / 下拉 / 时间选择器都从列左缘 0 开始）
// 右移 (48-18)/2 = 15px，肉眼看就是勾选框和别人不在一条线上。

/// 中文注释：挂载真实的 ArgumentView。
///
/// 必须挂真实控件而不是照抄一份布局做替身：替身里的 Transform 是测试自己写的，
/// production 的 _checkbox() 把左移量删掉了替身也照样通过（实测过这个假阳性）。
/// ArgumentView 只依赖 Get 里的 ArgsController，喂一份内联 json 即可起来。
Future<void> _pumpArgument(WidgetTester tester, Map<String, dynamic> arg) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  addTearDown(Get.reset);

  final controller = Get.put(ArgsController());
  // members 必须装 ArgumentModel 实例：loadModel 只是把 json 原样塞进 members，
  // ArgumentView 取的是 ArgumentModel，直接喂 Map 会在 build 里类型转换失败
  final group = GroupsModel(
    groupName: 'g',
    members: [ArgumentModel.fromJson(arg)],
  );
  controller.groupsName.value = ['g'];
  controller.groupsData.value = {'g': group};

  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: ArgumentView(
        // 对齐测试不落盘，直接返回成功
        setArgument: (a, b, c, d, e, f) async => true,
        getGroupName: () => 'g',
        index: 0,
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  group('SDK 几何前提', () {
    // 修正量是按这两个常量算的，SDK 改了就必须重新算，所以直接断言它们
    test('Checkbox 描边方块边长仍是 18', () {
      expect(Checkbox.width, 18.0,
          reason: 'args_view 的 _checkboxInset 按此值推导');
    });

    testWidgets('Checkbox 默认点击热区仍是 48×48', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Checkbox(value: true, onChanged: (_) {})),
      ));
      expect(tester.getSize(find.byType(Checkbox)), const Size(48, 48),
          reason: 'args_view 的 _checkboxTapTarget 按此值推导');
    });
  });

  group('列内左缘对齐', () {
    // 视觉回收量：与 args_view.dart 的 _checkboxOpticalPullBack 同值。
    // 那个是 private，测试读不到，只能在这里复述一份并靠下面的源码断言锁住。
    const opticalPullBack = 3.0;

    testWidgets('勾选框描边方块左缘落在输入框左缘右侧一个视觉回收量', (tester) async {
      // 先量真实 bool 参数里勾选框的位置
      await _pumpArgument(tester, {
        'name': '跳过难度较高的结界',
        'value': true,
        'type': 'boolean',
      });
      final tapTargetLeft = tester.getRect(find.byType(Checkbox)).left;
      // 描边方块居中在热区里，实际可见左缘要加回两者边长差的一半
      final paintedLeft = tapTargetLeft + (48 - Checkbox.width) / 2;

      // 再量同一布局下 integer 参数输入框的位置。
      // 注意不能直接 find.byType(EditableText)：标题走 SelectableText，
      // 它内部也是 EditableText，会先匹配到标题那一个。
      await _pumpArgument(tester, {
        'name': '主动退出次数',
        'value': 0,
        'type': 'integer',
      });
      final fieldLeft = tester
          .getRect(find.descendant(
            of: find.byType(TextFormField),
            matching: find.byType(EditableText),
          ))
          .left;

      // 严格几何对齐（paintedLeft == fieldLeft）实测偏左：描边是 2px 宽沿路径
      // 居中画的、墨迹落在方块外，而邻列看到的是自带左侧边距的文字。
      // 所以刻意留一个视觉回收量，方块盒子比文字盒子右 3px、墨迹才对齐。
      expect(paintedLeft, fieldLeft + opticalPullBack,
          reason: '勾选框应比输入框左缘右 $opticalPullBack px（视觉回收量）');

      // 同时守住方向与量级：回收后仍必须比「完全不修正」明显偏左，
      // 否则等于退回原来那个右移 15px 的故障
      expect(paintedLeft, lessThan(fieldLeft + 15),
          reason: '不得退回未修正状态（那时右移整整 15px）');
    });

    testWidgets('点击热区完整保留 48×48，没有为了对齐压缩热区', (tester) async {
      // 左移是用 Transform 移动绘制，不该改变布局尺寸；
      // 若改用 shrinkWrap / visualDensity 压热区，会掉到无障碍建议的 40px 以下
      await _pumpArgument(tester, {
        'name': '寮管理开启寮突破',
        'value': false,
        'type': 'boolean',
      });
      expect(tester.getSize(find.byType(Checkbox)), const Size(48, 48));
    });

    test('勾选框必须走 _checkbox() 并带左移修正', () {
      // 防回退成裸 Checkbox：那样又会右移 15px
      final source = File('lib/views/args/args_view.dart').readAsStringSync();
      expect(source.contains('"boolean" => _checkbox()'), isTrue,
          reason: 'bool 分支应走带对齐修正的 _checkbox()');
      expect(source.contains('offset: const Offset(-_checkboxInset, 0)'), isTrue,
          reason: '必须左移一个 inset，否则描边方块仍居中在热区里');
      // 几何量必须由 SDK 常量推导，不能写死魔法数字
      expect(
          source.contains(
              'const double _checkboxGeometryInset = (_checkboxTapTarget - Checkbox.width) / 2'),
          isTrue,
          reason: '几何量应由热区与方块边长推导，SDK 变动时才能被上面的用例发现');
      // 视觉回收量与本文件的 opticalPullBack 必须同值，
      // 否则上面那条渲染断言量的是另一个数
      expect(source.contains('const double _checkboxOpticalPullBack = 3'), isTrue,
          reason: '视觉回收量应为 3，与本文件 opticalPullBack 一致');
      // 压平空白再比：dart format 会按行长决定这条声明换不换行，
      // 带换行符硬比会随格式化结果时好时坏
      final flat = source.replaceAll(RegExp(r'\s+'), ' ');
      expect(
          flat.contains(
              'const double _checkboxInset = _checkboxGeometryInset - _checkboxOpticalPullBack'),
          isTrue,
          reason: '实际左移量应是「几何量 - 视觉回收量」，两者都不能内联成数字');
    });
  });
}
