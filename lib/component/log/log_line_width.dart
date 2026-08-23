/// 日志行宽归一：把后端推来的一段日志切成「每行都不超过分隔线宽度」的多行。
///
/// 为什么需要它：后端普通日志为保护 `WARNING |时间| 正文` 的 CJK 行首，
/// 已改成不经 rich 折行、整行推给前端；`ServerLauncher` 的子进程 stdout
/// （pip / uvicorn / traceback）同样没有宽度约束。另有少数载荷本身含多个 `\n`。
///
/// 前端 `logs` 的一个元素必须恰好是一行（`prototypeItem` + `maxLines: 1`），
/// 否则超宽或多行载荷会被省略号吃掉。
///
/// 因此这里做两件事：按 `\n` 拆行，再把仍然超宽的行按显示宽度硬折。
/// 处理后每个元素恰好是可渲染的一行，`maxLines: 1` 与 `prototypeItem`
/// 的「一元素一行、等高」不变式得以保持——这是整套滚动/视口补偿机制的前提，
/// 所以归一必须放在入库侧，而不是渲染侧把一个元素摊成多行。
library;

/// 分隔线宽度，也是日志行宽的硬上限（单位：显示列）。
///
/// 必须与后端 `GUI_RULE_WIDTH`（OAS `module/logger.py`）严格相等：
///   `GUI_LOG_WIDTH`  = 80，只约束 traceback 定宽框
///   `GUI_RULE_WIDTH` = 80，START/RESTART 分隔线总宽
///
/// 普通后端日志与子进程 stdout 都可能超过 80 列，本上限负责把它们折到分隔线内。
/// 前端若设得更窄会过早折行；更宽则输出会溢出分隔线。
/// **改这里必须同步改后端 `GUI_RULE_WIDTH`。**
///
/// 配套正文字号 12（见 LogContent._selectStyle）：Cascadia 每字符宽 0.5859em，
/// 80 列约 562px，1280 宽的窗口装得下，不必横向滚动。
const int kLogLineWidthLimit = 80;

/// 单个字符占的显示列数：东亚宽/全角字符占 2 列，其余占 1 列。
///
/// 与后端 `rich.cells.cell_len` 的显示列口径对齐。前端若按 UTF-16 code unit
/// 计数，一行中文会被当成半数列宽而放过，
/// 实际渲染却是满宽，等于没折。
///
/// 只覆盖真正会出现在日志里的宽字符区段（CJK、假名、谚文、全角形式）。
/// 组合附加符号（U+0300–U+036F 等零宽字符）不做 0 列处理：日志里不会出现，
/// 多写一个分支只是增加没有测试覆盖的代码。
int logCharWidth(int rune) {
  // 快路径：ASCII 恒为 1 列，日志绝大多数字符走这里
  if (rune < 0x1100) return 1;
  if ((rune >= 0x1100 && rune <= 0x115F) || // 谚文字母 Jamo
          (rune >= 0x2E80 && rune <= 0xA4CF) || // CJK 部首 … 彝文
          (rune >= 0xAC00 && rune <= 0xD7A3) || // 谚文音节
          (rune >= 0xF900 && rune <= 0xFAFF) || // CJK 兼容表意文字
          (rune >= 0xFE30 && rune <= 0xFE6F) || // CJK 兼容形式
          (rune >= 0xFF00 && rune <= 0xFF60) || // 全角形式
          (rune >= 0xFFE0 && rune <= 0xFFE6) || // 全角符号
          (rune >= 0x1F300 && rune <= 0x1F64F) || // emoji 图形/表情
          (rune >= 0x1F900 && rune <= 0x1F9FF) || // 补充符号与象形
          (rune >= 0x20000 && rune <= 0x3FFFD) // CJK 扩展 B 及以后
      ) {
    return 2;
  }
  return 1;
}

/// 字符串的显示宽度（列数）。
int logDisplayWidth(String text) {
  int width = 0;
  for (final rune in text.runes) {
    width += logCharWidth(rune);
  }
  return width;
}

