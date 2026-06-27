import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/api/api_client.dart';
import 'package:oasx/api/script_log_models.dart';

void main() {
  // 中文注释：锁定日志窗口 model 保留后端行级 key，避免相同文本被误判重复。
  test('ScriptLogWindow parses text cursors and stable line keys', () {
    final window = ScriptLogWindow.fromWindowJson({
      'older_cursor': 'older-token',
      'live_cursor': 'live-token',
      'reached_start': false,
      'lines': [
        {
          'file_name': '2026-06-27_oas1.txt',
          'line_no': 1,
          'offset': 10,
          'byte_length': 8,
          'text': 'INFO: same\n',
        },
        {
          'file_name': '2026-06-27_oas1.txt',
          'line_no': 2,
          'offset': 20,
          'byte_length': 8,
          'text': 'INFO: same\n',
        },
      ],
    });

    expect(window.olderCursor, 'older-token');
    expect(window.liveCursor, 'live-token');
    expect(window.reachedStart, isFalse);
    expect(window.lines.map((line) => line.text), ['INFO: same\n', 'INFO: same\n']);
    expect(window.lines[0].key, isNot(window.lines[1].key));
  });

  // 中文注释：锁定 reached_start=true 时不再暴露 olderCursor。
  test('reached start clears older cursor', () {
    final window = ScriptLogWindow.fromWindowJson({
      'older_cursor': 'older-token',
      'reached_start': true,
      'lines': [],
    });

    expect(window.reachedStart, isTrue);
    expect(window.olderCursor, isNull);
  });

  // 中文注释：ApiClient helper 纯构造路径与 query，不实例化网络客户端。
  test('ApiClient builds log window path and query without network', () {
    expect(ApiClient.buildScriptLogWindowPath('oas 1'), '/logs/oas%201');
    expect(ApiClient.buildScriptLogWindowQuery(), {'limit_lines': 500});
    expect(
      ApiClient.buildScriptLogWindowQuery(cursor: 'older', limitLines: 200),
      {'limit_lines': 200, 'cursor': 'older'},
    );
  });
}
