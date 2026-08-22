// lib/service/mixed_encoding.dart
import 'dart:convert';

/// 逐块自动判别 utf-8 / 系统代码页（中文 Windows 是 GBK）的解码器。
///
/// 为什么需要它：`ServerLauncher` 那一条日志流里混着两种编码的输出，
/// 固定用任何一种都会有一半乱码：
///   * `server.py` 的 rich 日志是 utf-8（分隔线 ═ ─ │、中文任务名）；
///     按 GBK 解就得到 `鈺愨晲鈺愨晲`。
///   * `taskkill` / `adb` 等系统命令按活动代码页输出（本机 GBK）；
///     按 utf-8 解，宽容模式下得到 `�ɹ�: ����ֹ`，严格模式下直接抛
///     FormatException 打断整条流。
///
/// 判别依据：GBK 编码的中文几乎不可能同时是合法 utf-8 序列（实测
/// 「成功: 已终止 PID」「错误: 没有找到进程」等均无法通过严格 utf-8 解码），
/// 反之 utf-8 的中文与制表符都能通过。所以先试严格 utf-8，失败再退回代码页。
/// 纯 ASCII 两种编码结果相同，走哪条分支都一样。
///
/// 只按块判别、不跨块保存状态：`ShellLinesController` 喂进来的是子进程
/// 一次 read 的字节块，同一条命令的输出不会混编码，块内一致即可。
/// 代价是一个多字节字符若正好被切在两个块之间会解错一个字符——
/// 这里的用途是给人看的日志，可以接受，换来的是两种编码都不乱码。
class MixedEncoding extends Encoding {
  /// 判别失败时退回的编码，通常传 `systemEncoding`（Windows 活动代码页）。
  final Encoding fallback;

  const MixedEncoding(this.fallback);

  @override
  String get name => 'mixed-utf8-${fallback.name}';

  @override
  Converter<List<int>, String> get decoder => _MixedDecoder(fallback);

  /// 编码一律用 utf-8：写回子进程 stdin 的内容由我们自己产生，
  /// 而 `PYTHONIOENCODING=utf-8` 已让 Python 侧按 utf-8 读。
  @override
  Converter<String, List<int>> get encoder => utf8.encoder;
}

class _MixedDecoder extends Converter<List<int>, String> {
  final Encoding fallback;

  const _MixedDecoder(this.fallback);

  @override
  String convert(List<int> input) {
    try {
      // 严格 utf-8：非法字节会抛，据此判定这块不是 utf-8
      return utf8.decode(input, allowMalformed: false);
    } on FormatException {
      return fallback.decode(input);
    }
  }

  @override
  Sink<List<int>> startChunkedConversion(Sink<String> sink) =>
      _MixedDecoderSink(sink, fallback);
}

/// 流式解码：每个字节块独立判别。
class _MixedDecoderSink implements Sink<List<int>> {
  final Sink<String> _out;
  final Encoding _fallback;

  _MixedDecoderSink(this._out, this._fallback);

  @override
  void add(List<int> data) {
    if (data.isEmpty) return;
    try {
      _out.add(utf8.decode(data, allowMalformed: false));
    } on FormatException {
      try {
        _out.add(_fallback.decode(data));
      } catch (_) {
        // 兜底：连代码页也解不了时用宽容 utf-8，绝不让异常打断日志流
        // （流一旦出错就终止，后续所有日志都收不到）
        _out.add(utf8.decode(data, allowMalformed: true));
      }
    }
  }

  @override
  void close() => _out.close();
}
