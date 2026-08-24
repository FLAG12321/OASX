import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:oasx/model/const/storage_key.dart';
import 'package:oasx/service/log_font_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    Get.testMode = true;
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      return '${Directory.systemTemp.path}/oasx_test_storage_log_font';
    });
    await GetStorage.init();
  });

  setUp(() async {
    await GetStorage().remove(StorageKey.logFontPreset.name);
    await GetStorage().remove(StorageKey.logFontSize.name);
  });

  test('未设置时使用默认 LatoLato', () {
    final service = LogFontService()..onInit();

    expect(service.preset, LogFontPreset.latoLato);
    expect(service.fontFamily, 'LatoLato');
    expect(service.fontSize, LogFontService.defaultFontSize);
  });

  test('选择字体后立即生效并持久化', () {
    final service = LogFontService()..onInit();
    service.setPreset(LogFontPreset.microsoftYaHeiUi);

    expect(service.preset, LogFontPreset.microsoftYaHeiUi);
    expect(service.fontFamily, 'Microsoft YaHei UI');
    expect(
      GetStorage().read(StorageKey.logFontPreset.name),
      'microsoftYaHeiUi',
    );

    final restored = LogFontService()..onInit();
    expect(restored.preset, LogFontPreset.microsoftYaHeiUi);
  });

  test('未知存储值安全回退到 LatoLato', () {
    expect(LogFontPreset.fromStorage('unknown'), LogFontPreset.latoLato);
  });

  test('字号独立于字体选择并持久化', () {
    final service = LogFontService()..onInit();
    service.setPreset(LogFontPreset.consolas);
    service.setFontSize(16);

    expect(service.preset, LogFontPreset.consolas);
    expect(service.fontSize, 16);
    expect(GetStorage().read(StorageKey.logFontSize.name), 16);

    final restored = LogFontService()..onInit();
    expect(restored.preset, LogFontPreset.consolas);
    expect(restored.fontSize, 16);
  });

  test('未知日志字号安全回退到默认 14', () {
    expect(
        LogFontService.fontSizeFromStorage(10), LogFontService.defaultFontSize);
    expect(LogFontService.fontSizeFromStorage('14'),
        LogFontService.defaultFontSize);
  });
}
