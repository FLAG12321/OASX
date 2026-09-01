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
  // 刻意不检查 toolkit/Git 与 config/deploy.yaml：git 缺失时启动会走
  // deploy.installer 的 ensure_git_ready()（deploy/git.py:121）自动下载完整版
  // 补齐，而它恰恰是 installer 才装的东西——硬性要求 git 预先存在会挡住
  // 手动拷贝的残缺安装（鸡生蛋）；deploy.yaml 已不在 OAS 仓库中分发，
  // DeployConfig 初始化时会从 deploy/template 自动生成。真正必需的是 python、
  // installer 与 template：有它们就能自愈。
  static bool validatePath(String root) {
    try {
      if (!Directory(root).existsSync()) return false;
      if (!File('$root/toolkit/python.exe').existsSync()) return false;
      if (!File('$root/deploy/installer.py').existsSync()) return false;
      if (!File('$root/deploy/template').existsSync()) return false;
    } catch (_) {
      return false;
    }
    return true;
  }

  // 构造只匹配当前 OAS 根目录的进程清理命令，供运行逻辑与测试共用。
  // PowerShell 读取 Win32_Process.CommandLine 后再按根目录过滤，不能使用
  // `taskkill /im python*.exe` 这种会误伤其它项目的全局匹配。
  // 用绝对路径而非裸 `powershell`：个别机器的 PATH 不含 PowerShell 目录，
  // 裸命令会直接「不是内部或外部命令」。不用 %SystemRoot%：process_run 的
  // runInShell 不走 cmd 的 %VAR% 展开，硬编码 Win10/11 恒定路径最稳。
  //
  // 成败判定用「复查存活」而不是逐条 taskkill 退出码：OAS server 会带
  // OCR 子进程与 multiprocessing 实例子进程，枚举顺序里父进程排第一时，
  // `taskkill /f /t` 树杀会连带杀光全部子进程，之后循环里对已死子进程
  // PID 的 taskkill 必然报 128「找不到进程」——那是树杀的连带效果而非
  // 失败。逐条判退出码会把这种正常情况误报成 exit 1。树杀后复查一次
  // 过滤条件，仍有存活才真正算失败。
  static String scopedProcessKillCommand(String root) {
    final escapedRoot = root.replaceAll("'", "''");
    return [
      r'''C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference = 'Stop'; $root = ''',
      "'$escapedRoot'",
      r'''; $prefix = [IO.Path]::GetFullPath($root).TrimEnd('\') + '\'; $filter = { $_.Name -in @('python.exe','pythonw.exe') -and (($_.ExecutablePath -and [IO.Path]::GetFullPath($_.ExecutablePath).StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) -or ($_.CommandLine -and $_.CommandLine.Replace('/','\').IndexOf($prefix, [StringComparison]::OrdinalIgnoreCase) -ge 0)) }; $processes = @(Get-CimInstance Win32_Process | Where-Object $filter); foreach ($target in $processes) { taskkill /f /t /pid $target.ProcessId | Out-Null }; Start-Sleep -Milliseconds 300; $left = @(Get-CimInstance Win32_Process | Where-Object $filter); if ($left.Count -gt 0) { exit 1 } else { exit 0 }"''',
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
      // result 为 null 的 ShellException（'Killed by framework' / 'Script was
      // killed'）是本类主动 kill()/dispose() 旧 shell 会话的预期产物，不是
      // 命令失败：launch() 开头会 kill 上一个会话，ServerController.run()
      // 替换旧 launcher 时也会 dispose。真实命令失败时 process_run 会带上
      // 非 null 的 result（含退出码），才值得按 ERROR 对待。
      if (e.result == null) {
        onLog('INFO: shell 会话已终止: ${e.message}');
        return false;
      }
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
      // cmd.exe 下 pwd 不是内置命令，靠 PATH 里的 pwd.exe（来自 Git）兜底；
      // 全新安装时 toolkit/Git 尚未下载（installer 才下载），pwd 会 exit 1 挡住启动。
      // 改用 cmd 内置 cd：零依赖、恒返回 0，且在 cmd 下会回显当前目录。
      if (!await _runShell('cd')) return false;
      if (!await _runShell('echo Stop existing OAS processes')) return false;
      // 杀进程失败不中断启动：installer 内部有 pywin32 的进程清理作为真正的
      // 闸门（杀不掉会 raise ExecutionError 中止安装），这里只是提前清理，
      // 失败不阻断（实测个别机器 powershell 不可用或进程跨提权杀不掉）。
      await _runShell(scopedProcessKillCommand(rootPath));
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
