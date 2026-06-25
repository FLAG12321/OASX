import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:oasx/model/const/storage_key.dart';
import 'package:oasx/model/script_model.dart';
import 'package:oasx/service/script_service.dart';
import 'package:oasx/service/websocket_service.dart';

// 中文注释：测试 ScriptService 的自动启动脚本相关逻辑。
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
    GetStorage().remove(StorageKey.autoScriptList.name);
  });

  // 中文注释：锁定 updateAutoScript 的增删与排序，并验证持久化写入
  test('updateAutoScript adds, removes and persists sorted list', () async {
    final service = await _buildScriptService();
    service.updateAutoScript('b', true);
    service.updateAutoScript('a', true);
    expect(service.autoScriptList, ['a', 'b']);
    final raw = GetStorage().read(StorageKey.autoScriptList.name);
    expect(raw, isNotNull);

    service.updateAutoScript('a', false);
    expect(service.autoScriptList, ['b']);
  });

  // 中文注释：锁定 isRunning 基于 scriptModelMap 状态判断
  test('isRunning reflects scriptModelMap running state', () async {
    final service = await _buildScriptService();
    service.addScriptModel('oas1');
    expect(service.isRunning('oas1'), isFalse);
    service.scriptModelMap['oas1']!.update(state: ScriptState.running);
    expect(service.isRunning('oas1'), isTrue);
  });

  // 中文注释：锁定 autoRunScript 在全部已运行时直接跳过，不调 startScript
  test('autoRunScript skips when all listed scripts already running', () async {
    final service = await _buildScriptService();
    service.addScriptModel('oas1');
    service.scriptModelMap['oas1']!.update(state: ScriptState.running);
    service.updateAutoScript('oas1', true);

    // autoRunScript 不应抛错，且因全部 running 不进入 startScript 分支
    await service.autoRunScript();
    expect(service.autoScriptList, ['oas1']);
  });
}

// 中文注释：构造 ScriptService 前 Get.put 一个无副作用的 WebSocketService，
// 绕开 ScriptService 字段初始化里 Get.find<WebSocketService> 的依赖。
Future<ScriptService> _buildScriptService() async {
  if (!Get.isRegistered<WebSocketService>()) {
    Get.put<WebSocketService>(WebSocketService(), permanent: true);
  }
  return ScriptService();
}
