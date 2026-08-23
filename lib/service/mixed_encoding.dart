// lib/service/mixed_encoding.dart
import 'dart:convert';

/// 逐块自动判别 utf-8 / 系统代码页（中文 Windows 是 GBK）的解码器。
///
/// 日志流里混着 Python 的 utf-8 与 Windows 命令的活动代码页输出，固定使用
/// 任意一种编码都会产生乱码，因此完整 utf-8 优先，失败后回退到系统编码。
class MixedEncoding extends Encoding {
  /// 判别失败时退回的编码，通常传 `systemEncoding`。
  final Encoding fallback;

  const MixedEncoding(this.fallback);

  @override
  String get name => 'mixed-utf8-${fallback.name}';

  @override
  Converter<List<int>, String> get decoder => _MixedDecoder(fallback);

  /// 写回子进程 stdin 的内容由 OASX 自己产生，统一使用 utf-8。
  @override
  Converter<String, List<int>> get encoder => utf8.encoder;
}

class _MixedDecoder extends Converter<List<int>, String> {
  final Encoding fallback;

  const _MixedDecoder(this.fallback);

  @override
  String convert(List<int> input) {
    try {
      return utf8.decode(input, allowMalformed: false);
    } on FormatException {
      return _decodeFallback(input, fallback);
    }
  }

  @override
  Sink<List<int>> startChunkedConversion(Sink<String> sink) =>
      _MixedDecoderSink(sink, fallback);
}

String _decodeFallback(List<int> data, Encoding fallback) {
  try {
    return fallback.decode(data);
  } catch (_) {
    // 兜底：无论日志内容如何异常，都不能让整条日志流中断。
    return utf8.decode(data, allowMalformed: true);
  }
}

/// 流式解码器：除编码判别外，保留跨 chunk 的不完整 utf-8 前缀。
class _MixedDecoderSink implements Sink<List<int>> {
  final Sink<String> _out;
  final Encoding _fallback;
  final List<int> _pendingUtf8 = [];

  _MixedDecoderSink(this._out, this._fallback);

  @override
  void add(List<int> data) {
    if (data.isEmpty) return;

    final combined = <int>[..._pendingUtf8, ...data];
    _pendingUtf8.clear();

    final pendingStart = _incompleteUtf8SuffixStart(combined);
    if (pendingStart != null) {
      final complete = combined.sublist(0, pendingStart);
      if (complete.isNotEmpty) {
        _out.add(utf8.decode(complete, allowMalformed: false));
      }
      _pendingUtf8.addAll(combined.sublist(pendingStart));
      return;
    }

    try {
      // 严格 utf-8 成功时，说明当前块（含上块残留）属于 utf-8。
      _out.add(utf8.decode(combined, allowMalformed: false));
    } on FormatException {
      // 在完整 utf-8 失败时，整块回退到系统代码页；不能只回退当前 data，
      // 否则上一个 chunk 末尾的字节会被拆离，产生重复或丢失。
      _out.add(_decodeFallback(combined, _fallback));
    }
  }

  @override
  void close() {
    if (_pendingUtf8.isNotEmpty) {
      _out.add(_decodeFallback(_pendingUtf8, _fallback));
      _pendingUtf8.clear();
    }
    _out.close();
  }
}

/// 返回末尾不完整 utf-8 序列的起点；若不是“仅末尾不完整”，返回 null。
///
/// 只检查最多 3 个字节的尾部前缀，避免把完整 GBK 块误判成跨块 utf-8。
int? _incompleteUtf8SuffixStart(List<int> bytes) {
  final start = bytes.length > 3 ? bytes.length - 3 : 0;
  for (var index = start; index < bytes.length; index++) {
    final expectedLength = _utf8SequenceLength(bytes[index]);
    if (expectedLength == null) continue;
    final available = bytes.length - index;
    if (available >= expectedLength) continue;

    final suffix = bytes.sublist(index);
    if (!suffix.skip(1).every(_isUtf8Continuation)) continue;
    try {
      utf8.decode(bytes.sublist(0, index), allowMalformed: false);
      return index;
    } on FormatException {
      return null;
    }
  }
  return null;
}

int? _utf8SequenceLength(int byte) {
  if (byte >= 0xC2 && byte <= 0xDF) return 2;
  if (byte >= 0xE0 && byte <= 0xEF) return 3;
  if (byte >= 0xF0 && byte <= 0xF4) return 4;
  return null;
}

bool _isUtf8Continuation(int byte) => byte >= 0x80 && byte <= 0xBF;
