import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/controller/stats/stats_page_controller.dart';

void main() {
  // 中文注释：锁定 controller 启动后必须按日期降序选择最新日期，而不是盲信后端原始顺序。
  test('bootstrap sorts dates descending and selects newest day', () async {
    final controller = StatsPageController(
      loadDates: (_) async => ['2026-06-22', '2026-06-24', '2026-06-23'],
      loadDay: (_, dateKey) async => _buildDayRaw(totalSeconds: dateKey == '2026-06-24' ? 24 : 1),
    );

    await controller.bootstrap('oas1');

    expect(controller.availableDateKeys, ['2026-06-24', '2026-06-23', '2026-06-22']);
    expect(controller.selectedDateKey.value, '2026-06-24');
    expect(controller.statistics.value?.totalRuntimeSeconds, 24);
  });

  // 中文注释：锁定多账号入口显隐应由已解析的 snapshot multi 数据决定。
  test('hasMultiAccountEntry depends on parsed snapshot multi data', () async {
    final controller = StatsPageController(
      loadDates: (_) async => ['2026-06-24'],
      loadDay: (_, __) async => _buildDayRaw(withMulti: true),
    );

    await controller.bootstrap('oas1');

    expect(controller.hasMultiAccountEntry, isTrue);
  });

  // 中文注释：锁定统计页开启自动刷新后会按间隔拉取当天快照，关闭后不再继续请求。
  test('auto refresh polls while enabled and stops after disabled', () {
    fakeAsync((async) {
      var callCount = 0;
      final controller = StatsPageController(
        autoRefreshInterval: const Duration(seconds: 2),
        loadDates: (_) async => ['2026-06-24'],
        loadDay: (_, __) async {
          callCount += 1;
          return _buildDayRaw(totalSeconds: callCount.toDouble());
        },
      );

      controller.bootstrap('oas1');
      async.flushMicrotasks();

      expect(callCount, 1);
      expect(controller.statistics.value?.totalRuntimeSeconds, 1);

      controller.startAutoRefresh();
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      expect(callCount, 2);
      expect(controller.statistics.value?.totalRuntimeSeconds, 2);

      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      expect(callCount, 3);
      expect(controller.statistics.value?.totalRuntimeSeconds, 3);

      controller.stopAutoRefresh();
      async.elapse(const Duration(seconds: 4));
      async.flushMicrotasks();
      expect(callCount, 3);
    });
  });
}

Map<String, dynamic> _buildDayRaw({
  double totalSeconds = 0,
  bool withMulti = false,
}) {
  return {
    'script_name': 'oas1',
    'total_runtime_seconds': totalSeconds,
    'total_task_run_count': 1,
    'total_battle_count': 0,
    'tasks': {
      'DailyTask': {
        'run_count': 1,
        'total_duration_seconds': totalSeconds,
        'battle': {
          'count': 0,
          'avg_duration_seconds': 0,
        },
        'runs': [
          {
            'start_time': '2026-06-24 10:00:00',
            'end_time': '2026-06-24 10:00:10',
            'duration_seconds': 10,
            'battle': {
              'count': 0,
              'avg_duration_seconds': 0,
            },
          },
        ],
      },
    },
    'multi': withMulti
        ? {
            'total_duration_seconds': totalSeconds,
            'sessions': [],
            'accounts': [
              {
                'account': 'acc1',
                'character': '角色1',
                'svr': '一区',
                'switch_ok': true,
                'duration_seconds': totalSeconds,
                'error_count': 0,
                'battle_count': 0,
                'battle_total_duration_seconds': 0,
                'battle_avg_duration_seconds': 0,
                'coop_total': 0,
                'tasks': [],
                'errors': [],
                'coops': [],
                'mshops': [],
                'segments': [],
              },
            ],
          }
        : null,
  };
}
