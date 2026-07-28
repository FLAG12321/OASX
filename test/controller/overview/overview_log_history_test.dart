import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/api/script_log_models.dart';
import 'package:oasx/model/script_model.dart';
import 'package:oasx/views/overview/overview_view.dart';

void main() {
  // 中文注释：锁定打开 Logs 时加载最新历史窗口。
  test('loadLatestHistoricalLogs prepends latest history before existing live logs', () async {
    final controller = OverviewController(
      name: 'oas1',
      scriptModelOverride: ScriptModel('oas1'),
      loadLogWindow: (_, {cursor, limitLines = 500}) async {
        expect(cursor, isNull);
        return const ScriptLogWindow(
          lines: [ScriptLogLine(key: 'k1', text: 'INFO: history\n')],
          olderCursor: 'older-token',
          liveCursor: 'live-token',
          reachedStart: false,
        );
      },
    );
    controller.logs.add('INFO: live\n');

    await controller.loadLatestHistoricalLogs();

    expect(controller.logs, ['INFO: history\n', 'INFO: live\n']);
    expect(controller.canLoadOlderLogs, isTrue);
  });

  // 中文注释：锁定历史加载失败时保留已有日志并停止当前失败轮次，避免顶部滚动无限重试。
  test('latest history failure keeps existing logs and disables older loading for that window', () async {
    final controller = OverviewController(
      name: 'oas1',
      scriptModelOverride: ScriptModel('oas1'),
      loadLogWindow: (_, {cursor, limitLines = 500}) async => null,
    );
    controller.logs.add('INFO: live\n');

    await controller.loadLatestHistoricalLogs();

    expect(controller.logs, ['INFO: live\n']);
    expect(controller.canLoadOlderLogs, isFalse);
  });

  // 中文注释：锁定 olderCursor 存在时加载更早窗口并 prepend。
  test('loadOlderHistoricalLogs prepends older window and stops at start', () async {
    final cursors = <String?>[];
    final controller = OverviewController(
      name: 'oas1',
      scriptModelOverride: ScriptModel('oas1'),
      loadLogWindow: (_, {cursor, limitLines = 500}) async {
        cursors.add(cursor);
        if (cursor == null) {
          return const ScriptLogWindow(
            lines: [ScriptLogLine(key: 'latest', text: 'INFO: latest\n')],
            olderCursor: 'older-token',
            liveCursor: null,
            reachedStart: false,
          );
        }
        return const ScriptLogWindow(
          lines: [ScriptLogLine(key: 'older', text: 'INFO: older\n')],
          olderCursor: null,
          liveCursor: null,
          reachedStart: true,
        );
      },
    );

    await controller.loadLatestHistoricalLogs();
    await controller.loadOlderHistoricalLogs();

    expect(cursors, [null, 'older-token']);
    expect(controller.logs, ['INFO: older\n', 'INFO: latest\n']);
    expect(controller.canLoadOlderLogs, isFalse);
  });

  // 中文注释：锁定相同文本但不同 key 的历史行允许共存，相同 key 或已在 UI/pending 中则跳过。
  test('deduplicates by key and visible or pending logs', () async {
    final controller = OverviewController(
      name: 'oas1',
      scriptModelOverride: ScriptModel('oas1'),
      loadLogWindow: (_, {cursor, limitLines = 500}) async {
        return const ScriptLogWindow(
          lines: [
            ScriptLogLine(key: 'k1', text: 'INFO: same\n'),
            ScriptLogLine(key: 'k2', text: 'INFO: same\n'),
            ScriptLogLine(key: 'k3', text: 'INFO: live\n'),
          ],
          olderCursor: null,
          liveCursor: null,
          reachedStart: true,
        );
      },
    );
    controller.logs.add('INFO: live\n');

    await controller.loadLatestHistoricalLogs();

    expect(controller.logs, ['INFO: same\n', 'INFO: same\n', 'INFO: live\n']);
  });

  // 中文注释：锁定 older 窗口只按行级 key 去重：重复文本（如分隔线）即使已可见也保留。
  test('older window keeps duplicate-text lines that are already visible', () async {
    final controller = OverviewController(
      name: 'oas1',
      scriptModelOverride: ScriptModel('oas1'),
      loadLogWindow: (_, {cursor, limitLines = 500}) async {
        if (cursor == null) {
          return const ScriptLogWindow(
            lines: [ScriptLogLine(key: 'sep-1', text: '────\n')],
            olderCursor: 'older-token',
            liveCursor: null,
            reachedStart: false,
          );
        }
        return const ScriptLogWindow(
          lines: [ScriptLogLine(key: 'sep-0', text: '────\n')],
          olderCursor: null,
          liveCursor: null,
          reachedStart: true,
        );
      },
    );

    await controller.loadLatestHistoricalLogs();
    await controller.loadOlderHistoricalLogs();

    expect(controller.logs, ['────\n', '────\n']);
  });

  // 中文注释：锁定历史请求进行中时重复触发不会并发发起第二次请求。
  test('older loading is guarded against concurrent triggers', () async {
    var calls = 0;
    final gate = Completer<ScriptLogWindow?>();
    final controller = OverviewController(
      name: 'oas1',
      scriptModelOverride: ScriptModel('oas1'),
      loadLogWindow: (_, {cursor, limitLines = 500}) {
        calls += 1;
        if (cursor == null) {
          return Future.value(const ScriptLogWindow(
            lines: [],
            olderCursor: 'older-token',
            liveCursor: null,
            reachedStart: false,
          ));
        }
        return gate.future;
      },
    );

    await controller.loadLatestHistoricalLogs();
    final first = controller.loadOlderHistoricalLogs();
    final second = controller.loadOlderHistoricalLogs();
    gate.complete(const ScriptLogWindow(
      lines: [],
      olderCursor: null,
      liveCursor: null,
      reachedStart: true,
    ));
    await Future.wait([first, second]);

    // 中文注释：latest 一次 + older 一次；第二次 older 触发被 _historyLoading 拒绝。
    expect(calls, 2);
  });

  // 中文注释：锁定 UI 头部截断后历史标记失效，下次触发丢弃旧游标从最新窗口重建，
  // 避免截断区段成为本会话不可恢复的日志断层。
  test('trimmed head marks history stale and rebuilds from latest window', () async {
    final cursors = <String?>[];
    final controller = OverviewController(
      name: 'oas1',
      scriptModelOverride: ScriptModel('oas1'),
      loadLogWindow: (_, {cursor, limitLines = 500}) async {
        cursors.add(cursor);
        return const ScriptLogWindow(
          lines: [ScriptLogLine(key: 'k1', text: 'INFO: history\n')],
          olderCursor: 'older-token',
          liveCursor: null,
          reachedStart: false,
        );
      },
    );

    await controller.loadLatestHistoricalLogs();
    controller.logs.clear();
    controller.onUiLogsTrimmedFromHead(1);

    expect(controller.canLoadOlderLogs, isTrue);
    await controller.loadOlderLogs();

    // 中文注释：重建时再次以 cursor=null 请求最新窗口，而非沿用旧 olderCursor；
    // key 集已清空，被截掉的行可重新加载。
    expect(cursors, [null, null]);
    expect(controller.logs, ['INFO: history\n']);
  });

  // 中文注释：锁定 stale 重建先移除 UI 中残留的旧历史区段再拉取最新窗口，
  // 避免新窗口插到旧历史上方造成时间线乱序，或残留行与新窗口重复。
  test('stale rebuild removes residual history before reloading latest', () async {
    var call = 0;
    final controller = OverviewController(
      name: 'oas1',
      scriptModelOverride: ScriptModel('oas1'),
      loadLogWindow: (_, {cursor, limitLines = 500}) async {
        call += 1;
        if (call == 1) {
          return const ScriptLogWindow(
            lines: [
              ScriptLogLine(key: 'h1', text: 'INFO: h1\n'),
              ScriptLogLine(key: 'h2', text: 'INFO: h2\n'),
            ],
            olderCursor: 'older-token',
            liveCursor: null,
            reachedStart: false,
          );
        }
        // 中文注释：文件尾部已前进，重建窗口同时含残留行 h2 与更新的 h3。
        return const ScriptLogWindow(
          lines: [
            ScriptLogLine(key: 'h2', text: 'INFO: h2\n'),
            ScriptLogLine(key: 'h3', text: 'INFO: h3\n'),
          ],
          olderCursor: null,
          liveCursor: null,
          reachedStart: true,
        );
      },
    );
    controller.logs.add('INFO: live\n');

    await controller.loadLatestHistoricalLogs();
    expect(controller.logs, ['INFO: h1\n', 'INFO: h2\n', 'INFO: live\n']);

    // 中文注释：模拟 LogMixin 截断头部 1 行（h1），h2 成为残留历史。
    controller.logs.removeRange(0, 1);
    controller.onUiLogsTrimmedFromHead(1);

    await controller.loadOlderLogs();

    // 中文注释：残留 h2 先被移除再重建，时间线单调且无重复。
    expect(controller.logs, ['INFO: h2\n', 'INFO: h3\n', 'INFO: live\n']);
  });

  // 中文注释：锁定 clearLog 后历史状态整体重置，可从最新窗口重新加载同样内容。
  test('clearLog resets history continuity for reload', () async {
    final cursors = <String?>[];
    final controller = OverviewController(
      name: 'oas1',
      scriptModelOverride: ScriptModel('oas1'),
      loadLogWindow: (_, {cursor, limitLines = 500}) async {
        cursors.add(cursor);
        return const ScriptLogWindow(
          lines: [ScriptLogLine(key: 'k1', text: 'INFO: history\n')],
          olderCursor: null,
          liveCursor: null,
          reachedStart: true,
        );
      },
    );

    await controller.loadLatestHistoricalLogs();
    controller.clearLog();

    expect(controller.logs, isEmpty);
    expect(controller.canLoadOlderLogs, isTrue);

    await controller.loadOlderLogs();

    expect(cursors, [null, null]);
    expect(controller.logs, ['INFO: history\n']);
  });
}
