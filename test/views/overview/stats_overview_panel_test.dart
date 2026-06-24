import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:oasx/controller/stats/stats_page_controller.dart';
import 'package:oasx/views/overview/stats_overview_panel.dart';

void main() {
  tearDown(() async {
    await Get.delete<StatsPageController>(tag: 'oas1', force: true);
    Get.reset();
  });

  // 中文注释：锁定后台刷新时页面应保持已渲染数据，不再闪回整页“正在加载统计”占位。
  testWidgets('keeps rendered stats visible during background refresh', (tester) async {
    final firstLoadDone = Completer<void>();
    final releaseSecondLoad = Completer<void>();
    var callCount = 0;

    final controller = StatsPageController(
      loadDates: (_) async => ['2026-06-24'],
      loadDay: (_, __) async {
        callCount += 1;
        if (callCount == 1) {
          firstLoadDone.complete();
          return _buildDayRaw(totalSeconds: 10);
        }
        await releaseSecondLoad.future;
        return _buildDayRaw(totalSeconds: 20);
      },
    );
    Get.put(controller, tag: 'oas1');

    await tester.pumpWidget(
      const GetMaterialApp(
        home: Scaffold(
          body: StatsOverviewPanel(scriptName: 'oas1'),
        ),
      ),
    );

    await firstLoadDone.future;
    await tester.pump();
    await tester.pump();

    expect(find.text('10s'), findsWidgets);
    expect(find.text('正在加载统计…'), findsNothing);

    unawaited(controller.refreshCurrentDate());
    await tester.pump();

    expect(find.text('10s'), findsWidgets);
    expect(find.text('正在加载统计…'), findsNothing);

    releaseSecondLoad.complete();
    await tester.pump();
    await tester.pump();

    expect(find.text('20s'), findsWidgets);
  });
}

Map<String, dynamic> _buildDayRaw({double totalSeconds = 0}) {
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
            'duration_seconds': totalSeconds,
            'battle': {
              'count': 0,
              'avg_duration_seconds': 0,
            },
          },
        ],
      },
    },
    'multi': null,
  };
}
