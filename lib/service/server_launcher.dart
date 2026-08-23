// lib/service/server_launcher.dart
// systemEncoding 来自 dart:io（不是 dart:convert），MixedEncoding 只需要它
import 'dart:async';
import 'dart:io';

import 'package:oasx/service/mixed_encoding.dart';
import 'package:oasx/service/server_operation_lock.dart';
import 'package:process_run/shell.dart';

/// Server 拉起器：Server 页手动启动与开机自启自动流程共用。
///
/// 所有 Windows 进程清理都按 OAS 根目录过滤，禁止无差别结束机器上的其它
/// Python/PythonW 进程。
class ServerLauncher {
  final String rootPath;
  // 日志回流（Server 页日志区或 AutoBootService 的 printInfo）
  final void Function(String line) onLog;

  Shell? _shell;
  final _linesController =
      ShellLinesController(encoding: const MixedEncoding(systemEncoding));

  ServerLauncher({required this.rootPath, required this.onLog}) {
    _linesController.stream.listen((event) => onLog('INFO: $event'));
    _shell = _buildShell();
  }

  // 校验 OAS 根目录结构（原 ServerController.authenticatePath 逻辑迁移）。
  static bool validatePath(String root) {
    try {
      if (!Directory(root).existsSync()) return false;
      if (!File('$root/toolkit/python.exe').existsSync()) return false;
      if (!File('$root/toolkit/Git/cmd/git.exe').existsSync()) return false;
      if (!File('$root/deploy/installer.py').existsSync()) return false;
      if (!File('$root/config/deploy.yaml').existsSync()) return false;
    } catch (_) {
      return false;
    }
    return true;
  }

  // 构造只匹配当前 OAS 根目录的进程清理命令，供运行逻辑与测试共用。
  // PowerShell 读取 Win32_Process.CommandLine 后再按根目录过滤，不能使用
  // `taskkill /im python*.exe` 这种会误伤其它项目的全局匹配。
  static String scopedProcessKillCommand(String root) {
    final escapedRoot = root.replaceAll("'", "''");
    return [
      r'''powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference = 'Stop'; $root = ''',
      "'$escapedRoot'",
      r'''; $prefix = [IO.Path]::GetFullPath($root).TrimEnd('\') + '\'; $failed = $false; $processes = @(Get-CimInstance Win32_Process | Where-Object { $_.Name -in @('python.exe','pythonw.exe') -and (($_.ExecutablePath -and [IO.Path]::GetFullPath($_.ExecutablePath).StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) -or ($_.CommandLine -and $_.CommandLine.Replace('/','\').IndexOf($prefix, [StringComparison]::OrdinalIgnoreCase) -ge 0)) }); foreach ($target in $processes) { taskkill /f /t /pid $target.ProcessId | Out-Null; if ($LASTEXITCODE -ne 0) { $failed = $true } }; if ($failed) { exit 1 } else { exit 0 }"''',
    ].join();
  }

  String get _pathGit => '$rootPath\\toolkit\\Git\\mingw64\\bin';
  String get _pathGitUsr => '$rootPath\\toolkit\\Git\\usr\\bin';
  String get _pathPython => '$rootPath\\toolkit';
  String get _pathAdb =>
      '$rootPath\\toolkit\\Lib\\site-packages\\adbutils\\binaries';
  String get _pathScripts => '$rootPath\\toolkit\\Scripts';
  Map<String, String> get _pathEnv => {
        // process_run 默认不继承父环境；保留系统环境，否则 powershell、taskkill
        // 以及 Python 的 TEMP/SystemRoot 等关键变量可能不可用。
        ...Platform.environment,
        'PATH':
            '$rootPath;$_pathGit;$_pathGitUsr;$_pathPython;$_pathAdb;$_pathScripts;${Platform.environment['PATH'] ?? ''}',
        // Python 日志固定按 utf-8 输出，避免 Windows 活动代码页污染 rich 分隔线。
        'PYTHONIOENCODING': 'utf-8',
      };

  Shell _buildShell() => Shell(
        workingDirectory: rootPath,
        runInShell: true,
        environment: _pathEnv,
        stdout: _linesController.sink,
        stdoutEncoding: const MixedEncoding(systemEncoding),
        stderrEncoding: const MixedEncoding(systemEncoding),
        verbose: false,
      );

  /// 执行一步命令并返回是否成功；非零退出码和异常都视为失败。
  Future<bool> _runShell(String command) async {
    try {
      final results = await _shell!.run(command);
      final errText = results.errText;
      if (errText.isNotEmpty) onLog('ERROR: $errText');
      final failed = results.any((result) => result.exitCode != 0);
      if (failed) {
        onLog('ERROR: command failed: $command');
        return false;
      }
      return true;
    } on ShellException catch (e) {
      onLog('ERROR: ${e.toString()}');
      return false;
    } catch (e) {
      onLog('ERROR: $command -> ${e.runtimeType}: $e');
      return false;
    }
  }

  /// 拉起 Server。清理、依赖对齐和启动命令串行执行，任一步失败都会停止。
  Future<bool> launch() {
    return ServerOperationLock.instance.run(() async {
      _shell!.kill();
      if (!await _runShell('echo OAS working directory: ')) return false;
      if (!await _runShell('pwd')) return false;
      if (!await _runShell('echo Stop existing OAS processes')) return false;
      if (!await _runShell(scopedProcessKillCommand(rootPath))) return false;
      if (!await _runShell('echo Align dependencies')) return false;
      if (!await _runShell('python -m deploy.installer')) return false;
      if (!await _runShell('echo Start OAS')) return false;

      // server.py 是常驻进程，不能 await；但前面的关键步骤已全部成功。
      unawaited(_runShell('.\\toolkit\\pythonw.exe  server.py'));
      return true;
    });
  }

  // 终止本实例 shell 中未完成的命令。
  void kill() {
    _shell?.kill();
  }

  // 释放资源：终止在途命令并关闭日志流，避免旧实例的 stream 监听泄漏。
  void dispose() {
    kill();
    _linesController.close();
  }
}
