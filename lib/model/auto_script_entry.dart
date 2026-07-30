// lib/model/auto_script_entry.dart
import 'dart:convert';

// 自动启动脚本条目：脚本名 + 相对后端就绪时刻(T0)的延时秒数。
// 存储于 StorageKey.autoScriptList，新格式为对象数组 JSON 字符串。
class AutoScriptEntry {
  final String name;
  final int delaySeconds;

  // 延时上限 24 小时（spec §4.3）
  static const int maxDelaySeconds = 86400;

  AutoScriptEntry(this.name, int delaySeconds)
      : delaySeconds = _clampDelay(delaySeconds);

  // 延时限定 0–86400，非法值按 0 处理
  static int _clampDelay(int value) {
    if (value < 0) return 0;
    if (value > maxDelaySeconds) return maxDelaySeconds;
    return value;
  }

  Map<String, dynamic> toJson() =>
      {'name': name, 'delaySeconds': delaySeconds};

  // 解析存储原始值，兼容三种历史形态：
  // 1) raw List 直存（最早期版本）2) JSON 字符串包 List（前一版）
  // 元素为字符串 → 旧格式，延时按 0；元素为对象 → 新格式。
  // 任何解析失败按空列表处理，空名条目丢弃。
  static List<AutoScriptEntry> parseStored(dynamic raw) {
    dynamic decoded = raw;
    if (raw is String) {
      if (raw.trim().isEmpty) return [];
      try {
        decoded = jsonDecode(raw);
      } catch (_) {
        return [];
      }
    }
    if (decoded is! List) return [];
    final entries = <AutoScriptEntry>[];
    for (final item in decoded) {
      if (item is String) {
        if (item.isNotEmpty) entries.add(AutoScriptEntry(item, 0));
      } else if (item is Map) {
        final name = item['name'];
        if (name is String && name.isNotEmpty) {
          final delay = item['delaySeconds'];
          entries.add(AutoScriptEntry(
              name, delay is int ? delay : int.tryParse('$delay') ?? 0));
        }
      }
    }
    return entries;
  }

  // 序列化为新格式 JSON 字符串（对象数组）
  static String encodeList(List<AutoScriptEntry> entries) =>
      jsonEncode(entries.map((e) => e.toJson()).toList());
}
