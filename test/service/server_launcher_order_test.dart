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

  test('按当前 OAS 根目录筛选进程，并早于 deploy.installer', () {
    final scopedKill = indexOfCommand('scopedProcessKillCommand(rootPath)');
    final installer =
        indexOfCommand("await _runShell('python -m deploy.installer')");

    expect(scopedKill, lessThan(installer),
        reason: '必须先停止当前 OAS 进程再换包，否则 ORT DLL 仍可能被锁');
    expect(source.contains('Get-CimInstance Win32_Process'), isTrue,
        reason: '必须按进程路径筛选，不能无差别 taskkill 全局 Python');
    expect(source.contains('taskkill /f /t /pid'), isTrue,
        reason: '必须按 PID 终止当前 OAS 进程');
  });

  test('关键命令必须 await，失败时不得继续启动', () {
    expect(source.contains("await _runShell('python -m deploy.installer')"),
        isTrue,
        reason: '依赖对齐必须完成后才能启动 server');
    expect(source.contains('if (!await _runShell('), isTrue,
        reason: '关键步骤失败必须中止后续流程');
  });

  test('启动 server 那一行不得 await，否则开机自启永久卡死', () {
    // server.py 是常驻进程，await 等于永不返回；
    // AutoBootService await launch() 之后才轮询就绪，会直接死锁。
    final serverCommand = source.lastIndexOf('server.py');
    expect(serverCommand, greaterThanOrEqualTo(0), reason: '仍需拉起 server');
    final launchTail = source.substring(serverCommand - 80, serverCommand + 20);
    expect(launchTail.contains('unawaited(_runShell('), isTrue,
        reason: 'server.py 必须 fire-and-forget，不能 await 常驻进程');
  });
}
