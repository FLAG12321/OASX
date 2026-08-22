import 'package:flutter/material.dart';
import 'package:chinese_font_library/chinese_font_library.dart';

/// 用枚举太麻烦了
enum ColorSeed {
  baseColor('M3 Baseline', Color(0xff6750a4)),
  indigo('Indigo', Colors.indigo),
  blue('Blue', Colors.blue),
  teal('Teal', Colors.teal),
  green('Green', Colors.green),
  yellow('Yellow', Colors.yellow),
  orange('Orange', Colors.orange),
  deepOrange('Deep Orange', Colors.deepOrange),
  pink('Pink', Colors.pink);

  const ColorSeed(this.label, this.color);
  final String label;
  final Color color;
}

const Map<String, Color> colorSeedMap = {
  'M3 Baseline': Color(0xff6750a4),
  'Indigo': Colors.indigo,
  'Blue': Colors.blue,
  'Teal': Colors.teal,
  'Green': Colors.green,
  'Yellow': Colors.yellow,
  'Orange': Colors.orange,
  'Deep Orange': Colors.deepOrange,
  'Pink': Colors.pink
};

ThemeData lightTheme = ThemeData(
  colorSchemeSeed: ColorSeed.baseColor.color,
  useMaterial3: true,
  brightness: Brightness.light,
  textTheme: const TextTheme(
    bodyLarge: TextStyle(),
    bodyMedium: TextStyle(),
    bodySmall: TextStyle(),
    labelLarge: TextStyle(),
    labelMedium: TextStyle(),
    labelSmall: TextStyle(),
    titleLarge: TextStyle(),
    titleMedium: TextStyle(),
    // titleMedium: TextStyle(fontWeight: FontWeight.w600),
    titleSmall: TextStyle(),
    // 全局等宽（CascadiaCode）：让运行日志、统计表、自启动脚本名与延时里的
    // 数字逐列对齐——这些散落在 3000+ 行视图里，逐处加 fontFamily 必然漏改。
    // 前提是 log_widget 的级别补空格已按等宽字符差重算（原值照 Lato 标定，
    // 在等宽下会超量把时间戳列推歪）。中文由 useSystemChineseFont 回退提供。
  ).apply(fontFamily: 'CascadiaCode').useSystemChineseFont(Brightness.light),
  scaffoldBackgroundColor: const Color.fromRGBO(255, 251, 255, 1),
  navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: Color.fromRGBO(255, 251, 255, 1)),
);

ThemeData darkTheme = ThemeData(
  useMaterial3: true,
  colorSchemeSeed: ColorSeed.baseColor.color,
  brightness: Brightness.dark,
  textTheme: const TextTheme(
    bodyLarge: TextStyle(),
    bodyMedium: TextStyle(),
    bodySmall: TextStyle(),
    labelLarge: TextStyle(),
    labelMedium: TextStyle(),
    labelSmall: TextStyle(),
    titleLarge: TextStyle(),
    titleMedium: TextStyle(),
    titleSmall: TextStyle(),
    // 同 lightTheme：全局等宽，让各处数字逐列对齐
  ).apply(fontFamily: 'CascadiaCode').useSystemChineseFont(Brightness.dark),
  scaffoldBackgroundColor: const Color.fromRGBO(49, 48, 51, 1),
  navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: Color.fromRGBO(49, 48, 51, 1)),
);
