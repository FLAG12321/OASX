// test/service/auto_boot_service_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:oasx/model/const/storage_key.dart';
import 'package:oasx/service/auto_boot_service.dart';

// 中文注释：测试 AutoBootService 的配置状态（读取迁移/增删改持久化）与纯逻辑
// （触发条件判定、剩余延时补偿）。GetStorage 依赖 path_provider，按既有模式 mock。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    Get.testMode = true;
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      // 目录名与其他测试文件区分，避免并行 isolate 冲突
      return '${Directory.systemTemp.path}/oasx_test_storage_autoboot';
    });
    await GetStorage.init();
  });

  setUp(() async {
    await GetStorage().remove(StorageKey.autoScriptList.name);
  });

  test('loadEntries 迁移旧格式并按新格式写回', () async {
    await GetStorage()
        .write(StorageKey.autoScriptList.name, jsonEncode(['oas1']));
    final service = AutoBootService();
    service.loadEntries();
    expect(service.isSelected('oas1'), isTrue);
    expect(service.delayOf('oas1'), 0);
    // 写回后存储值应为新格式对象数组
    final raw = GetStorage().read(StorageKey.autoScriptList.name);
    expect(jsonDecode(raw as String), [
      {'name': 'oas1', 'delaySeconds': 0}
    ]);
  });

  test('首次运行（无存储值）不写回空数组', () async {
    final service = AutoBootService();
    service.loadEntries();
    expect(service.autoScriptEntries, isEmpty);
    expect(GetStorage().read(StorageKey.autoScriptList.name), isNull);
  });

  test('setSelected/setDelay/removeEntry 更新状态并持久化', () async {
    final service = AutoBootService();
    service.loadEntries();
    service.setSelected('oas2', true);
    service.setSelected('oas1', true);
    // 条目保持稳定排序（按名称）
    expect(service.autoScriptEntries.map((e) => e.name), ['oas1', 'oas2']);
    service.setDelay('oas2', 90);
    expect(service.delayOf('oas2'), 90);
    service.setSelected('oas1', false);
    expect(service.isSelected('oas1'), isFalse);
    service.removeEntry('oas2');
    expect(service.autoScriptEntries, isEmpty);
    expect(
        jsonDecode(GetStorage().read(StorageKey.autoScriptList.name)), isEmpty);
  });

  test('shouldAutoBoot 三条件缺一不可', () {
    expect(
        AutoBootService.shouldAutoBoot(
            hasAutostartArg: true, isDesktop: true, entryCount: 1),
        isTrue);
    expect(
        AutoBootService.shouldAutoBoot(
            hasAutostartArg: false, isDesktop: true, entryCount: 1),
        isFalse);
    expect(
        AutoBootService.shouldAutoBoot(
            hasAutostartArg: true, isDesktop: false, entryCount: 1),
        isFalse);
    expect(
        AutoBootService.shouldAutoBoot(
            hasAutostartArg: true, isDesktop: true, entryCount: 0),
        isFalse);
  });

  test('remainingDelay 按 T0 补偿且不为负', () {
    final t0 = DateTime(2026, 7, 30, 8, 0, 0);
    // 就绪后 10 秒调度、延时 30 秒 → 剩余 20 秒
    expect(
        AutoBootService.remainingDelay(
            30, t0, t0.add(const Duration(seconds: 10))),
        const Duration(seconds: 20));
    // 已超时 → 0（立即启动）
    expect(
        AutoBootService.remainingDelay(
            30, t0, t0.add(const Duration(seconds: 60))),
        Duration.zero);
  });
}
