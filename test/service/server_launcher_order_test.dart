// test/service/server_launcher_order_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// 中文注释：锁住 ServerLauncher.launch() 的命令顺序与 await 语义。
//
// launch() 会真的调 shell，不能在单测里执行，所以按源码做静态门禁——
// 这里防的是两个都真实踩过的缺陷：
//
// 1. installer 跑在 taskkill 之前：上一轮 server/实例/OCR 服务还活着、还锁着
//    onnxruntime_providers_shared.dll，换 ORT 包必然 WinError 5，而
//    installer.ocr_install() 失败只 warning 不阻断，静默留下半损坏依赖。
// 2. 最后一行 server.py 若被 await：它是常驻进程永不退出，而
//    AutoBootService 会 await launch() 之后才轮询就绪 —— 开机自启永久卡死。
void main() {
  late String source;

  setUpAll(() {
    source = File('lib/service/server_launcher.dart').readAsStringSync();
  });

  int indexOfCommand(String needle) {
    final idx = source.indexOf(needle);
    expect(idx, greaterThanOrEqualTo(0), reason: '源码里找不到命令：$needle');
    return idx;
  }

  test('taskkill 必须早于 deploy.installer', () {
    final killPythonw = indexOfCommand('taskkill /f /t /im pythonw.exe');
    final killPython = indexOfCommand('taskkill /f /t /im python.exe');
    final installer = indexOfCommand('python -m deploy.installer');

    expect(killPythonw, lessThan(installer),
        reason: '必须先杀 pythonw 再换包，否则 ORT DLL 仍被锁');
    expect(killPython, lessThan(installer),
        reason: '必须先杀 python 再换包：OCR RPC 服务是 python.exe');
  });

  test('taskkill 必须覆盖 python.exe 而不只是 pythonw.exe', () {
    // OCR RPC 服务由 _spawn_server_process 用 sys.executable 启动，
    // 进程名是 python.exe；只杀 pythonw 会漏掉真正持有 ORT DLL 的进程
    expect(source.contains('taskkill /f /t /im python.exe'), isTrue,
        reason: 'OCR 服务是 python.exe，必须一并终止');
  });

  test('taskkill 与 installer 必须 await，否则并发执行顺序无效', () {
    expect(source.contains("await _runShell('taskkill /f /t /im pythonw.exe')"),
        isTrue,
        reason: 'fire-and-forget 会让顺序失效');
    expect(source.contains("await _runShell('taskkill /f /t /im python.exe')"),
        isTrue);
    expect(source.contains("await _runShell('python -m deploy.installer')"),
        isTrue);
  });

  test('启动 server 那一行不得 await，否则开机自启永久卡死', () {
    // server.py 是常驻进程，await 等于永不返回；
    // AutoBootService await launch() 之后才轮询就绪，会直接死锁
    expect(source.contains('await _runShell(".\\\\toolkit\\\\pythonw.exe'),
        isFalse,
        reason: 'server.py 常驻，await 它会让 AutoBootService 永久挂起');
    expect(source.contains('_runShell(".\\\\toolkit\\\\pythonw.exe'), isTrue,
        reason: '仍需拉起 server');
  });
}
