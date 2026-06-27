/// 单条脚本运行日志行。
class ScriptLogLine {
  const ScriptLogLine({required this.key, required this.text});

  /// 后端文件位置组合成的稳定 key，用于历史窗口与实时日志去重。
  final String key;

  /// 日志原始文本（含换行），用于 LogWidget 渲染。
  final String text;

  factory ScriptLogLine.fromJson(Map<String, dynamic> json) {
    final fileName = (json['file_name'] ?? '').toString();
    final lineNo = (json['line_no'] ?? '').toString();
    final offset = (json['offset'] ?? '').toString();
    final byteLength = (json['byte_length'] ?? '').toString();
    final text = (json['text'] ?? '').toString();
    // 中文注释：后端实测必返回 file_name/line_no/offset/byte_length 四个定位字段；
    // 仅当全部缺失时才退化为 text 兜底，此时该行无法跨窗口稳定去重。
    final key = [fileName, lineNo, offset, byteLength]
        .where((part) => part.isNotEmpty)
        .join(':');
    return ScriptLogLine(key: key.isEmpty ? text : key, text: text);
  }
}

/// 脚本历史日志窗口。
class ScriptLogWindow {
  const ScriptLogWindow({
    required this.lines,
    required this.olderCursor,
    required this.liveCursor,
    required this.reachedStart,
  });

  final List<ScriptLogLine> lines;
  final String? olderCursor;
  final String? liveCursor;
  final bool reachedStart;

  factory ScriptLogWindow.fromWindowJson(Map<String, dynamic> json) {
    final rawLines = json['lines'];
    final lines = <ScriptLogLine>[];
    if (rawLines is List) {
      lines.addAll(rawLines
          .whereType<Map<String, dynamic>>()
          .map(ScriptLogLine.fromJson));
    }
    final reachedStart = json['reached_start'] == true;
    return ScriptLogWindow(
      lines: lines,
      // 中文注释：到达起点时清空 olderCursor，避免上层继续请求更早窗口。
      olderCursor: reachedStart ? null : json['older_cursor']?.toString(),
      liveCursor: json['live_cursor']?.toString(),
      reachedStart: reachedStart,
    );
  }
}
