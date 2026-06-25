import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:oasx/controller/settings.dart';
import 'package:oasx/service/auto_start_service.dart';
import 'package:oasx/service/locale_service.dart';
import 'package:oasx/service/script_service.dart';
import 'package:oasx/service/theme_service.dart';
import 'package:oasx/utils/platform_utils.dart';
import 'package:styled_widget/styled_widget.dart';

import 'package:oasx/config/translation/i18n_content.dart';
import 'package:oasx/views/layout/appbar.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildPlatformAppBar(context),
      body: SingleChildScrollView(
          child: <Widget>[
        const _ThemeWidget().paddingAll(5),
        const _LanguageWidget().paddingAll(5),
        if (PlatformUtils.isDesktop) const _AutoStartWidget().paddingAll(5),
        if (PlatformUtils.isDesktop)
          const _AutoRunScriptsWidget().paddingAll(5),
        killServerButton(),
        _exitButton(),
      ].toColumn().alignment(Alignment.center)),
    );
  }

  Widget _exitButton() {
    return TextButton(
            onPressed: () => {Get.offAllNamed('/login')},
            child: Text('Log out'.tr))
        .constrained(minWidth: 180);
  }

  Widget killServerButton() {
    return TextButton(
            onPressed: () => {
                  Get.defaultDialog(
                    title: I18n.are_you_sure_kill.tr,
                    onCancel: () => {},
                    onConfirm: () async =>
                        await Get.find<SettingsController>().killServer(),
                  )
                },
            child: Text(I18n.kill_oas_server.tr))
        .constrained(minWidth: 180);
  }
}

class _ThemeWidget extends StatelessWidget {
  const _ThemeWidget();

  @override
  Widget build(BuildContext context) {
    final themeService = Get.find<ThemeService>();

    return Obx(() {
      final isDark = themeService.isDarkMode;
      return <Widget>[
        Text(I18n.change_theme.tr).paddingOnly(bottom: 5),
        IconButton(
          onPressed: () => themeService.switchTheme(),
          icon: const Icon(Icons.light_mode),
          selectedIcon: const Icon(Icons.dark_mode),
          isSelected: isDark,
        )
      ].toColumn();
    });
  }
}

class _LanguageWidget extends StatelessWidget {
  const _LanguageWidget();

  @override
  Widget build(BuildContext context) {
    final localeService = Get.find<LocaleService>();

    return <Widget>[
      Text(I18n.change_language.tr).paddingOnly(bottom: 5),
      Obx(() {
        final isSelected = switch (localeService.language.value) {
          'zh-CN' => [true, false],
          'en-US' => [false, true],
          _ => [true, false],
        };
        return ToggleButtons(
          isSelected: isSelected,
          onPressed: (index) {
            if (index == 0) {
              localeService.switchLanguage('zh-CN');
            } else {
              localeService.switchLanguage('en-US');
            }
          },
          borderRadius: BorderRadius.circular(10),
          children: <Widget>[
            Text(I18n.zh_cn.tr).paddingOnly(left: 10, right: 10),
            Text(I18n.en_us.tr).paddingOnly(left: 10, right: 10),
          ],
        ).constrained(maxHeight: 40);
      })
    ].toColumn();
  }
}

// 开机自启开关，绑定 AutoStartService 的真实系统状态
class _AutoStartWidget extends StatelessWidget {
  const _AutoStartWidget();

  @override
  Widget build(BuildContext context) {
    final service = Get.find<AutoStartService>();

    return Obx(() {
      final enabled = service.enableLaunchAtStartup.value;
      final applying = service.isApplying.value;
      return <Widget>[
        Text(I18n.launchAtStartup.tr).paddingOnly(bottom: 5),
        Switch(
          value: enabled,
          // 更新中禁用切换，避免并发写入系统注册项
          onChanged: applying
              ? null
              : (v) => service.updateLaunchAtStartupEnable(v),
        )
      ].toColumn();
    });
  }
}

// 自动启动脚本多选列表，数据源为 scriptModelMap.keys（仅真实脚本）
class _AutoRunScriptsWidget extends StatelessWidget {
  const _AutoRunScriptsWidget();

  @override
  Widget build(BuildContext context) {
    final scriptService = Get.find<ScriptService>();

    return Obx(() {
      final scriptNames = scriptService.scriptModelMap.keys.toList();
      final selected = scriptService.autoScriptList;
      return <Widget>[
        Text(I18n.autoRunScriptConfig.tr).paddingOnly(bottom: 5),
        // 展开每个脚本名渲染复选项，勾选状态绑定 autoScriptList
        ...scriptNames.map((name) => CheckboxListTile(
              value: selected.contains(name),
              onChanged: (v) =>
                  scriptService.updateAutoScript(name, v ?? false),
              title: Text(name),
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
            )),
      ].toColumn(crossAxisAlignment: CrossAxisAlignment.start);
    });
  }
}
