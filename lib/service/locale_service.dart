import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:oasx/model/const/storage_key.dart';

import 'package:oasx/config/translation/i18n.dart';
import 'package:path_provider/path_provider.dart';

class LocaleService extends GetxService with DynamicMessages {
  final _storage = GetStorage();
  final language = 'zh-CN'.obs;

  /// 语言名到 Locale 的映射；未知语言回退简体中文。
  Locale _localeFor(String lang) => switch (lang) {
        'zh-CN' => const Locale('zh', 'CN'),
        'en-US' => const Locale('en', 'US'),
        _ => const Locale('zh', 'CN'),
      };

  /// 当前语言对应的 Locale，供 GetMaterialApp.locale 使用。
  Locale get currentLocale => _localeFor(language.value);

  /// 回退目标跟随当前语言：英文模式下不回退到 zh-CN，
  /// 避免 GetX `.tr` 把英文表缺失的 key 解析成中文；
  /// 中文模式仍回退中文，行为不变。
  Locale get fallbackLocale => _localeFor(language.value);

  @override
  void onInit() {
    loadMessage();
    language.value = _storage.read(StorageKey.language.name) ?? 'zh-CN';
    _updateLocale(language.value);
    super.onInit();
  }

  void switchLanguage(String lang) {
    language.value = lang;
    _storage.write(StorageKey.language.name, lang);
    _updateLocale(lang);
  }

  void _updateLocale(String lang) {
    final locale = _localeFor(lang);
    Get.updateLocale(locale);
    // GetMaterialApp 仅在 initState 里设置一次 Get.fallbackLocale，
    // 语言切换后需手动跟随，否则英文模式下仍会回退 zh-CN 显示中文。
    Get.fallbackLocale = locale;
  }
}

mixin DynamicMessages {
  late final Messages _messages = Messages();
  Messages get messages => _messages;

  Future<bool> loadMessage() async {
    await _loadLocaleMessage('zh-CN');
    await _loadLocaleMessage('en-US');
    return true;
  }

  Future<bool> _loadLocaleMessage(String lang) async {
    try {
      Directory appDocDir = await getApplicationCacheDirectory();
      // final json = await rootBundle.loadString('assets/i18n/$lang.json');
      String filePath = '${appDocDir.path}/i18n/$lang.json';
      File file = File(filePath);
      String json = await file.readAsString();
      final dataMap = jsonDecode(json) as Map<String, dynamic>;
      dataMap.forEach(
          (key, value) => _messages.translateUpdate(key, value, locale: lang));
    } catch (e) {
      printError(info: e.toString());
    }
    return true;
  }

  /// 把后端下发的补充翻译立即合入内存翻译表，使当次启动即可显示新翻译
  /// （saveAdditionalTranslate 只写缓存文件，要下次启动才生效）
  ///
  /// 注意隐式契约：putChineseTranslate 上传镜像用的是 Messages() 新实例
  /// （编译期内置翻译），不受本方法运行时合入的条目影响；后端靠这一点
  /// 区分「前端内置」与「真缺失」，勿改为复用本实例上传
  void applyAdditionalTranslate(Map<String, Map<String, String>> data) {
    data.forEach((lang, entries) {
      entries.forEach(
          (key, value) => _messages.translateUpdate(key, value, locale: lang));
    });
  }

  Future<bool> saveAdditionalTranslate(
      Map<String, Map<String, String>> data) async {
    await _saveAdditionalTranslate(data["zh-CN"]!, lang: 'zh-CN');
    await _saveAdditionalTranslate(data["en-US"]!, lang: 'en-US');
    return true;
  }

  Future<bool> _saveAdditionalTranslate(Map<String, String> data,
      {String lang = "zh-CN"}) async {
    try {
      JsonEncoder encoder = const JsonEncoder.withIndent('  ');
      String jsonString = encoder.convert(data);
      Directory appDocDir = await getApplicationCacheDirectory();
      String i18nDirPath = '${appDocDir.path}/i18n';
      Directory i18nDir = Directory(i18nDirPath);
      if (!i18nDir.existsSync()) {
        i18nDir.createSync(recursive: true);
      }
      String filePath = '$i18nDirPath/$lang.json';
      printInfo(info: 'Save additional translate to $filePath');
      File file = File(filePath);
      await file.writeAsString(jsonString);
    } catch (e) {
      printError(info: e.toString());
    }
    return true;
  }
}
