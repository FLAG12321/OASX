// test/service/script_service_auto_test.dart
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:oasx/model/const/storage_key.dart';
import 'package:oasx/model/script_model.dart';
import 'package:oasx/service/auto_boot_service.dart';
import 'package:oasx/service/script_service.dart';
import 'package:oasx/service/websocket_service.dart';

// 中文注释：ScriptService 自启相关职责已移至 AutoBootService（见
// docs/superpowers/specs/2026-07-30-auto-boot-design.md），本文件保留
// isRunning 与「删除脚本同步移除自启条目」两个契约。
// GetStorage 底层依赖 path_provider，测试中 mock 该 MethodChannel 返回临时目录。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    Get.testMode = true;
    // mock path_provider，让 GetStorage 在内存临时目录初始化
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      // 所有 path_provider 方法统一返回同一临时目录
      return '${Directory.systemTemp.path}/oasx_test_storage';
    });
    await GetStorage.init();
  });

  setUp(() async {
    await GetStorage().remove(StorageKey.autoScriptList.name);
    if (!Get.isRegistered<AutoBootService>()) {
      Get.put<AutoBootService>(AutoBootService(), permanent: true);
    }
    Get.find<AutoBootService>().loadEntries();
  });

  // 中文注释：锁定 isRunning 基于 scriptModelMap 状态判断
  test('isRunning reflects scriptModelMap running state', () async {
    final service = _buildScriptService();
    service.addScriptModel('oas1');
    expect(service.isRunning('oas1'), isFalse);
    service.scriptModelMap['oas1']!.update(state: ScriptState.running);
    expect(service.isRunning('oas1'), isTrue);
  });

  // 中文注释：锁定删除脚本时同步移除 AutoBootService 中的自启条目
  test('deleteScriptModel 同步移除 AutoBootService 自启条目', () async {
    final autoBoot = Get.find<AutoBootService>();
    autoBoot.setSelected('oas1', true);
    final service = _buildScriptService();
    service.addScriptModel('oas1');
    service.deleteScriptModel('oas1');
    expect(autoBoot.isSelected('oas1'), isFalse);
  });
}

// 中文注释：构造 ScriptService 前 Get.put 一个无副作用的 WebSocketService，
// 绕开 ScriptService 字段初始化里 Get.find<WebSocketService> 的依赖。
ScriptService _buildScriptService() {
  if (!Get.isRegistered<WebSocketService>()) {
    Get.put<WebSocketService>(WebSocketService(), permanent: true);
  }
  return ScriptService();
}
