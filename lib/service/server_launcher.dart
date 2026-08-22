// lib/service/server_launcher.dart
// systemEncoding 来自 dart:io（不是 dart:convert），MixedEncoding 只需要它
import 'dart:io';

import 'package:oasx/service/mixed_encoding.dart';
import 'package:process_run/shell.dart';

// server 拉起器：Server 页手动启动与开机自启自动流程共用。
// 命令序列为 Windows 专属（pythonw.exe / taskkill），从 ServerController 抽出；
// 保留既有副作用：taskkill 会杀掉系统内所有 pythonw 进程。
class ServerLauncher {
  final String rootPath;
  // 日志回流（Server 页日志区或 AutoBootService 的 printInfo）
  final void Function(String line) onLog;

  Shell? _shell;
  // 日志流的解码必须在这里指定，而不是 Shell 的 stdoutEncoding。
  //
  // ShellLinesController 自带 encoding 字段（默认 shellContext.encoding，
  // 本机是 systemEncoding=GBK），onLog 收到的每一行都由它解码；
  // Shell 的 stdoutEncoding 只管 result.outText/errText。踩过的坑：只改
  // Shell 那个，分隔线依旧是 `鈺愨晲`——因为界面日志走的是本控制器。
  //
  // 用 MixedEncoding 逐块自动判别，而不是固定 utf-8：这条流混着
  // Python 的 utf-8 日志（分隔线 ═ ─ │）与 taskkill/adb 的 GBK 中文，
  // 固定任何一种都有一半乱码——固定 GBK 时分隔线成 `鈺愨晲`，
  // 固定 utf-8 宽容模式时 taskkill 成 `�ɹ�: ����ֹ`，严格模式还会抛
  // FormatException 打断整条流。
  final _linesController =
      ShellLinesController(encoding: const MixedEncoding(systemEncoding));

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
  //
  // 这里踩过三个坑，缺一个 pwd 就跑不起来（启动日志报
  // `ShellException(pwd, exitCode 1)`）：
  //   1. 分隔符必须是分号：Windows PATH 用 `;` 分隔，原实现用的是逗号，
  //      整串被当成一个畸形路径，**所有**目录一起失效（实测逗号 exit=1、
  //      分号 exit=0）。这是最致命的一个，另两个都被它掩盖着。
  //   2. _pathGit 尾部曾带一个多余引号：PATH 条目里嵌 " 会让该条目失效。
  //   3. pwd.exe 不在 mingw64\bin：Git for Windows 的通用 Unix 工具
  //      （pwd/ls/echo 等）在 usr\bin，必须单独拼一条。
  String get _pathGit => '$rootPath\\toolkit\\Git\\mingw64\\bin';
  String get _pathGitUsr => '$rootPath\\toolkit\\Git\\usr\\bin';
  String get _pathPython => '$rootPath\\toolkit';
  String get _pathAdb =>
      '$rootPath\\toolkit\\Lib\\site-packages\\adbutils\\binaries';
  String get _pathScripts => '$rootPath\\toolkit\\Scripts';
  Map<String, String> get _pathEnv => {
        'PATH':
            '$rootPath;$_pathGit;$_pathGitUsr;$_pathPython;$_pathAdb;$_pathScripts',
        // server.py 的 rich 日志按 utf-8 输出（含 ═ ─ │ 等制表符与中文）。
        // 不指定时 Python 在 Windows 上按活动代码页（本机 GBK/936）输出，
        // 分隔线会变成 `鈺愨晲` 这类乱码。与 updater_launcher 保持一致。
        'PYTHONIOENCODING': 'utf-8',
      };

  Shell _buildShell() => Shell(
        workingDirectory: rootPath,
        runInShell: true,
        environment: _pathEnv,
        stdout: _linesController.sink,
        // 与 _linesController 用同一套逐块判别（见 MixedEncoding）：
        // result.errText 里同样混着 Python 的 utf-8 与系统命令的 GBK。
        // 严格 utf8 曾在这里抛 FormatException 中断整个 launch()。
        stdoutEncoding: const MixedEncoding(systemEncoding),
        stderrEncoding: const MixedEncoding(systemEncoding),
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
    } catch (e) {
      // 兜住非 ShellException 的一切：launch() 里每一步都 await 本方法，
      // 任何异常逃逸都会中断后续步骤、server 永不启动（曾因严格 utf8 解码
      // taskkill 的 GBK 中文抛 FormatException 踩到，日志停在
      // 「Stop existing OAS processes」）。单步失败不该拖垮整条启动链。
      onLog('ERROR: $command -> ${e.runtimeType}: $e');
    }
  }

  // 拉起 server。
  //
  // 顺序至关重要：必须先 taskkill 再对齐依赖。Windows 锁定已加载的
  // onnxruntime_providers_shared.dll，上一轮的 server / 实例 / OCR 服务只要还活着
  // 就锁着它，此时换 ORT 包必然 WinError 5，而 installer.ocr_install() 失败只
  // warning 不阻断，会静默留下半损坏的依赖（远程机器 OCR 全挂的根因）。
  //
  // 前几步必须 await：此前全部 fire-and-forget，实际并发执行，
  // 即使顺序写对了也不保证 taskkill 在换包前完成。
  //
  // taskkill 要同时覆盖 python.exe：OCR RPC 服务由 _spawn_server_process 用
  // sys.executable 启动，进程名是 python.exe 而非 pythonw.exe，
  // 只杀 pythonw 会漏掉真正持有 ORT DLL 的那个进程。
  Future<void> launch() async {
    _shell!.kill();
    await _runShell('echo OAS working directory: ');
    await _runShell('pwd');
    await _runShell('echo Stop existing OAS processes');
    await _runShell('taskkill /f /t /im pythonw.exe');
    await _runShell('taskkill /f /t /im python.exe');
    await _runShell('echo Align dependencies');
    await _runShell('python -m deploy.installer');
    await _runShell('echo Start OAS');
    // 最后一步刻意不 await：server.py 是常驻进程，等它退出等于永不返回，
    // 而 AutoBootService 会 await launch() 之后才开始轮询就绪，
    // await 这一行将让开机自启永久卡死。就绪判定交给调用方轮询。
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
