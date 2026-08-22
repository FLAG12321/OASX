import 'package:expansion_tile_group/expansion_tile_group.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:oasx/component/log/log_mixin.dart';
import 'package:oasx/component/log/log_widget.dart';

/// 中文注释：LogMixin 桩 controller；不注册到 Get，避免 onInit 启动日志刷新计时器。
class _FakeLogController extends GetxController with LogMixin {}

/// 中文注释：挂载 LogWidget 并取出第 index 行真正渲染出来的纯文本。
///
/// 为什么要看渲染结果而不是只测 controller.logs：日志行经
/// `_trimMillis` 截毫秒、再由 EasyRichText 按 pattern 拆成多个 TextSpan
/// （级别着色、时间戳高亮、补位 span），任何一步出错都只体现在最终 span 树上。
/// 既有测试只比对行高，看不见文字内容，所以 `$1` 这类字面量泄漏能一路蒙过去。
Future<String> _renderedLine(WidgetTester tester, String rawLine) async {
  final controller = _FakeLogController();
  controller.logs.add(rawLine);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 400,
          child: LogWidget(controller: controller, title: '日志'),
        ),
      ),
    ),
  );
  await tester.pump();

  // 日志行用 selectable 渲染，落地为 SelectableText.rich
  final selectable = tester.widgetList<SelectableText>(
    find.byType(SelectableText),
  );
  expect(selectable, isNotEmpty, reason: '应至少渲染出一行日志');
  return selectable.first.textSpan!.toPlainText();
}

void main() {
  group('日志行渲染文本', () {
    testWidgets('毫秒截断保留一位且不泄漏 \$1 字面量', (tester) async {
      final text = await _renderedLine(
          tester, 'INFO    |12:34:56.789| 任务开始\n');

      // 回归锚点：Dart 的 String.replaceAll 第二参是字面量、不解析 $1 反向引用，
      // 误用会把时间戳整段替换成 "$1"。必须用 replaceAllMapped。
      expect(text, isNot(contains(r'$1')),
          reason: r'时间戳被替换成 $1 字面量，说明用了 replaceAll 而非 replaceAllMapped');
      expect(text, contains('12:34:56.7'), reason: '应保留一位毫秒');
      expect(text, isNot(contains('12:34:56.789')), reason: '后两位毫秒应被截掉');
    });

    testWidgets('各级别渲染宽度一致，前端不再二次补位', (tester) async {
      // 后端 flutter_formatter 的 %(levelname)-8s 已把级别补成定宽 8 列
      // （见 OAS module/logger.py）。前端若再补空格，总宽会变成「8 + 补数」，
      // 让 INFO > ERROR > WARNING。
      final lengths = <String, int>{};
      for (final level in ['INFO', 'WARNING', 'ERROR', 'CRITICAL']) {
        // 模拟后端已 -8s 补位的真实行形态：级别 8 列后紧跟 |，两侧不留空格
        final raw = '${level.padRight(8)}|12:34:56.789| msg\n';
        final text = await _renderedLine(tester, raw);
        // 取到第一个 '|' 之前，即级别字段渲染后的实际宽度
        lengths[level] = text.indexOf('|');
      }
      final distinct = lengths.values.toSet();
      expect(distinct.length, 1,
          reason: '级别字段渲染宽度必须一致，实测 $lengths');
      expect(distinct.single, 8,
          reason: '级别字段应恰好 8 列（%(levelname)-8s），实测 $lengths');
    });

    testWidgets('分隔线不被改写', (tester) async {
      // GuiRule 按 GUI_LOG_WIDTH 渲染 START/RESTART 分隔线；等宽字体下它与数据行
      // 逐列对齐，前端不应对其做任何替换（其中不含时间戳，_trimMillis 应原样放过）。
      const sep = '─────────────── RESTART ───────────────\n';
      final text = await _renderedLine(tester, sep);
      expect(text.trim(), sep.trim());
    });
  });

  group('日志缩进与折叠面板对齐', () {
    testWidgets('日志标题与正文左缘对齐折叠面板标题', (tester) async {
      // 折叠面板标题走 ListTile 默认 contentPadding(horizontal:16)，
      // 文字落在 Card 左边缘 +16；日志原来只有 paddingAll(8)，比面板浅 8px。
      //
      // 必须用真实的 ExpansionTileCard 作基准，不能拿裸 Card+ListTile 替身：
      // 真实面板的 ListTile 带 leading/trailing 图标，几何与裸 ListTile 不同，
      // 替身会量出 20（真实值 16），据此设值反而错开 4px。
      tester.view.physicalSize = const Size(1486, 993);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final controller = _FakeLogController();
      controller.logs.add('INFO    |12:34:56.789| hello\n');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                // 与 ServerView._body 的左右 10 一致
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Column(
                  spacing: 10,
                  children: [
                    // 与服务页四个面板完全同款的真实控件
                    ExpansionTileCard(
                      title: const Text('面板标题'),
                      children: const [Text('面板正文')],
                    ),
                    SizedBox(
                      height: 300,
                      child: LogWidget(
                          controller: controller, title: '服务启动日志'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final panelLeft = tester.getRect(find.text('面板标题')).left;
      final logTitleLeft = tester.getRect(find.text('服务启动日志')).left;
      final logLineLeft =
          tester.getRect(find.byType(SelectableText).first).left;

      expect(logTitleLeft, panelLeft,
          reason: '日志标题应与折叠面板标题左缘对齐');
      expect(logLineLeft, panelLeft,
          reason: '日志正文应与折叠面板标题左缘对齐');
    });

    testWidgets('日志标题字号比 titleMedium 默认值大一号', (tester) async {
      // 服务页五个框标题必须同款；面板侧由 ServerView.panelTitleStyle 统一，
      // 日志侧在 TopLogPanel 里用同样的 17。
      final controller = _FakeLogController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 300,
              child:
                  LogWidget(controller: controller, title: '服务启动日志'),
            ),
          ),
        ),
      );
      await tester.pump();

      final style = tester.widget<Text>(find.text('服务启动日志')).style;
      expect(style?.fontSize, 17,
          reason: '与 ServerView.panelTitleStyle 的 17 保持一致');
      // 只改字号、保留 titleMedium 的 w500：titleLarge 是 22/w400，字重会变轻
      expect(style?.fontWeight, FontWeight.w500,
          reason: '标题应保持 titleMedium 的 w500 字重');
    });
  });
}
