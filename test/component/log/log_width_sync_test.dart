import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/component/log/log_line_width.dart';

// 中文注释：跨仓库常量一致性门禁。
//
// 日志宽度这组数字同时存在于两个仓库：
//   前端 OASX  lib/component/log/log_line_width.dart 的 kLogLineWidthLimit
//   后端 OAS   module/logger.py 的 GUI_LOG_WIDTH / GUI_RULE_WIDTH
// 后端把「消息折行宽度」与「分隔线宽度」拆成两个常量、取值相同：
//   GUI_LOG_WIDTH  = 80  推给前端的 Console(width=...)，消息按它折
//   GUI_RULE_WIDTH = 80  分隔线总宽（= GUI_LOG_WIDTH，同源）
// 前端只需要知道后者：分隔线是合法的最宽行，前端上限兜的是不经 rich 的子进程
// stdout，超出分隔线才折。
//
// 两边不等的后果是静默错列，没有任何报错：
//   前端更窄 -> 后端折好的行被再折一次，末尾溢出一小截独占一行
//   前端更宽 -> 子进程 stdout 溢出分隔线
// 两个仓库分别改、跨仓库无编译期约束，所以只能靠这条测试守。
void main() {
  group('前后端日志宽度常量一致', () {
    // OASX 在 <yys>/OnmyojiAutoScript-easy-install/OASX_last/OASX，
    // OAS 在 <yys>/OnmyojiAutoScript-easy-install/OnmyojiAutoScript-easy-install
    // （同名目录嵌套两层，见 CLAUDE.md）。flutter test 的 cwd 是包根即 OASX。
    final oasLogger =
        File('../../OnmyojiAutoScript-easy-install/module/logger.py');

    /// 读后端源码里一个顶层整数常量；缺失返回 null 让调用方给出可读的失败原因。
    int? backendInt(String source, String name) {
      final m = RegExp('^$name\\s*=\\s*(\\d+)', multiLine: true)
          .firstMatch(source);
      return m == null ? null : int.parse(m.group(1)!);
    }

    test('后端 GUI_RULE_WIDTH 与前端 kLogLineWidthLimit 相等', () {
      if (!oasLogger.existsSync()) {
        // 只在同时 checkout 了两个仓库的环境跑；CI 只有 OASX 时跳过而不是失败
        markTestSkipped('未找到 OAS 的 module/logger.py，跳过跨仓库校验');
        return;
      }
      final source = oasLogger.readAsStringSync();
      // GUI_LOG_WIDTH 是唯一写数字的地方（100）；GUI_RULE_WIDTH 是它的别名
      // （`= GUI_LOG_WIDTH`），解析不出独立数字，只能断言同源
      final logWidth = backendInt(source, 'GUI_LOG_WIDTH');
      expect(logWidth, isNotNull,
          reason: '后端应有顶层常量 GUI_LOG_WIDTH；被改名或内联了就会失去这道门禁');
      expect(logWidth, kLogLineWidthLimit,
          reason: '前端上限必须等于后端日志行宽度 GUI_LOG_WIDTH');
      // 分隔线总宽必须由 GUI_LOG_WIDTH 推导，两个数都写死会有漂移风险
      expect(source.contains('GUI_RULE_WIDTH = GUI_LOG_WIDTH'), isTrue,
          reason: '分隔线总宽 GUI_RULE_WIDTH 必须等于 GUI_LOG_WIDTH（同源）');
    });

    test('后端不得把宽度写死在 Console/GuiRule 里', () {
      if (!oasLogger.existsSync()) {
        markTestSkipped('未找到 OAS 的 module/logger.py，跳过跨仓库校验');
        return;
      }
      final source = oasLogger.readAsStringSync();
      // 消息折行用 GUI_LOG_WIDTH、分隔线用 GUI_RULE_WIDTH，各自都必须引用常量。
      // 写死数字会让上面那条相等断言形同虚设（常量对了、实际用的还是旧值）
      expect(source.contains('width=GUI_LOG_WIDTH'), isTrue,
          reason: '推给前端的 Console 必须用 GUI_LOG_WIDTH');
      expect(source.contains('options.max_width = GUI_RULE_WIDTH'), isTrue,
          reason: 'GuiRule.__rich_console__ 必须用 GUI_RULE_WIDTH');
      expect(source.contains('total_width = GUI_RULE_WIDTH'), isTrue,
          reason: 'GuiRule.__str__ 必须用 GUI_RULE_WIDTH');
    });

    test('后端行首格式与前端的着色/截毫秒正则同构', () {
      if (!oasLogger.existsSync()) {
        markTestSkipped('未找到 OAS 的 module/logger.py，跳过跨仓库校验');
        return;
      }
      final source = oasLogger.readAsStringSync();
      // 级别定宽 8 列由 %(levelname)-8s 保证：前端据此不再补空格（见
      // _buildPatterns 的注释），若后端改回 rich 的级别列，前端列宽会失配
      expect(source.contains(r'%(levelname)-8s|%(asctime)s.%(msecs)03d|'),
          isTrue,
          reason: '行首必须是「级别8列 + | + 时间戳 + |」，竖线两侧不留空格');
      expect(source.contains('show_level=False'), isTrue,
          reason: '级别须由 formatter 输出；开着 rich 的级别列会多占一列并给续行加缩进');

      // 后端仍推 3 位毫秒，前端 _trimMillis 在渲染层截成 1 位。
      // 后端若改成 1 位，前端的截断正则与着色正则都要跟着改
      expect(source.contains('%(msecs)03d'), isTrue,
          reason: '后端毫秒保持 3 位（复制日志要原始精度），截断只在前端渲染层做');
      final widget =
          File('lib/component/log/log_widget.dart').readAsStringSync();
      expect(widget.contains(r'(\d{2}:\d{2}:\d{2}\.\d)\d{2}'), isTrue,
          reason: '_trimMillis 的正则须匹配后端的 3 位毫秒');
    });
  });

  group('字号与宽度匹配', () {
    test('日志正文字号必须让整条分隔线在窄窗口内装得下', () {
      // Cascadia 每字符宽 0.5859em（fontTools 实测，等宽含 ─ 与全角）。
      // 1280 宽窗口下日志正文可用约 1234px（实测：页面左右各 10 + Card 内
      // 左 16 右 10）。字号 12 时 80 列约 562px，装得下；14 也只要 656px。
      //
      // 量的是分隔线宽度（80）而不是日志行宽：分隔线就是最宽的行。
      const advance = 0.5859;
      const fontSize = 12.0;
      const narrowestAvail = 1234.0;
      const needed = kLogLineWidthLimit * advance * fontSize;
      expect(needed, lessThan(narrowestAvail),
          reason: '整行需 ${needed.toStringAsFixed(0)}px，'
              '窄窗口只有 ${narrowestAvail.toStringAsFixed(0)}px，会被裁成省略号');

      // 同步锁住 log_widget 里的实际取值，避免这里算得对、那边写了别的
      final widget =
          File('lib/component/log/log_widget.dart').readAsStringSync();
      expect(widget.contains('base.copyWith(fontSize: 12)'), isTrue,
          reason: '日志正文字号应为 12，与本用例的计算前提一致');
    });
  });
}
