import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:oasx/config/translation/i18n_content.dart';
import 'package:oasx/model/const/storage_key.dart';
import 'package:oasx/service/auto_boot_service.dart';
import 'package:oasx/service/auto_start_service.dart';
import 'package:oasx/views/server/auto_start_settings.dart';

// 中文注释：测试 Server 页「OASX自启动设置」内容区 AutoStartSettingsContent。
// AutoStartService 用 no-op onInit 的 fake 子类，避免测试机上真实执行
// schtasks / PackageInfo；server 探测与脚本列表经构造参数注入，隔离真实 HTTP。

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
    // 公共 setUp：内容区无条件渲染开机自启开关，故每个用例都需注册 fake；
    // 自启条目数据源为 AutoBootService（loadEntries 重置为存储当前值）
    Get.put<AutoStartService>(_FakeAutoStartService(), permanent: true);
    Get.put<AutoBootService>(AutoBootService()..loadEntries(), permanent: true);
  });

  tearDown(() async {
    // 逐个清理注册，避免用例间状态泄漏
    await Get.delete<AutoStartService>(force: true);
    await Get.delete<AutoBootService>(force: true);
  });

  // 中文注释：ListTile 系需要 Material 祖先；.tr 未加载翻译时回退键值（即英文文案），
  // 断言统一用 I18n 常量匹配。探测结果与脚本列表经构造参数注入
  Future<void> pumpContent(WidgetTester tester,
      {bool? reachable,
      List<String> scripts = const [],
      Future<bool> Function()? probeBackend,
      Future<List<String>> Function()? fetchScripts}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AutoStartSettingsContent(
            probeBackend: probeBackend ?? (() async => reachable!),
            fetchScripts: fetchScripts ?? (() async => scripts),
          ),
        ),
      ),
    ));
    // 等待探测 Future 完成、进度条消失
    await tester.pumpAndSettle();
  }

  testWidgets('server 不可达时渲染启动提示、不渲染脚本多选', (WidgetTester tester) async {
    await pumpContent(tester, reachable: false);

    expect(find.text(I18n.autoRunScriptServerHint), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNothing);
    // 开机自启开关始终渲染
    expect(find.byType(SwitchListTile), findsOneWidget);
  });

  testWidgets('探测异常时结束 loading 并显示不可达提示', (WidgetTester tester) async {
    await pumpContent(tester, probeBackend: () async {
      throw StateError('probe failed');
    });

    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text(I18n.autoRunScriptServerHint), findsOneWidget);
  });

  testWidgets('脚本拉取异常时结束 loading 并显示不可达提示', (WidgetTester tester) async {
    await pumpContent(tester, reachable: true, fetchScripts: () async {
      throw StateError('fetch failed');
    });

    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text(I18n.autoRunScriptServerHint), findsOneWidget);
  });
  testWidgets('可达时渲染脚本列表，勾选持久化新格式并启用延时输入', (WidgetTester tester) async {
    await pumpContent(tester, reachable: true, scripts: ['oas1', 'oas2']);
    expect(find.text(I18n.autoRunScriptServerHint), findsNothing);
    expect(find.byType(CheckboxListTile), findsNWidgets(2));

    // 勾选 oas1 → AutoBootService 条目新增并按新格式持久化
    await tester.tap(find.text('oas1'));
    await tester.pump();
    final autoBoot = Get.find<AutoBootService>();
    expect(autoBoot.isSelected('oas1'), isTrue);
    expect(jsonDecode(GetStorage().read(StorageKey.autoScriptList.name)), [
      {'name': 'oas1', 'delaySeconds': 0}
    ]);

    // 修改延时 → 持久化延时值（key 含勾选态：已勾选为 _true）
    await tester.enterText(find.byKey(const ValueKey('delay_oas1_true')), '30');
    await tester.pump();
    expect(autoBoot.delayOf('oas1'), 30);

    // 未勾选脚本的延时输入禁用
    final oas2Field = tester
        .widget<TextFormField>(find.byKey(const ValueKey('delay_oas2_false')));
    expect(oas2Field.enabled, isFalse);

    // 取消勾选 → 条目移除并持久化
    await tester.tap(find.text('oas1'));
    await tester.pump();
    expect(autoBoot.isSelected('oas1'), isFalse);
    expect(
        jsonDecode(GetStorage().read(StorageKey.autoScriptList.name)), isEmpty);
  });

  testWidgets('isApplying 为 true 时开机自启开关禁用', (WidgetTester tester) async {
    final autoStart = Get.find<AutoStartService>();
    autoStart.isApplying.value = true;

    await pumpContent(tester, reachable: false);

    final switchTile =
        tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(switchTile.onChanged, isNull);
  });

  testWidgets('启用态 tap 开关触发 updateLaunchAtStartupEnable',
      (WidgetTester tester) async {
    final autoStart = Get.find<AutoStartService>() as _FakeAutoStartService;

    await pumpContent(tester, reachable: false);

    // fake 已阻断真实 schtasks，tap 仅记录调用入参
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    expect(autoStart.updateCalls, [true]);
  });
}
