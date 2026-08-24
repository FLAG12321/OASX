import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:oasx/controller/settings.dart';
import 'package:oasx/service/locale_service.dart';
import 'package:oasx/service/log_font_service.dart';
import 'package:oasx/service/theme_service.dart';
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
        const _LogFontWidget().paddingAll(5),
        const _LogFontSizeWidget().paddingAll(5),
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

class _LogFontWidget extends StatelessWidget {
  const _LogFontWidget();

  @override
  Widget build(BuildContext context) {
    final logFontService = Get.find<LogFontService>();

    return Obx(() {
      return <Widget>[
        Text(I18n.log_font.tr).paddingOnly(bottom: 5),
        DropdownButton<LogFontPreset>(
          value: logFontService.preset,
          onChanged: (preset) {
            if (preset != null) {
              logFontService.setPreset(preset);
            }
          },
          items: LogFontPreset.values
              .map(
                (preset) => DropdownMenuItem(
                  value: preset,
                  child: Text(_labelFor(preset).tr),
                ),
              )
              .toList(),
        ).constrained(minWidth: 180),
      ].toColumn();
    });
  }

  String _labelFor(LogFontPreset preset) => switch (preset) {
        LogFontPreset.cascadiaCode => I18n.log_font_cascadia_code,
        LogFontPreset.latoLato => I18n.log_font_lato_lato,
        LogFontPreset.consolas => I18n.log_font_consolas,
        LogFontPreset.segoeUi => I18n.log_font_segoe_ui,
        LogFontPreset.microsoftYaHeiUi => I18n.log_font_microsoft_yahei_ui,
        LogFontPreset.systemDefault => I18n.log_font_system_default,
      };
}

class _LogFontSizeWidget extends StatelessWidget {
  const _LogFontSizeWidget();

  @override
  Widget build(BuildContext context) {
    final logFontService = Get.find<LogFontService>();

    return Obx(() {
      return <Widget>[
        Text(I18n.log_font_size.tr).paddingOnly(bottom: 5),
        DropdownButton<int>(
          value: logFontService.fontSize,
          onChanged: (size) {
            if (size != null) {
              logFontService.setFontSize(size);
            }
          },
          items: LogFontService.supportedFontSizes
              .map(
                (size) => DropdownMenuItem(
                  value: size,
                  child: Text('$size px'),
                ),
              )
              .toList(),
        ).constrained(minWidth: 180),
      ].toColumn();
    });
  }
}
