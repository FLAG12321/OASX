import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:oasx/model/const/storage_key.dart';

/// 可用于日志正文的字体预设。
///
/// `sans-serif` 是 Flutter 的通用字体族名；它让 System Default 不再继承
/// 全局主题指定的 CascadiaCode，而由当前系统选择默认无衬线字体。
enum LogFontPreset {
  cascadiaCode('cascadiaCode', 'CascadiaCode'),
  latoLato('latoLato', 'LatoLato'),
  consolas('consolas', 'Consolas'),
  segoeUi('segoeUi', 'Segoe UI'),
  microsoftYaHeiUi('microsoftYaHeiUi', 'Microsoft YaHei UI'),
  systemDefault('systemDefault', 'sans-serif');

  const LogFontPreset(this.storageValue, this.fontFamily);

  final String storageValue;
  final String fontFamily;

  static LogFontPreset fromStorage(Object? value) {
    for (final preset in LogFontPreset.values) {
      if (preset.storageValue == value) {
        return preset;
      }
    }
    return LogFontPreset.latoLato;
  }
}

/// 管理日志正文的局部字体偏好，不影响应用的全局 ThemeData。
class LogFontService extends GetxService {
  static const supportedFontSizes = <int>[11, 12, 13, 14, 15, 16];
  static const defaultFontSize = 14;

  final _storage = GetStorage();
  final _preset = LogFontPreset.latoLato.obs;
  final _fontSize = defaultFontSize.obs;

  LogFontPreset get preset => _preset.value;
  String get fontFamily => preset.fontFamily;
  int get fontSize => _fontSize.value;

  static int fontSizeFromStorage(Object? value) {
    return value is int && supportedFontSizes.contains(value)
        ? value
        : defaultFontSize;
  }

  @override
  void onInit() {
    _preset.value =
        LogFontPreset.fromStorage(_storage.read(StorageKey.logFontPreset.name));
    _fontSize.value =
        fontSizeFromStorage(_storage.read(StorageKey.logFontSize.name));
    super.onInit();
  }

  void setPreset(LogFontPreset preset) {
    _preset.value = preset;
    _storage.write(StorageKey.logFontPreset.name, preset.storageValue);
  }

  void setFontSize(int size) {
    if (!supportedFontSizes.contains(size)) {
      return;
    }
    _fontSize.value = size;
    _storage.write(StorageKey.logFontSize.name, size);
  }
}
