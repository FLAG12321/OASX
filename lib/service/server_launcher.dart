// lib/service/server_launcher.dart
import 'dart:io';

import 'package:process_run/shell.dart';

// server 拉起器：Server 页手动启动与开机自启自动流程共用。
// 命令序列为 Windows 专属（pythonw.exe / taskkill），从 ServerController 抽出；
// 保留既有副作用：taskkill 会杀掉系统内所有 pythonw 进程。
class ServerLauncher {
  final String rootPath;
  // 日志回流（Server 页日志区或 AutoBootService 的 printInfo）
  final void Function(String line) onLog;

  Shell? _shell;
  final _linesController = ShellLinesController();

  ServerLauncher({required this.rootPath, required this.onLog}) {
    _linesController.stream.listen((event) => onLog('INFO: $event'));
    _shell = _buildShell();
  }

  // 校验 OAS 根目录结构（原 ServerController.authenticatePath 逻辑迁移）：
  // 依次检查根目录、toolkit/python.exe、toolkit/Git/cmd/git.exe、
  // deploy/installer.py、config/deploy.yaml
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

  // PATH 环境（原 ServerController 各 path getter 迁移）。
  // 注：_pathGit 尾部多余引号为原实现遗留，此处原样迁移不做行为改动
  String get _pathGit => '$rootPath\\toolkit\\Git\\mingw64\\bin"';
  String get _pathPython => '$rootPath\\toolkit';
  String get _pathAdb =>
      '$rootPath\\toolkit\\Lib\\site-packages\\adbutils\\binaries';
  String get _pathScripts => '$rootPath\\toolkit\\Scripts';
  Map<String, String> get _pathEnv => {
        'PATH': '$rootPath,$_pathGit,$_pathPython,$_pathAdb,$_pathScripts'
      };

  Shell _buildShell() => Shell(
        workingDirectory: rootPath,
        runInShell: true,
        environment: _pathEnv,
        stdout: _linesController.sink,
        verbose: false,
      );

  Future<void> _runShell(String command) async {
    try {
      final result = await _shell!.run(command);
      // 保留原 ServerController.runShell 的 stderr 汇总输出（installer 报错可见）
      final errText = result.errText;
      if (errText.isNotEmpty) onLog('ERROR: $errText');
    } on ShellException catch (e) {
      onLog('ERROR: ${e.toString()}');
    }
  }

  // 拉起 server（原 ServerController.run 命令序列，fire-and-forget 风格保留）
  Future<void> launch() async {
    _shell!.kill();
    _runShell('echo OAS working directory: ');
    _runShell('pwd');
    _runShell('python -m deploy.installer');
    _runShell('echo Start OAS');
    _runShell('taskkill /f /t /im pythonw.exe');
    _runShell(".\\toolkit\\pythonw.exe  server.py");
  }

  // 终止本实例 shell 中未完成的命令（重复启动前调用，避免旧命令进程残留）
  void kill() {
    _shell?.kill();
  }

  // 释放资源：终止在途命令并关闭日志流，避免旧实例的 stream 监听泄漏
  void dispose() {
    kill();
    _linesController.close();
  }
}
