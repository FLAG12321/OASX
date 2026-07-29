import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:oasx/config/translation/i18n_content.dart';
import 'package:oasx/model/const/storage_key.dart';
import 'package:oasx/service/auto_start_service.dart';
import 'package:oasx/service/script_service.dart';
import 'package:oasx/service/websocket_service.dart';
import 'package:oasx/views/server/auto_start_settings.dart';

// 中文注释：测试 Server 页「OASX自启动设置」内容区 AutoStartSettingsContent。
// 两个 service 均用 no-op onInit 的 fake 子类，避免测试机上真实执行
// schtasks / PackageInfo / HTTP 与 5×500ms 轮询（pending Timer 会使测试必败）。

// fake：覆写 onInit 跳过 PackageInfo 读取与 schtasks refresh；
// 覆写 updateLaunchAtStartupEnable 结构性阻断真实 schtasks 执行，并记录调用
class _FakeAutoStartService extends AutoStartService {
  final updateCalls = <bool>[];

  // 故意不调 super：super.onInit 正是要跳过的真实副作用
  @override
  // ignore: must_call_super
  Future<void> onInit() async {}

  @override
  Future<void> updateLaunchAtStartupEnable(bool enabled) async {
    updateCalls.add(enabled);
  }
}

// fake：覆写 onInit/onClose 跳过真实 HTTP、就绪轮询与 websocket 收尾
class _FakeScriptService extends ScriptService {
  // 故意不调 super：super.onInit 正是要跳过的真实副作用
  @override
  // ignore: must_call_super
  Future<void> onInit() async {}

  @override
  // ignore: must_call_super
  Future<void> onClose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    Get.testMode = true;
    // mock path_provider，让 GetStorage 在内存临时目录初始化（沿用既有模式）；
    // 目录名与其他测试文件区分，避免并行 isolate 同时初始化同一存储文件冲突
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      return '${Directory.systemTemp.path}/oasx_test_storage_autostart';
    });
    await GetStorage.init();
  });

  setUp(() async {
    await GetStorage().remove(StorageKey.autoScriptList.name);
    // 公共 setUp：内容区无条件渲染开机自启开关，故每个用例都需注册 fake
    Get.put<AutoStartService>(_FakeAutoStartService(), permanent: true);
  });

  tearDown(() async {
    // 逐个清理注册，避免用例间状态泄漏
    await Get.delete<AutoStartService>(force: true);
    if (Get.isRegistered<ScriptService>()) {
      await Get.delete<ScriptService>(force: true);
    }
    if (Get.isRegistered<WebSocketService>()) {
      await Get.delete<WebSocketService>(force: true);
    }
  });

  // 中文注释：ListTile 系需要 Material 祖先；.tr 未加载翻译时回退键值（即英文文案），
  // 断言统一用 I18n 常量匹配
  Future<void> pumpContent(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: AutoStartSettingsContent()),
      ),
    ));
  }

  // 注册 fake ScriptService（其字段初始化依赖已注册的 WebSocketService）
  ScriptService putFakeScriptService() {
    if (!Get.isRegistered<WebSocketService>()) {
      Get.put<WebSocketService>(WebSocketService(), permanent: true);
    }
    return Get.put<ScriptService>(_FakeScriptService(), permanent: true);
  }

  testWidgets('ScriptService 未注册时渲染登录提示、不渲染脚本多选',
      (WidgetTester tester) async {
    await pumpContent(tester);

    expect(find.text(I18n.autoRunScriptLoginHint), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNothing);
    // 开机自启开关始终渲染
    expect(find.byType(SwitchListTile), findsOneWidget);
  });

  testWidgets('已注册时渲染脚本多选，勾选触发 updateAutoScript 并持久化',
      (WidgetTester tester) async {
    final service = putFakeScriptService();
    service.addScriptModel('oas1');
    service.addScriptModel('oas2');

    await pumpContent(tester);

    expect(find.text(I18n.autoRunScriptLoginHint), findsNothing);
    expect(find.byType(CheckboxListTile), findsNWidgets(2));

    // 勾选 oas1 → autoScriptList 更新并写入 GetStorage
    await tester.tap(find.text('oas1'));
    await tester.pump();
    expect(service.autoScriptList, ['oas1']);
    expect(GetStorage().read(StorageKey.autoScriptList.name),
        jsonEncode(['oas1']));

    // 取消勾选 → 移除并持久化
    await tester.tap(find.text('oas1'));
    await tester.pump();
    expect(service.autoScriptList, isEmpty);
    expect(GetStorage().read(StorageKey.autoScriptList.name), jsonEncode([]));
  });

  testWidgets('isApplying 为 true 时开机自启开关禁用', (WidgetTester tester) async {
    final autoStart = Get.find<AutoStartService>();
    autoStart.isApplying.value = true;

    await pumpContent(tester);

    final switchTile =
        tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(switchTile.onChanged, isNull);
  });

  testWidgets('启用态 tap 开关触发 updateLaunchAtStartupEnable',
      (WidgetTester tester) async {
    final autoStart = Get.find<AutoStartService>() as _FakeAutoStartService;

    await pumpContent(tester);

    // fake 已阻断真实 schtasks，tap 仅记录调用入参
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    expect(autoStart.updateCalls, [true]);
  });
}