/// 把一段日志载荷归一成若干行，每行显示宽度都不超过 [kLogLineWidthLimit] 列。
///
/// 刻意**不**把短行补空格到定宽：尾随空格在渲染上完全不可见（Flutter 的文本
/// 布局在算宽度时忽略尾随空白，实测补到满宽也不会触发省略号），列对齐靠的是
/// 等宽字体加后端 `ljust(8)` 的定宽级别字段，与补位无关。补位只会让每行都膨胀
/// 到上限长度（日志缓冲上限 1000 行，全补满是白花的内存），并让 `copyLogs`
/// 复制出一堆尾随空白。
///
/// 返回的每一行都保留结尾 `\n`：`LogMixin.copyLogs` 用 `logs.join("")` 复制，
/// 靠各行自带换行符还原原文。
///
/// 只有确实超宽的行（普通后端日志或子进程 stdout）会被插入新换行符，复制结果比原文多
/// 换行——这正是「超过了请另起一行」要的效果。
List<String> normalizeLogLines(String payload) {
  if (payload.isEmpty) return const [];
  final result = <String>[];
  final rawLines = payload.split('\n');
  // 末尾换行会让 split 额外产生一个空字符串；它只是分隔符哨兵，
  // 不代表又有一条真实空行。中间的空字符串必须保留，才能保留真实空行。
  final lineCount =
      payload.endsWith('\n') ? rawLines.length - 1 : rawLines.length;
  for (var i = 0; i < lineCount; i++) {
    final rawLine = rawLines[i];
    // 空字符串代表真实空行，不要与 Rich 生成的“全是补位空格”混为一谈。
    if (rawLine.isEmpty) {
      result.add('\n');
      continue;
    }

    // 必须先剥尾随空格再判宽度：Rich 把每行补到定宽，若带着补位进折行分支，
    // “满宽内容 + 补位空格”会折出纯空白的第二行。
    final trimmed = _trimTrailingSpaces(rawLine);
    // 非空行被剥完只剩空格或 Windows 的 \r，视为 Rich 补位行而丢弃；
    // 真实空行已经在上面的 rawLine.isEmpty 分支保留。
    if (trimmed.isEmpty) continue;
    // 绝大多数行（后端已折好的定宽行）在这里直接过，不进入逐字符切分。
    if (logDisplayWidth(trimmed) <= kLogLineWidthLimit) {
      result.add('$trimmed\n');
      continue;
    }
    result.addAll(_hardWrap(trimmed));
  }
  return result;
}

/// 只剥尾随的半角空格与 `\r`，不用 trimRight()。
///
/// trimRight() 会把制表符、全角空格一并吃掉：Windows 子进程 stdout 常带 `\r`，
/// 剥掉正好；但把正文里有意义的全角空格也剥掉就改了日志原文。
String _trimTrailingSpaces(String line) {
  int end = line.length;
  while (end > 0 && (line[end - 1] == ' ' || line[end - 1] == '\r')) {
    end--;
  }
  return line.substring(0, end);
}

/// 按显示宽度硬折一行超宽文本，每片都带结尾 `\n`。
///
/// 按显示宽度而非字符数累加，宽字符跨越边界时整字符移到下一行——不切开字符，
/// 否则会切出半个 UTF-16 代理对（emoji / CJK 扩展区）变成乱码。
List<String> _hardWrap(String line) {
  final pieces = <String>[];
  final buffer = StringBuffer();
  int width = 0;
  for (final rune in line.runes) {
    final w = logCharWidth(rune);
    // 放不下就先收本行，再从当前字符开始新行
    if (width + w > kLogLineWidthLimit) {
      pieces.add('$buffer\n');
      buffer.clear();
      width = 0;
    }
    buffer.writeCharCode(rune);
    width += w;
  }
  // 末片可能全是空格（原行以空格结尾时），补位产物不单独成行
  if (buffer.isNotEmpty) {
    final tail = _trimTrailingSpaces(buffer.toString());
    if (tail.isNotEmpty) pieces.add('$tail\n');
  }
  return pieces;
}
