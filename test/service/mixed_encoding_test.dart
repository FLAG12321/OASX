import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/service/mixed_encoding.dart';

/// 字节序列是否逐字节相同。
bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// 中文注释：锁住「一条日志流里 utf-8 与 GBK 混流都不乱码」。
//
// 这是踩了四轮才定位清楚的问题。ServerLauncher 那条流同时收两种编码：
//   server.py 的 rich 日志   utf-8（分隔线 ═ ─ │、中文任务名）
//   taskkill / adb 的输出    活动代码页（中文 Windows 是 GBK）
// 固定用任何一种都有一半乱码：
//   固定 GBK      -> 分隔线成 `鈺愨晲鈺愨晲`
//   固定 utf-8 宽容 -> taskkill 成 `�ɹ�: ����ֹ`
//   固定 utf-8 严格 -> 抛 FormatException 打断整条流，server 根本启动不了
void main() {
  // 中文 Windows 的活动代码页；非中文环境下 systemEncoding 可能就是 utf-8，
  // 那时 GBK 相关用例没有意义，跳过而不是失败

  /// GBK 字节；用 systemEncoding 反向编码得到，避免在源码里写死字节表
  List<int> gbkBytes(String s) => systemEncoding.encode(s);

  /// 当前 systemEncoding 是否为「非 utf-8 的多字节代码页」（中文 Windows = GBK）。
  ///
  /// 不能按 name 判断：Dart 的 SystemEncoding.name 恒为 'system'，看不出代码页
  /// （实测中文 Windows 上就是 'system'，但 encode('成功') 得到 b3 c9 b9 a6 = GBK）。
  /// 所以直接探测行为：编出来的字节与 utf-8 不同即为其它代码页。
  final isGbkHost = !_sameBytes(systemEncoding.encode('成功'), utf8.encode('成功'));

  group('一次性解码', () {
    const codec = MixedEncoding(systemEncoding);

    test('utf-8 的制表符与中文原样还原', () {
      const line = '════════ START ════════ │ 任务开始 结算界面';
      expect(codec.decode(utf8.encode(line)), line);
    });

    test('GBK 的中文原样还原（不出现替换字符）', () {
      if (!isGbkHost) {
        markTestSkipped('systemEncoding 非 GBK，跳过代码页用例');
        return;
      }
      const line = '成功: 已终止 PID 5944 (属于 PID 12688 子进程)的进程。';
      final decoded = codec.decode(gbkBytes(line));
      expect(decoded, line);
      // U+FFFD 就是界面上看到的那个 `�`
      expect(decoded, isNot(contains('�')),
          reason: 'GBK 字节被按 utf-8 解了，才会出现替换字符');
    });

    test('纯 ASCII 两种编码结果相同', () {
      const line = 'Devices: [] exitCode 128';
      expect(codec.decode(utf8.encode(line)), line);
      expect(codec.decode(gbkBytes(line)), line);
    });

    test('空输入不抛异常', () {
      expect(codec.decode(const []), '');
    });
  });

  group('流式解码（ShellLinesController 走这条）', () {
    test('同一条流里两种编码交替出现都正确', () async {
      if (!isGbkHost) {
        markTestSkipped('systemEncoding 非 GBK，跳过混流用例');
        return;
      }
      final out = <String>[];
      final sink = const MixedEncoding(systemEncoding)
          .decoder
          .startChunkedConversion(ChunkedConversionSink.withCallback(
              (chunks) => out.addAll(chunks)));

      // 真实顺序：先 taskkill(GBK)、再 server.py 的分隔线与日志(utf-8)
      sink.add(gbkBytes('成功: 已终止 PID 5944 的进程。\n'));
      sink.add(utf8.encode('════════ START ════════\n'));
      sink.add(gbkBytes('错误: 没有找到进程 python.exe\n'));
      sink.add(utf8.encode('INFO    |22:41:24.8| │ Uvicorn running\n'));
      sink.close();

      final all = out.join();
      expect(all, contains('成功: 已终止 PID 5944 的进程。'),
          reason: 'GBK 行应正确还原，实际: $all');
      expect(all, contains('════════ START ════════'),
          reason: 'utf-8 分隔线应正确还原');
      expect(all, contains('错误: 没有找到进程 python.exe'));
      expect(all, contains('│ Uvicorn running'));
      // 两类乱码特征都不许出现
      expect(all, isNot(contains('�')), reason: '不应有替换字符');
      expect(all, isNot(contains('鈺')), reason: '不应有 utf-8 被按 GBK 解的痕迹');
    });

    test('UTF-8 字符跨块时等待补齐后再解码', () async {
      const line = '跨块中文😀';
      final out = <String>[];
      final sink = const MixedEncoding(systemEncoding)
          .decoder
          .startChunkedConversion(ChunkedConversionSink.withCallback(
              (chunks) => out.addAll(chunks)));

      // 故意每次只喂一个字节，覆盖三字节中文和四字节 emoji 的跨块场景。
      for (final byte in utf8.encode(line)) {
        sink.add([byte]);
      }
      sink.close();

      expect(out.join(), line);
    });
    test('无法解码的字节也不抛异常、不终止流', () async {
      // 流一旦出错就终止，后续所有日志都收不到——这是必须兜住的
      final out = <String>[];
      final sink = const MixedEncoding(systemEncoding)
          .decoder
          .startChunkedConversion(ChunkedConversionSink.withCallback(
              (chunks) => out.addAll(chunks)));

      sink.add([0xFF, 0xFE, 0xFF]); // 既非合法 utf-8 也非合法 GBK 序列
      sink.add(utf8.encode('后续行必须照常到达\n'));
      sink.close();

      expect(out.join(), contains('后续行必须照常到达'), reason: '坏字节不得中断流');
    });
  });

  group('接线检查', () {
    test('ServerLauncher 的日志流与 Shell 都用 MixedEncoding', () {
      // 三处都要用同一套判别，漏一处就有一条路径乱码（踩过：只改了 Shell 的
      // stdoutEncoding，界面日志走 ShellLinesController 依旧乱码）
      final source =
          File('lib/service/server_launcher.dart').readAsStringSync();
      expect(
          source.contains(
              'ShellLinesController(encoding: const MixedEncoding(systemEncoding))'),
          isTrue,
          reason: '界面日志走 ShellLinesController，必须传 MixedEncoding');
      expect(
          source
              .contains('stdoutEncoding: const MixedEncoding(systemEncoding)'),
          isTrue);
      expect(
          source
              .contains('stderrEncoding: const MixedEncoding(systemEncoding)'),
          isTrue);
      // 固定编码是踩过的坑，不得退回
      expect(source.contains('Utf8Codec(allowMalformed: true)'), isFalse,
          reason: '固定 utf-8 会让 taskkill 的 GBK 中文变替换字符');
      expect(source.contains('ShellLinesController();'), isFalse,
          reason: '无参构造用 systemEncoding，utf-8 分隔线会乱码');
    });
  });
}
