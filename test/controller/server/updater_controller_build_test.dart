// test/controller/server/updater_controller_build_test.dart
//
// 中文注释：回归锚点——infoFuture 不得在 build 期同步修改 Rx。
//
// 踩过的坑：getter 曾写成
//     _infoFuture ??= ServerOperationLock.instance.run(_loadInfo)
// 而 ServerOperationLock.run 第一行就是同步的 `isBusy.value = true`。
// _RemoteSection.build（lib/views/server/updater_panel.dart）在 build 期读
// infoFuture，Obx 监听者随即被 markNeedsBuild，Flutter 抛
//     setState() or markNeedsBuild() called during build.
// 整个更新器面板白屏。
//
// 为什么不 pump 真实面板：它要 GetStorage / path_provider / ServerController
// 一整套依赖，且 FutureBuilder 里的 spinner 会让 pumpAndSettle 永不收敛
// （实测挂满 10 分钟超时）。所以这里直接断言「读 getter 不同步改锁状态」——
// 这正是 markNeedsBuild 的充要条件，比复现整个 widget 树稳定得多。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:oasx/controller/server/updater_controller.dart';
import 'package:oasx/service/server_operation_lock.dart';

class _InfoFutureBuildProbe extends StatelessWidget {
  const _InfoFutureBuildProbe({required this.controller});

  final UpdaterController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // 先建立对 isBusy 的响应式依赖，再在同一次 build 读取真实 infoFuture。
      // 旧实现会在这里同步把 busy 改成 true，从而触发 markNeedsBuild during build。
      final busy = ServerOperationLock.instance.isBusy.value;
      return FutureBuilder(
        future: controller.infoFuture,
        builder: (context, snapshot) => Text('busy=$busy'),
      );
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // 真实 UpdaterController.infoFuture 会读取 GetStorage.rootPathServer；
    // 初始化测试绑定和存储，避免回归测试因插件未初始化而留下异步错误。
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      return '${Directory.systemTemp.path}/oasx_test_updater_controller';
    });
    await GetStorage.init();
  });

  testWidgets('build 读取真实 infoFuture 不得同步修改 Rx', (tester) async {
    await GetStorage().remove('rootPathServer');
    final lock = ServerOperationLock.instance;
    expect(lock.isBusy.value, isFalse, reason: '前置条件：锁应空闲');

    await tester.pumpWidget(MaterialApp(
      home: _InfoFutureBuildProbe(controller: UpdaterController()),
    ));
    expect(tester.takeException(), isNull,
        reason: 'build 期间不得抛 setState/markNeedsBuild 异常');

    // 再 pump 一帧让 microtask 中的锁操作与失败 Future 完整收尾。
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(lock.isBusy.value, isFalse, reason: '操作结束后应释放');
  });

  test('infoFuture 源码必须保持推迟取锁的写法', () {
    final source = File('lib/controller/server/updater_controller.dart')
        .readAsStringSync();
    expect(source.contains('Future.microtask'), isTrue,
        reason: 'infoFuture 必须把取锁推迟到 build 之后');
    expect(
        source.contains(
            '_infoFuture ??= ServerOperationLock.instance.run(_loadInfo)'),
        isFalse,
        reason: '不得退回 build 期同步取锁的写法');
  });
}
