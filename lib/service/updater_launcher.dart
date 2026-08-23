// lib/service/updater_launcher.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:oasx/service/server_launcher.dart';

/// 本地更新器：直接 spawn OAS 安装目录下的 `python -m deploy.update`，
/// 不经过 server 的 HTTP 接口。
///
/// Windows 锁定已加载的 onnxruntime DLL，因此更新必须由不加载 OCR 的干净进程执行。
/// 进度从 stdout/stderr 流式回传，结束后用固定前缀解析机器可读结果。
class UpdaterLauncher {
  /// OAS 安装根目录（与 ServerLauncher 使用同一个 rootPathServer）。
  final String rootPath;

  UpdaterLauncher({required this.rootPath});

  /// 与 deploy/update.py 约定的机器可读结果行前缀。
  static const String jsonPrefix = 'OAS_JSON:';

  /// 从 GetStorage 中解析并校验 OAS 安装根目录。
  static String? resolveRootPath(String? stored) {
    final root = (stored ?? '').trim();
    if (root.isEmpty) return null;
    // Server 可以启动旧版安装，但本地更新器必须确认新入口存在。
    if (!ServerLauncher.validatePath(root)) return null;
    return File('$root\\deploy\\update.py').existsSync() ? root : null;
  }

  /// 内置解释器。使用 python.exe 而不是 pythonw.exe，以便读取实时输出。
  String get _python => '$rootPath\\toolkit\\python.exe';

  Process? _process;

  /// 当前是否存在尚未收尾的更新进程。
  bool get isRunning => _process != null;

  /// 从混合输出中挑出最后一条 JSON 结果行。
  static Map<String, dynamic>? parseJsonLine(Iterable<String> lines) {
    Map<String, dynamic>? found;
    for (final line in lines) {
      final idx = line.indexOf(jsonPrefix);
      if (idx < 0) continue;
      try {
        final decoded = jsonDecode(line.substring(idx + jsonPrefix.length));
        if (decoded is Map<String, dynamic>) found = decoded;
      } catch (_) {
        // 单行损坏不影响后续结果行解析。
      }
    }
    return found;
  }

  /// 读取仓库信息，server 未启动时也可执行。
  Future<Map<String, dynamic>?> fetchInfo() async {
    return _runCaptured(['-m', 'deploy.update', '--info']);
  }

  /// 写入 deploy.yaml 的 Repository / Branch。
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

  /// 执行短命令并收集全部输出，用于 --info / --set-config。
  Future<Map<String, dynamic>?> _runCaptured(
    List<String> args, {
    String? stdinPayload,
  }) async {
    try {
      final process = await Process.start(
        _python,
        args,
        workingDirectory: rootPath,
        // 保留父进程环境，只覆盖 Python 输出编码，避免子进程找不到系统工具。
        environment: {
          ...Platform.environment,
          'PYTHONIOENCODING': 'utf-8',
        },
      );
      if (stdinPayload != null) process.stdin.write(stdinPayload);
      await process.stdin.close();
      final lines = <String>[];
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

  /// 执行完整更新并逐行回调进度。
  Future<void> start({
    required void Function(String line) onLog,
    required void Function(Map<String, dynamic>? result, int exitCode) onDone,
  }) async {
    if (isRunning) return;

    final lines = <String>[];
    Process? process;
    var doneCalled = false;

    void finish(Map<String, dynamic>? result, int exitCode) {
      if (doneCalled) return;
      doneCalled = true;
      onDone(result, exitCode);
    }

    try {
      process = await Process.start(
        _python,
        ['-m', 'deploy.update'],
        workingDirectory: rootPath,
        environment: {
          ...Platform.environment,
          'PYTHONIOENCODING': 'utf-8',
        },
      );
      _process = process;

      void handle(String line) {
        lines.add(line);
        // JSON 结果行仅供程序解析，不重复刷到日志区。
        if (!line.contains(jsonPrefix)) onLog(line);
      }

      final streams = [
        process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .forEach(handle),
        process.stderr
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .forEach(handle),
      ];
      await Future.wait(streams);
      final code = await process.exitCode;
      finish(parseJsonLine(lines), code);
    } catch (e) {
      onLog('ERROR: 更新器运行失败：$e');
      finish(null, -1);
    } finally {
      // 只清理本次 start 创建的进程，避免旧任务的 finally 覆盖新任务状态。
      if (identical(_process, process)) _process = null;
    }
  }

  /// 终止更新器及其派生的 git/pip/cmd 进程。
  ///
  /// 不立即清空 [_process]：让 start() 的 finally 统一收尾，避免 exitCode 空引用
  /// 和 onDone 丢失。
  void kill() {
    final process = _process;
    if (process == null) return;
    if (Platform.isWindows) {
      unawaited(_killProcessTree(process));
    } else {
      process.kill();
    }
  }

  Future<void> _killProcessTree(Process process) async {
    try {
      final result = await Process.run(
        'taskkill',
        ['/f', '/t', '/pid', '${process.pid}'],
      );
      if (result.exitCode != 0) process.kill();
    } catch (_) {
      // taskkill 不可用时至少终止直接子进程，避免更新器永久悬挂。
      process.kill();
    }
  }
}
