/// 日志行宽归一：把后端推来的一段日志切成「每行都不超过分隔线宽度」的多行。
///
/// 为什么需要它：后端 rich 按 `GUI_LOG_WIDTH` 渲染（OAS `module/logger.py`，
/// `set_func_logger` 的 `Console(width=...)` 与 START/RESTART 分隔线的
/// `GuiRule` 共用这一个常量），一条超长消息在后端就已被折成若干定宽的行，
/// 并用 `\n` 拼在**同一个**回调载荷里推给前端。而前端 `logs` 的一个元素就是
/// 一行（`prototypeItem` + `maxLines: 1`），于是整段多行被塞进一行渲染，
/// 只看得见第一行、其余被省略号吃掉。
///
/// 另一类来源不经过 rich：`ServerLauncher` 把子进程 stdout 直接 `INFO: $event`
/// 推进来（pip / uvicorn / traceback），完全没有宽度约束，同样会超出分隔线。
///
/// 因此这里做两件事：按 `\n` 拆行，再把仍然超宽的行按显示宽度硬折。
/// 处理后每个元素恰好是可渲染的一行，`maxLines: 1` 与 `prototypeItem`
/// 的「一元素一行、等高」不变式得以保持——这是整套滚动/视口补偿机制的前提，
/// 所以归一必须放在入库侧，而不是渲染侧把一个元素摊成多行。
library;

/// 分隔线宽度，也是日志行宽的硬上限（单位：显示列）。
///
/// 必须与后端 `GUI_RULE_WIDTH`（OAS `module/logger.py`）严格相等。后端把宽度拆成
/// 两个常量但取值相同：
///   `GUI_LOG_WIDTH`  = 80，推给前端的 `Console(width=...)`，消息按它折行
///   `GUI_RULE_WIDTH` = 80，分隔线总宽，与日志行同宽
///
/// 所以经过 rich 的日志行到前端时已经 ≤80 列，本上限对它们从不生效；
/// 真正会撞上的是 `ServerLauncher` 直推的子进程 stdout（pip / uvicorn /
/// traceback），那类完全没有宽度约束，超出分隔线才折。
/// 前端若设得更窄会把后端折好的行再折一次；更宽则子进程输出溢出分隔线。
/// **改这里必须同步改后端 `GUI_RULE_WIDTH`。**
///
/// 配套正文字号 12（见 LogContent._selectStyle）：Cascadia 每字符宽 0.5859em，
/// 80 列约 562px，1280 宽的窗口装得下，不必横向滚动。
const int kLogLineWidthLimit = 80;

/// 单个字符占的显示列数：东亚宽/全角字符占 2 列，其余占 1 列。
///
/// 与后端 `rich.cells.cell_len` 的口径对齐——后端正是按这个宽度折行的，
/// 前端若按 UTF-16 code unit 计数，一行中文会被当成半数列宽而放过，
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
/// 只有确实超宽的行（子进程 stdout）会被插入新换行符，此时复制结果比原文多
/// 换行——这正是「超过了请另起一行」要的效果。
List<String> normalizeLogLines(String payload) {
  if (payload.isEmpty) return const [];
  final result = <String>[];
  // split('\n') 对 'a\nb\n' 得到 ['a','b','']，末尾空串是行尾换行符的产物，
  // 不是真实空行，必须跳过，否则每条日志后面都会多出一个空行
  for (final rawLine in payload.split('\n')) {
    if (rawLine.isEmpty) continue;
    // 必须先剥尾随空格再判宽度：rich 把每行补到恰好定宽，若带着补位进折行分支，
    // 「满宽内容 + 补位空格」会折出纯空白的第二行 —— 屏幕上就是每条日志后面
    // 跟一个空行，信息密度直接砍半（用户报的就是这个）。
    final trimmed = _trimTrailingSpaces(rawLine);
    // 整行只有空白：它是补位产物而非真实空行，直接丢弃
    if (trimmed.isEmpty) continue;
    // 绝大多数行（后端已折好的定宽行）在这里直接过，不进入逐字符切分
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
