import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/model/stats/script_statistics_models.dart';

void main() {
  // 中文注释：锁定 snapshot -> domain model 契约，确保普通任务统计快照可被解析。
  test('parses task snapshot with runs and battle summary', () {
    final raw = <String, dynamic>{
      'script_name': 'oas1',
      'total_runtime_seconds': 3600,
      'total_task_run_count': 3,
      'total_battle_count': 50,
      'tasks': {
        'DailyTask': {
          'run_count': 2,
          'total_duration_seconds': 1800,
          'battle': {
            'count': 30,
            'avg_duration_seconds': 12,
          },
          'runs': [
            {
              'start_time': '2026-06-23 06:00:00.000',
              'end_time': '2026-06-23 06:10:00.000',
              'duration_seconds': 600,
            },
          ],
        },
      },
      'multi': {
        'accounts': [],
        'sessions': [],
        'total_duration_seconds': 0,
      },
    };

    final statisticsDay = ScriptStatisticsDay.fromSnapshotJson(
      raw,
      dateKey: '2026-06-23',
    );

    expect(statisticsDay.scriptName, equals('oas1'));
    expect(statisticsDay.dateKey, equals('2026-06-23'));
    expect(statisticsDay.totalRuntimeSeconds, equals(3600));
    expect(statisticsDay.totalTaskRunCount, equals(3));
    expect(statisticsDay.totalBattleCount, equals(50));
    expect(statisticsDay.tasks.containsKey('DailyTask'), isTrue);

    final task = statisticsDay.tasks['DailyTask']!;
    expect(task.runCount, equals(2));
    expect(task.totalDurationSeconds, equals(1800));
    expect(task.battle?.count, equals(30));
    expect(task.battle?.avgDurationSeconds, equals(12));
    expect(task.runs, hasLength(1));
    expect(task.runs.first.startTimeText, equals('2026-06-23 06:00:00.000'));
    expect(task.runs.first.endTimeText, equals('2026-06-23 06:10:00.000'));
    expect(task.runs.first.durationSeconds, equals(600));
    expect(statisticsDay.multi, isNotNull);
  });
}
