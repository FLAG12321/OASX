// test/service/auto_start_service_args_test.dart
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:oasx/service/auto_start_service.dart';

// 中文注释：锁定开机自启注册项携带 --autostart 参数
// （spec §4.1：开机自启拉起 OASX 时以该参数区分于手动打开）。
// fake 跳过 onInit 的 PackageInfo/schtasks 副作用，直接测内容构造。
// mac plist / linux desktop 构造依赖 onInit 初始化的 late 字段，
// fake 跳过 onInit 后访问会抛错，故单测只覆盖 Windows XML
// （当前唯一实际部署平台），mac/linux 改动靠 analyze 与代码审查保障。
class _FakeAutoStartService extends AutoStartService {
  @override
  // ignore: must_call_super
  Future<void> onInit() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // AutoStartService 构造时初始化 GetStorage 字段，需 mock path_provider
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      return '${Directory.systemTemp.path}/oasx_test_storage_autostart_args';
    });
    await GetStorage.init();
  });

  test('Windows 计划任务 XML 携带 --autostart 参数', () {
    final xml = _FakeAutoStartService().buildWindowsTaskXml();
    expect(xml, contains('<Arguments>--autostart</Arguments>'));
  });

  test('注册项参数常量与解析端一致', () {
    expect(AutoStartService.autostartArgument, '--autostart');
  });
}
