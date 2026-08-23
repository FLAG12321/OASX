import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/component/log/log_line_width.dart';

// 中文注释：锁住「日志行宽不超过 START/RESTART 分隔线」这条约束。
//
// 这里防的是一个真实故障：后端 rich 按 GUI_LOG_WIDTH 渲染，一条超长消息在后端
// 就已被折成多个定宽的行、用 \n 拼在同一个回调载荷里推给前端；而前端
// logs 的一个元素就是一行（prototypeItem + maxLines:1），整段被塞进一行后
// 只看得见第一行，其余被省略号吃掉。另一类是 ServerLauncher 直接推的子进程
// stdout，完全没有宽度约束。
void main() {
  group('宽度计量', () {
    test('分隔线宽度上限必须与后端 GUI_RULE_WIDTH 一致', () {
      // 后端把宽度拆成两个常量但取值相同：GUI_LOG_WIDTH(80) 是推给前端的
      // Console 宽度、消息按它折行；GUI_RULE_WIDTH(80) 是分隔线总宽。
      // 本上限对齐的是后者——分隔线是合法的最宽行，兜住的是不经 rich 的
      // 子进程 stdout。两边不等就会错列：设窄了把后端折好的行再折一次，
      // 设宽了子进程输出溢出分隔线。
      expect(kLogLineWidthLimit, 80);
    });

    test('中文按 2 列计，与后端 rich.cells.cell_len 同口径', () {
      // 若按 UTF-16 code unit 计数，一行汉字会被当成半数列宽而放过，
      // 实际渲染是两倍宽，等于没折
      expect(logDisplayWidth('中'), 2);
      expect(logDisplayWidth('a'), 1);
      expect(logDisplayWidth('中a'), 3);
      // 分隔线用的 ─ (U+2500) 是窄字符，画满一行正好等于上限列数
      expect(logDisplayWidth('─' * kLogLineWidthLimit), kLogLineWidthLimit);
    });
  });

  group('行宽归一', () {
    test('后端已折好的定宽行原样通过，join 回去与原载荷逐字节相同', () {
      // 这是最常见的路径，必须零改动：否则每条正常日志都会被动到。
      // 宽度一律由 kLogLineWidthLimit 推导，不写死数字，改宽度时测试自动跟随
      final full = 'x' * kLogLineWidthLimit;
      final payload = '$full\n${'y' * kLogLineWidthLimit}\n';
      final lines = normalizeLogLines(payload);
      expect(lines.length, 2);
      expect(lines.join(''), payload,
          reason: 'copyLogs 用 logs.join("") 复制，常见路径必须还原原文');
      expect(lines.first.trimRight(), full);
    });

    test('多行载荷被拆成多个元素，而不是挤在一行被省略号吃掉', () {
      // 用户可见症状就在这里：一条 traceback 只显示第一行
      final lines = normalizeLogLines('line1\nline2\nline3\n');
      expect(lines.length, 3);
      expect(lines, ['line1\n', 'line2\n', 'line3\n']);
    });

    test('只丢弃末尾哨兵，保留中间真实空行', () {
      // 末尾 split 哨兵不是真实行，但两个换行之间的空串代表真实空行。
      expect(normalizeLogLines('a\n').length, 1);
      expect(normalizeLogLines('a\n\nb\n'), ['a\n', '\n', 'b\n']);
      expect(normalizeLogLines('\n'), ['\n']);
      expect(normalizeLogLines(''), isEmpty);
    });

    test('超宽的 ASCII 行按上限折行', () {
      // 子进程 stdout（pip / uvicorn）不经 rich，没有任何宽度约束
      const total = kLogLineWidthLimit * 2 + 40;
      final lines = normalizeLogLines('${'a' * total}\n');
      expect(lines.length, 3, reason: '应折成 上限+上限+余量 三行');
      for (final line in lines) {
        expect(logDisplayWidth(line.trimRight()),
            lessThanOrEqualTo(kLogLineWidthLimit));
      }
      // 折行不能丢字符
      expect(lines.map((l) => l.trimRight()).join(''), 'a' * total);
    });

    test('超宽的中文行按显示宽度折，且不切开字符', () {
      // 按字符数折会切出「上限个」汉字 = 两倍列宽，仍然超宽
      const count = kLogLineWidthLimit; // 汉字数 = 上限，占两倍列宽必然要折
      final lines = normalizeLogLines('${'中' * count}\n');
      for (final line in lines) {
        expect(logDisplayWidth(line.trimRight()),
            lessThanOrEqualTo(kLogLineWidthLimit));
      }
      expect(lines.map((l) => l.trimRight()).join(''), '中' * count);
    });

    test('宽字符跨越边界时整字符移到下一行，不切出半个代理对', () {
      // 上限-1 列 ASCII + 一个汉字：汉字占 2 列放不下，必须整个挪到下一行。
      // 若按 UTF-16 code unit 切，emoji / CJK 扩展区会被切成半个代理对变乱码
      final head = 'a' * (kLogLineWidthLimit - 1);
      final lines = normalizeLogLines('$head中\n');
      expect(lines.length, 2);
      expect(lines[0].trimRight(), head);
      expect(lines[1].trimRight(), '中');
    });

    test('每行都带结尾换行符，copyLogs 才能还原成多行', () {
      for (final line
          in normalizeLogLines('${'a' * (kLogLineWidthLimit * 2)}\n')) {
        expect(line.endsWith('\n'), isTrue);
      }
    });
  });

  group('过滤补位空行（信息密度）', () {
    test('内容满宽后的补位空格不折出纯空白第二行', () {
      // 回归锚点：rich 把每行补到恰好定宽，若原样进折行分支，
      // 「满宽内容 + 补位空格」会折出一行纯空格 —— 屏幕上就是每条日志
      // 后面跟一个空行，信息密度直接砍半。用户报的就是这个。
      final full = 'a' * kLogLineWidthLimit;
      final lines = normalizeLogLines('$full     \n');
      expect(lines.length, 1, reason: '尾随补位空格不该单独成行，实际折出 ${lines.length} 行');
      expect(lines.single.trimRight(), full);
    });

    test('Rich 补位行不产生纯空白元素', () {
      const limit = kLogLineWidthLimit;
      final samples = [
        '${'a' * limit}          \n', // Rich 补位
        '${'中' * (limit ~/ 2)}     \n', // 中文满宽 + 补位
        '${'a' * (limit * 2)}        \n', // 超宽且末片全空格
        'x   \n', // 短行带尾随空格
        '   \n', // 整行只有空格
        'a\r\n', // Windows 换行残留
      ];
      for (final s in samples) {
        for (final line in normalizeLogLines(s)) {
          expect(line.trimRight(), isNotEmpty,
              reason: '输入 ${s.replaceAll(' ', '·')} 折出了补位空行');
        }
      }
    });

    test('补位空白行丢弃，但真实空行保留', () {
      // 非空字符串剥掉补位后为空，才视为 Rich 补位产物。
      expect(normalizeLogLines('   \n'), isEmpty);
      expect(normalizeLogLines('\r\n'), isEmpty);
      expect(normalizeLogLines('\n'), ['\n']);
    });
  });

  group('不补位（不制造不可见的尾随空白）', () {
    test('短行不被补空格到定宽', () {
      // 补位在渲染上毫无效果：Flutter 算文本宽度时忽略尾随空白，
      // 补到满宽也不会触发省略号（实测）。列对齐靠等宽字体 + 后端 ljust(8)
      // 的定宽级别字段，与补位无关。补了只会让每行都膨胀到上限长度
      // （缓冲上限 1000 行，全补满是白花的内存），并让 copyLogs 复制出尾随空白。
      final lines = normalizeLogLines('short\n');
      expect(lines.single, 'short\n');
    });

    test('后端补到满宽的行，补位被剥掉只留正文', () {
      // rich 把每行补到恰好定宽推过来，前端存原文即可
      final lines = normalizeLogLines('msg${' ' * 100}\n');
      expect(lines.single, 'msg\n');
    });

    test('折行产生的续行也不补位', () {
      final lines = normalizeLogLines('${'a' * (kLogLineWidthLimit + 40)}\n');
      expect(lines.length, 2);
      expect(lines[0], '${'a' * kLogLineWidthLimit}\n');
      expect(lines[1], '${'a' * 40}\n', reason: '末片按实际长度，不补到定宽');
    });
  });

  group('行首格式契约', () {
    // 用户明确要求的最终显示格式：`WARNING |07:42:27.3| 内容`
    //   级别固定 8 列、时间戳保留 1 位毫秒、两个分隔符位置不变。
    //
    // 回归锚点：后端 rich 曾按「单词」折行（rich/_wrap.py 的 \s*\S+\s*），
    // 中文整段没有空格算一个 68 列的单词，行首 23 列后放不下就整体换行，
    // 第一行只剩 `WARNING |07:42:27.350|`、正文掉到第二行且不带行首 ——
    // 格式就是这么被破坏的。修复是后端 soft_wrap 整行推出（见 OAS
    // module/logger.py 的 FlutterHandler），折行全部交给这里。
    //
    // 完整字符串级别的格式回归由用户另行补充，这里只锁「归一不破坏行首」。
    test('归一不得让行首独占一行，正文必须留在第一行', () {
      // 后端修好后推来的真实形状：整行不折、无补位
      const payload =
          'WARNING |08:18:10.103| 这是一条比较长的中文日志内容用来触发后端折行看看行首装饰到底占多少列\n';
      final lines = normalizeLogLines(payload);

      expect(lines.first.startsWith('WARNING |08:18:10.103| '), isTrue,
          reason: '第一行必须是完整行首，实际: ${lines.first}');
      // 行首之后必须还有正文 —— 这正是「行首独占一行」的判据
      final body = lines.first.substring('WARNING |08:18:10.103| '.length);
      expect(body.trimRight(), isNotEmpty,
          reason: '第一行行首之后必须有正文，否则又退回「行首独占一行」');
      // 折行不丢内容
      expect(lines.map((l) => l.trimRight()).join(''),
          payload.trimRight().replaceAll('\n', ''));
    });

    test('短行原样保留，行首与正文之间的单空格不被吃掉', () {
      const payload = 'INFO    |08:18:10.101| 任务开始\n';
      expect(normalizeLogLines(payload).single, payload,
          reason: '常见短行必须逐字节原样通过');
    });

    test('CRITICAL 也是 8 列，分隔符列位与其它级别一致', () {
      // CRITICAL 恰好 8 字符，%(levelname)-8s 不再补空格；
      // 若前端另行补位就会让它比其它级别多一列，破坏列对齐。
      const critical = 'CRITICAL|08:18:10.108| 内容\n';
      const info = 'INFO    |08:18:10.108| 内容\n';
      expect(normalizeLogLines(critical).single, critical);
      expect(normalizeLogLines(info).single, info);
      // 两者第一个 `|` 的列位必须相同
      expect(critical.indexOf('|'), info.indexOf('|'),
          reason: '级别字段必须恒为 8 列，分隔符才能成列');
    });
  });
}
