import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/model/stats/script_statistics_models.dart';

void main() {
  // 中文注释：锁定全天视图优先使用后端 total_duration_seconds，旧响应缺失时才回退账号累加。
  test('all-day prefers backend total duration then falls back to account fold', () {
    final multiWithBackendTotal = ScriptMultiStatistics(
      accounts: [
        ScriptMultiAccountStatistics(
          account: 'acc-1',
          character: '角色1',
          svr: '区服1',
          switchOk: true,
          durationSeconds: 1200,
          errorCount: 1,
          battleCount: 5,
          battleTotalDurationSeconds: 500,
          battleAvgDurationSeconds: 100,
          coopTotal: 0,
          tasks: const [],
          errors: const [],
          coops: const [],
          mshops: const [],
          segments: const [],
        ),
        ScriptMultiAccountStatistics(
          account: 'acc-2',
          character: '角色2',
          svr: '区服2',
          switchOk: true,
          durationSeconds: 1000,
          errorCount: 0,
          battleCount: 3,
          battleTotalDurationSeconds: 240,
          battleAvgDurationSeconds: 80,
          coopTotal: 0,
          tasks: const [],
          errors: const [],
          coops: const [],
          mshops: const [],
          segments: const [],
        ),
      ],
      sessions: const [],
      totalDurationSeconds: 1800,
    );

    final allDay = filterMultiAccountSessionData(
      multi: multiWithBackendTotal,
      sessionIndex: null,
    );
    expect(allDay.totalDurationSeconds, equals(1800));
    expect(allDay.accounts, hasLength(2));

    final multiWithoutBackendTotal = ScriptMultiStatistics(
      accounts: multiWithBackendTotal.accounts,
      sessions: const [],
      totalDurationSeconds: 0,
    );
    final fallbackAllDay = filterMultiAccountSessionData(
      multi: multiWithoutBackendTotal,
      sessionIndex: null,
    );
    expect(fallbackAllDay.totalDurationSeconds, equals(2200));
  });

  // 中文注释：锁定 session 视图必须剔除没有命中该 session 的账号，且按筛选后账号重算总耗时。
  test('session view removes accounts without matching session records', () {
    final multi = ScriptMultiStatistics(
      accounts: [
        ScriptMultiAccountStatistics(
          account: 'acc-1',
          character: '角色1',
          svr: '区服1',
          switchOk: true,
          durationSeconds: 1200,
          errorCount: 1,
          battleCount: 5,
          battleTotalDurationSeconds: 500,
          battleAvgDurationSeconds: 100,
          coopTotal: 1,
          tasks: [
            ScriptMultiTaskRecord(
              task: 'DailyTask',
              ok: true,
              startTime: '2026-06-23 06:05:00.000',
              durationSeconds: 300,
              battleCount: 2,
              battleTotalDurationSeconds: 120,
              battleAvgDurationSeconds: 60,
            ),
          ],
          errors: const [],
          coops: [
            ScriptMultiCoopRecord(
              ctype: 'daily',
              real: false,
              time: '2026-06-23 06:06:00.000',
            ),
          ],
          mshops: [
            ScriptMultiMshopRecord(
              goods: 'item-a',
              price: 10,
              time: '2026-06-23 06:07:00.000',
            ),
          ],
          segments: [
            ScriptMultiSegmentRecord(
              startTimeText: '2026-06-23 06:00:00.000',
              endTimeText: '2026-06-23 06:10:00.000',
              durationSeconds: 600,
              session: 1,
              startTime: DateTime.parse('2026-06-23T06:00:00.000'),
              endTime: DateTime.parse('2026-06-23T06:10:00.000'),
            ),
          ],
        ),
        ScriptMultiAccountStatistics(
          account: 'acc-2',
          character: '角色2',
          svr: '区服2',
          switchOk: true,
          durationSeconds: 1000,
          errorCount: 0,
          battleCount: 3,
          battleTotalDurationSeconds: 240,
          battleAvgDurationSeconds: 80,
          coopTotal: 0,
          tasks: const [],
          errors: const [],
          coops: const [],
          mshops: const [],
          segments: [
            ScriptMultiSegmentRecord(
              startTimeText: '2026-06-23 07:00:00.000',
              endTimeText: '2026-06-23 07:10:00.000',
              durationSeconds: 400,
              session: 2,
              startTime: DateTime.parse('2026-06-23T07:00:00.000'),
              endTime: DateTime.parse('2026-06-23T07:10:00.000'),
            ),
          ],
        ),
      ],
      sessions: [
        ScriptMultiSessionRecord(
          index: 1,
          startTimeText: '2026-06-23 06:00:00.000',
          endTimeText: '2026-06-23 06:10:00.000',
          durationSeconds: 600,
          accountCount: 1,
          startTime: DateTime.parse('2026-06-23T06:00:00.000'),
        ),
        ScriptMultiSessionRecord(
          index: 2,
          startTimeText: '2026-06-23 07:00:00.000',
          endTimeText: '2026-06-23 07:10:00.000',
          durationSeconds: 400,
          accountCount: 1,
          startTime: DateTime.parse('2026-06-23T07:00:00.000'),
        ),
      ],
      totalDurationSeconds: 1000,
    );

    final sessionView = filterMultiAccountSessionData(
      multi: multi,
      sessionIndex: 1,
    );

    expect(sessionView.accounts, hasLength(1));
    expect(sessionView.accounts.first.account, equals('acc-1'));
    expect(sessionView.totalDurationSeconds, equals(600));
    expect(sessionView.accounts.first.tasks, hasLength(1));
    expect(sessionView.accounts.first.coops, hasLength(1));
    expect(sessionView.accounts.first.mshops, hasLength(1));
    expect(sessionView.accounts.first.errorCount, equals(0));
    expect(sessionView.accounts.first.errors, isEmpty);
  });
}
