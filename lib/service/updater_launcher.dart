// lib/service/updater_launcher.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:oasx/service/server_launcher.dart';

/// 本地更新器：直接 spawn OAS 安装目录下的 `python -m deploy.update`，
/// 不经过 server 的 HTTP 接口。
///
/// 为什么必须绕开 server：
/// Windows 锁定已加载的 onnxruntime_providers_shared.dll，而 server.py / gui.py /
/// script.py 入口都会 preload onnxruntime，Python 又无法卸载已加载的扩展 DLL。
/// 因此 server 进程内发起的 OCR 换包必然 WinError 5 拒绝访问——server 自己就是
/// 锁的持有者。`deploy/update.py` 是不加载 onnxruntime 的干净进程，
/// 由 OASX 在 server 未启动时 spawn，才能真正换掉 ORT 包。
///
/// 三种调用与 deploy/update.py 的三种模式一一对应：
/// [fetchInfo] → --info，[saveConfig] → --set-config，[start] → 无参数执行更新。
class UpdaterLauncher {
  /// OAS 安装根目录（与 ServerLauncher 用的是同一个 rootPathServer）
  final String rootPath;

  UpdaterLauncher({required this.rootPath});

  /// 与 deploy/update.py 约定的机器可读结果行前缀
  static const String jsonPrefix = 'OAS_JSON:';

  /// 从 GetStorage 里取 OAS 安装根目录并校验，取不到或不合法返回 null。
  ///
  /// 与 ServerLauncher 共用同一个 rootPathServer 键与同一套目录校验，
  /// 保证「能启动 server 的目录」和「能跑更新器的目录」判定一致。
  static String? resolveRootPath(String? stored) {
    final root = (stored ?? '').trim();
    if (root.isEmpty) return null;
    return ServerLauncher.validatePath(root) ? root : null;
  }

  /// 内置解释器。用 python.exe 而不是 pythonw.exe：需要 stdout 管道拿进度。
  String get _python => '$rootPath\\toolkit\\python.exe';

  Process? _process;

  /// 更新是否正在进行，用于前端禁用按钮、避免并发跑 git
  bool get isRunning => _process != null;

  /// 从混合输出里挑出 JSON 结果行并解析。
  ///
  /// stdout 里混着 git / pip 的原始输出，靠 [jsonPrefix] 定位；
  /// 取最后一条匹配行（执行更新时结尾那条才是最终结果）。
  static Map<String, dynamic>? parseJsonLine(Iterable<String> lines) {
    Map<String, dynamic>? found;
    for (final line in lines) {
      final idx = line.indexOf(jsonPrefix);
      if (idx < 0) continue;
      try {
        final decoded = jsonDecode(line.substring(idx + jsonPrefix.length));
        if (decoded is Map<String, dynamic>) found = decoded;
      } catch (_) {
        // 单行解析失败不影响其它行，继续往后找
      }
    }
    return found;
  }

  /// 读取仓库信息（分支 / 仓库地址 / commit 对比），server 未启动也可用。
  ///
  /// 返回的 Map 字段与 /home/update_info 一致，可直接喂给 UpdateInfoModel.fromJson。
  Future<Map<String, dynamic>?> fetchInfo() async {
    final result = await _runCaptured(['-m', 'deploy.update', '--info']);
    return result;
  }

  /// 写入 deploy.yaml 的 Repository / Branch。
  ///
  /// 走 stdin 传 JSON，避免仓库地址里的特殊字符被 shell 解释。
  Future<Map<String, dynamic>?> saveConfig({
    String? repository,
    String? branch,
  }) async {
    return _runCaptured(
      ['-m', 'deploy.update', '--set-config'],
      stdinPayload: jsonEncode({
        'repository': repository ?? '',
        'branch': branch ?? '',
      }),
    );
  }

  /// 一次性执行并收集全部输出，用于 --info / --set-config 这类短命令。
  Future<Map<String, dynamic>?> _runCaptured(
    List<String> args, {
    String? stdinPayload,
  }) async {
    try {
      final process = await Process.start(
        _python,
        args,
        workingDirectory: rootPath,
        // 子进程内部按 utf-8 输出中文，显式指定避免 Windows 默认代码页乱码
        environment: {'PYTHONIOENCODING': 'utf-8'},
      );
      if (stdinPayload != null) {
        process.stdin.write(stdinPayload);
      }
      await process.stdin.close();
      final lines = <String>[];
      // stdout / stderr 都要收：deploy.logger 走 stdout，Python 异常走 stderr
      final done = [
        process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .forEach(lines.add),
        process.stderr
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .forEach(lines.add),
      ];
      await Future.wait(done);
      await process.exitCode;
      return parseJsonLine(lines);
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// 执行完整更新。逐行回调进度，结束时回调最终结果。
  ///
  /// [onLog] 收到每一行输出（含 git / pip 原始输出与阶段标记 `> 阶段名`）。
  /// [onDone] 收到 deploy/update.py 结尾那条 JSON 结果；进程异常退出时为 null。
  Future<void> start({
    required void Function(String line) onLog,
    required void Function(Map<String, dynamic>? result, int exitCode) onDone,
  }) async {
    if (isRunning) return;
    final lines = <String>[];
    try {
      _process = await Process.start(
        _python,
        ['-m', 'deploy.update'],
        workingDirectory: rootPath,
        environment: {'PYTHONIOENCODING': 'utf-8'},
      );
    } catch (e) {
      _process = null;
      onLog('ERROR: 无法启动更新器：$e');
      onDone(null, -1);
      return;
    }

    void handle(String line) {
      lines.add(line);
      // JSON 结果行是给程序看的，不往日志区刷
      if (!line.contains(jsonPrefix)) onLog(line);
    }

    final streams = [
      _process!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach(handle),
      _process!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach(handle),
    ];
    await Future.wait(streams);
    final code = await _process!.exitCode;
    _process = null;
    onDone(parseJsonLine(lines), code);
  }

  /// 终止在途更新进程。
  ///
  /// execute_pull 全程幂等，中断后重新点更新会接上剩余阶段，
  /// 所以强杀是安全的（残留的 .git/*.lock 由下次的清理阶段处理）。
  void kill() {
    _process?.kill();
    _process = null;
  }
}
