// test/model/auto_script_entry_test.dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/model/auto_script_entry.dart';

// 中文注释：锁定自启条目的存储解析——兼容 raw List 直存 / JSON 字符串两种容器，
// 字符串元素（旧格式，延时 0）/ 对象元素（新格式）两种元素，及脏数据防护。
void main() {
  test('旧格式 raw List 直存迁移为延时 0 的条目', () {
    final entries = AutoScriptEntry.parseStored(['oas1', 'oas2']);
    expect(entries.map((e) => e.name), ['oas1', 'oas2']);
    expect(entries.every((e) => e.delaySeconds == 0), isTrue);
  });

  test('旧格式 JSON 字符串迁移为延时 0 的条目', () {
    final entries = AutoScriptEntry.parseStored(jsonEncode(['oas1']));
    expect(entries.single.name, 'oas1');
    expect(entries.single.delaySeconds, 0);
  });

  test('新格式对象数组解析出延时', () {
    final raw = jsonEncode([
      {'name': 'oas1', 'delaySeconds': 30},
      {'name': 'oas2', 'delaySeconds': 90},
    ]);
    final entries = AutoScriptEntry.parseStored(raw);
    expect(entries[0].delaySeconds, 30);
    expect(entries[1].delaySeconds, 90);
  });

  test('脏数据（非 JSON / 非 List / 空名 / 非法延时）安全处理', () {
    expect(AutoScriptEntry.parseStored('{broken'), isEmpty);
    expect(AutoScriptEntry.parseStored(42), isEmpty);
    expect(AutoScriptEntry.parseStored(null), isEmpty);
    // 空名条目丢弃；延时非数字按 0；负数按 0；超上限截断
    final entries = AutoScriptEntry.parseStored(jsonEncode([
      {'name': '', 'delaySeconds': 5},
      {'name': 'a', 'delaySeconds': 'x'},
      {'name': 'b', 'delaySeconds': -3},
      {'name': 'c', 'delaySeconds': 999999},
    ]));
    expect(entries.map((e) => e.name), ['a', 'b', 'c']);
    expect(entries.map((e) => e.delaySeconds),
        [0, 0, AutoScriptEntry.maxDelaySeconds]);
  });

  test('encodeList 输出新格式 JSON', () {
    final s = AutoScriptEntry.encodeList([AutoScriptEntry('oas1', 30)]);
    expect(jsonDecode(s), [
      {'name': 'oas1', 'delaySeconds': 30}
    ]);
  });
}
