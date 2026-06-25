import 'dart:convert';
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

  // 中文注释：锁定 updateAutoScript 的增删与排序，并验证持久化写入正确内容
  test('updateAutoScript adds, removes and persists sorted list', () async {
    final service = await _buildScriptService();
    service.updateAutoScript('b', true);
    service.updateAutoScript('a', true);
    expect(service.autoScriptList, ['a', 'b']);
    // 锁定持久化内容为 JSON 数组字符串（避免之前只断言 isNotNull 的弱验证）
    final raw = GetStorage().read(StorageKey.autoScriptList.name);
    expect(raw, jsonEncode(['a', 'b']));

    service.updateAutoScript('a', false);
    expect(service.autoScriptList, ['b']);
    expect(GetStorage().read(StorageKey.autoScriptList.name), jsonEncode(['b']));
  });

  // 中文注释：锁定 _loadAutoScriptListFromStorage 兼容历史 JSON 字符串格式
  test('restore autoScriptList from legacy JSON string', () async {
    // 模拟历史版本写入的 JSON 字符串
    await GetStorage().write(
        StorageKey.autoScriptList.name, jsonEncode(['x', 'y']));
    final service = await _buildScriptService();
    // 触发 restore（构造时 onInit 不会跑，手动调用同等价路径）
    service.restoreAutoScriptListForTest();
    expect(service.autoScriptList, ['x', 'y']);
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
