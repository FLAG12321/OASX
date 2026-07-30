import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:device_preview/device_preview.dart';
import 'package:get_storage/get_storage.dart';
import 'package:oasx/service/locale_service.dart';
import 'package:oasx/service/theme_service.dart';
import 'package:oasx/service/websocket_service.dart';
import 'package:oasx/service/window_service.dart';
import 'package:oasx/service/auto_boot_service.dart';
import 'package:oasx/service/auto_start_service.dart';
import 'package:oasx/utils/logger.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:get/get.dart';

import 'package:oasx/views/routes.dart';
import 'package:oasx/utils/platform_utils.dart';
import 'package:oasx/controller/settings.dart';
import 'package:oasx/config/theme.dart' show lightTheme, darkTheme;

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await initService();
  // 开机自启拉起（注册项携带 --autostart）时标记自动流程（spec §4.2）；
  // 参数须在首帧（LoginController.onInit）前就位，流程触发放首帧后，
  // 确保 GetMaterialApp 路由可用
  Get.find<AutoBootService>().hasAutostartArg =
      args.contains(AutoStartService.autostartArgument);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    Get.find<AutoBootService>().start();
  });

  runApp(
    DevicePreview(
      enabled: !kReleaseMode && (PlatformUtils.isWindows),
      builder: (context) => const OASXApp(), // Wrap your app
    ),
  );
}

class OASXApp extends StatelessWidget {
  const OASXApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    final localeService = Get.find<LocaleService>();

    return ResponsiveApp(builder: (context) {
      return GetMaterialApp(
        // useInheritedMediaQuery: true,
        debugShowCheckedModeBanner: false,
        // locale: DevicePreview.locale(context),
        builder: DevicePreview.appBuilder, // 上面三个是使用device_preview
        scrollBehavior: GlobalBehavior(),
        translations: localeService.messages,
        locale: localeService.currentLocale,
        fallbackLocale: localeService.fallbackLocale, //语言选择无效时，备用语言
        title: 'OASX',
        onInit: onInit,
        initialRoute: Routes.initial,
        getPages: Routes.routes,
        theme: lightTheme,
        darkTheme: darkTheme,
      );
    });
  }

  /// 但是我不能确定 Getx 框架这个时候是否成功初始化
  void onInit() {
    Get.put(SettingsController());
  }
}

class GlobalBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        // etc.
      };
}

Future<void> initService() async {
  await initLogger();
  await GetStorage.init();

  await Future.wait([
    Get.putAsync(() async => LocaleService()),
    Get.putAsync(() async => ThemeService()),
    Get.putAsync(() async => WindowService()),
  ]);

  // 桌面平台才注册开机自启服务，非桌面 no-op
  if (PlatformUtils.isDesktop) {
    Get.putAsync(() async => AutoStartService(), permanent: true);
  }

  // 自启配置状态所有平台可用（配置面板登录前即需数据源）；
  // 自动流程本身仅桌面且 --autostart 时执行
  Get.put<AutoBootService>(AutoBootService()..loadEntries(), permanent: true);

  Get.lazyPut(() => WebSocketService());
}
