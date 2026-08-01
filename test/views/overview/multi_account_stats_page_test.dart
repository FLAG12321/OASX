import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:oasx/model/stats/script_statistics_models.dart';
import 'package:oasx/views/overview/multi_account_stats_page.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    Get.testMode = true;
    // mock path_provider，让 GetStorage 在内存临时目录初始化（沿用既有模式）。
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      return '${Directory.systemTemp.path}/oasx_test_storage_multi_stats';
    });
    await GetStorage.init();
  });

  // 中文注释：锁定多账号统计页标题栏始终渲染返回按钮与标题。
  // Windows 下为自绘 _StatsWindowTitleBar（含最小化/最大化/关闭按钮），
  // 其它平台为普通 AppBar，两分支都保留返回按钮与标题，测试跨平台通过。
  testWidgets('multi-account stats page renders back button and title', (tester) async {
    final day = ScriptStatisticsDay(
      scriptName: 'oas1',
      dateKey: '2026-08-02',
      totalRuntimeSeconds: 0,
      totalTaskRunCount: 0,
      totalBattleCount: 0,
      tasks: const {},
      multi: null,
    );
    await tester.pumpWidget(
      GetMaterialApp(home: MultiAccountStatsPage(statisticsDay: day)),
    );
    await tester.pump();

    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    expect(find.textContaining('Multi-Account Stats'), findsOneWidget);
    if (Platform.isWindows) {
      // Windows 下标题栏为自绘控制条，应含最小化/最大化/关闭三个按钮。
      expect(find.byType(WindowCaptionButton), findsNWidgets(3));
    }
  });

  // 中文注释：锁定三个窗口控制按钮已接入对应 window_manager 方法。
  // 曾出现按钮只传 brightness、onPressed 为 null 导致点击无响应的问题，
  // 该测试防止回归（仅 Windows 分支渲染这些按钮）。
  testWidgets('window control buttons invoke window manager methods',
      (tester) async {
    if (!Platform.isWindows) {
      return;
    }
    final calls = <String>[];
    const channel = MethodChannel('window_manager');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'isMaximized':
        case 'isMinimized':
          return false;
        default:
          return null;
      }
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final day = ScriptStatisticsDay(
      scriptName: 'oas1',
      dateKey: '2026-08-02',
      totalRuntimeSeconds: 0,
      totalTaskRunCount: 0,
      totalBattleCount: 0,
      tasks: const {},
      multi: null,
    );
    await tester.pumpWidget(
      GetMaterialApp(home: MultiAccountStatsPage(statisticsDay: day)),
    );
    await tester.pump();

    // 按钮顺序固定：索引 0=最小化，1=最大化（未最大化时），2=关闭。
    await tester.tap(find.byType(WindowCaptionButton).at(0));
    await tester.pump();
    expect(calls, contains('minimize'));

    await tester.tap(find.byType(WindowCaptionButton).at(1));
    await tester.pump();
    expect(calls, contains('maximize'));

    await tester.tap(find.byType(WindowCaptionButton).at(2));
    await tester.pump();
    expect(calls, contains('close'));
  });
}
