import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:oasx/config/translation/i18n_content.dart';
import 'package:oasx/views/nav/view_nav.dart';

/// 中文注释：跳过 NavCtrl 真实网络初始化，菜单为空时只测空态 UI。
class _FakeNavCtrl extends NavCtrl {
  @override
  // ignore: must_call_super
  Future<void> onInit() async {}

  @override
  Future<void> reloadMenus() async {}
}

void main() {
  testWidgets('菜单为空且加载中时显示加载动画', (tester) async {
    final nav = _FakeNavCtrl();
    nav.isHomeMenu.value = false;
    nav.scriptMenuJson.value = {};
    nav.menuLoading.value = true;
    Get.put<NavCtrl>(nav);

    await tester.pumpWidget(
      const GetMaterialApp(home: Scaffold(body: TreeMenuView())),
    );

    // 加载中：显示转圈与加载文案，不显示失败入口
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text(I18n.menu_loading.tr), findsOneWidget);
    expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
    expect(find.byIcon(Icons.refresh_rounded), findsNothing);

    Get.reset();
  });

  testWidgets('菜单为空且加载失败时显示失败提示与重试入口', (tester) async {
    final nav = _FakeNavCtrl();
    nav.isHomeMenu.value = false;
    nav.scriptMenuJson.value = {};
    nav.menuLoading.value = false;
    Get.put<NavCtrl>(nav);

    await tester.pumpWidget(
      const GetMaterialApp(home: Scaffold(body: TreeMenuView())),
    );

    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    expect(find.text(I18n.menu_load_failed.tr), findsOneWidget);
    expect(find.text(I18n.retry.tr), findsOneWidget);

    await tester.tap(find.byIcon(Icons.refresh_rounded));
    await tester.pump();

    Get.reset();
  });
}
