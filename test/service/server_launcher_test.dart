// test/service/server_launcher_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/service/mixed_encoding.dart';
import 'package:oasx/service/server_launcher.dart';
import 'package:process_run/shell.dart';

// 中文注释：测试 ServerLauncher.validatePath 的目录结构校验（原
// ServerController.authenticatePath 逻辑迁移）。launch() 涉及真实 shell，
// 不做单测，由端到端手动验证覆盖。
void main() {
  test('validatePath 校验 python/installer/deploy 三件套，缺 git 视为可自愈', () async {
    final root = Directory.systemTemp.createTempSync('oasx_launcher_test');
    addTearDown(() => root.deleteSync(recursive: true));

    // 空目录 → false
    expect(ServerLauncher.validatePath(root.path), isFalse);

    // 补齐三件套（刻意不含 toolkit/Git）→ true：git 缺失由 installer 自动下载补齐
    File('${root.path}/toolkit/python.exe').createSync(recursive: true);
    File('${root.path}/deploy/installer.py').createSync(recursive: true);
    File('${root.path}/config/deploy.yaml').createSync(recursive: true);
    expect(ServerLauncher.validatePath(root.path), isTrue);

    // 缺 installer.py（纯源码/垃圾目录）→ false，仍然挡住
    final root2 = Directory.systemTemp.createTempSync('oasx_launcher_test2');
    addTearDown(() => root2.deleteSync(recursive: true));
    File('${root2.path}/toolkit/python.exe').createSync(recursive: true);
    File('${root2.path}/config/deploy.yaml').createSync(recursive: true);
    expect(ServerLauncher.validatePath(root2.path), isFalse);

    // 不存在的根目录 → false
    expect(ServerLauncher.validatePath('${root.path}/nope'), isFalse);
  });

  test('PATH 必须用分号分隔、含 Git usr\\bin、且不带尾部引号', () {
    // 回归锚点：启动日志曾反复报 ShellException(pwd, exitCode 1)。三个根因，
    // 前两个被第三个掩盖，逐个修才见效：
    //  1. 分隔符用了逗号——Windows PATH 用 `;`，逗号让整串成为一个畸形路径，
    //     所有目录一起失效（实测 cmd 下逗号 exit=1、分号 exit=0）；
    //  2. _pathGit 尾部带多余引号，PATH 条目嵌 " 会失效；
    //  3. mingw64\bin 里没有 pwd.exe，通用工具在 usr\bin。
    // 源码级断言（getter 都是 private），防任一条被改回去。
    final source = File('lib/service/server_launcher.dart').readAsStringSync();

    // 1. 分号分隔，且整串里不得再出现逗号分隔的痕迹
    expect(
        source.contains(
            r'''$rootPath;$_pathGit;$_pathGitUsr;$_pathPython;$_pathAdb;$_pathScripts'''),
        isTrue,
        reason: 'Windows PATH 必须用分号分隔，逗号会让所有目录失效');
    expect(source.contains(r'''$rootPath,$_pathGit'''), isFalse,
        reason: '不得退回逗号分隔');

    // 2. 无尾部引号
    expect(source.contains(r'''mingw64\\bin';'''), isTrue,
        reason: '_pathGit 应以纯净路径结尾，不带尾部引号');
    expect(source.contains(r'''mingw64\\bin"'''), isFalse,
        reason: 'PATH 条目嵌引号会让目录失效');

    // 3. usr\bin 必须在
    expect(source.contains(r'''Git\\usr\\bin'''), isTrue,
        reason: 'pwd.exe 等在 usr\\bin，PATH 缺它同样找不到命令');
  });

  // 中文注释：真实执行验证。源码断言只能证明写法没退化，证不了 PATH 真的可用——
  // 前两轮修复（去引号、补 usr\bin）都通过了源码断言却依然 pwd 失败，
  // 所以这里用 _pathEnv 同款拼法真跑一次 cmd /c pwd 看退出码。
  //
  // 用 Process.run 而不是 process_run 的 Shell：Shell 在 flutter test 沙箱里
  // 会挂住不返回（实测超时 10 分钟）。cmd /c 是 runInShell 的等价形式。
  test('用同款 PATH 拼法真实执行 pwd 必须成功', () async {
    // OASX 在 <yys>/OnmyojiAutoScript-easy-install/OASX_last/OASX，
    // OAS 在 <yys>/OnmyojiAutoScript-easy-install/OnmyojiAutoScript-easy-install
    final root =
        '${Directory.current.parent.parent.path}\\OnmyojiAutoScript-easy-install';
    if (!Directory('$root\\toolkit\\Git\\usr\\bin').existsSync()) {
      markTestSkipped('未找到 OAS 的 toolkit/Git/usr/bin，跳过真实执行校验');
      return;
    }
    // 与 _pathEnv 同款：分号分隔、含 usr\bin、无引号
    final path = [
      root,
      '$root\\toolkit\\Git\\mingw64\\bin',
      '$root\\toolkit\\Git\\usr\\bin',
      '$root\\toolkit',
    ].join(';');
    final r = await Process.run('cmd', ['/c', 'pwd'],
        environment: {'PATH': path},
        includeParentEnvironment: false,
        workingDirectory: root);
    expect(r.exitCode, 0, reason: 'pwd 应能被找到并成功执行，实际 stderr=${r.stderr}');
  });

  test('子进程输出必须逐块判别编码，否则中文乱码或直接中断启动链', () {
    // 两个回归锚点：
    //  1. 分隔线显示成 `鈺愨晲鈺愨晲...` —— utf-8 字节被按 GBK(936) 解码
    //     （实测 '──' 的 utf-8 字节按 GBK 解正是 `鈹€鈹€`）；
    //  2. 日志停在「Stop existing OAS processes」、server 根本没启动 ——
    //     严格 utf8 解码 taskkill 的 GBK 中文抛 FormatException
    //     （实测 `Unexpected extension byte`），非 ShellException 逃过 catch，
    //     中断了整个 launch()。
    //
    // 两处都要对：
    //   PYTHONIOENCODING          Python 侧按什么编码输出
    //   stdout/stderrEncoding     Dart 侧按什么编码解码（默认 systemEncoding=GBK）
    // 后者用 MixedEncoding 而非固定 utf-8：这个 Shell 还跑 taskkill/adb 等
    // 按活动代码页输出的命令，固定 utf-8 容错会把它们的中文变成 `�ɹ�: ����ֹ`。
    // 具体接线（三处都传 MixedEncoding）由 mixed_encoding_test.dart 的
    // 「接线检查」覆盖，这里只锁 PYTHONIOENCODING 与「不得退回严格 utf8」。
    final source = File('lib/service/server_launcher.dart').readAsStringSync();
    expect(source.contains("'PYTHONIOENCODING': 'utf-8'"), isTrue,
        reason: 'Python 侧需显式 utf-8，否则按 Windows 活动代码页输出');
    // 严格 utf8 是踩过的坑，不得退回
    expect(source.contains('stdoutEncoding: utf8,'), isFalse,
        reason: '严格 utf8 会抛 FormatException 中断 launch()');
    expect(source.contains('stderrEncoding: utf8,'), isFalse,
        reason: '严格 utf8 会抛 FormatException 中断 launch()');
  });

  test('_runShell 必须兜住非 ShellException，单步失败不拖垮启动链', () {
    // launch() 里每一步都 await _runShell，任何异常逃逸都会让后续步骤
    // （含最后启动 server）整个不执行。FormatException 就是这么漏掉的。
    final source = File('lib/service/server_launcher.dart').readAsStringSync();
    final start = source.indexOf('Future<bool> _runShell(');
    expect(start, greaterThanOrEqualTo(0));
    final body = source.substring(start, start + 900);
    expect(body.contains('} catch (e) {'), isTrue,
        reason: '除 ShellException 外还需一个兜底 catch');
  });

  test('容错解码下真实跑 taskkill（GBK 中文输出）不抛异常', () async {
    // 直接复现踩过的坑：严格 utf8 时这行会抛 FormatException。
    // 用不存在的进程名，只看解码路径，不实际杀任何东西。
    final r = await Process.run(
      'cmd',
      ['/c', 'taskkill /f /t /im oasx_nonexistent_probe.exe'],
      stdoutEncoding: const Utf8Codec(allowMalformed: true),
      stderrEncoding: const Utf8Codec(allowMalformed: true),
    );
    // 128 = 没有匹配进程，属预期；关键是走到这里没抛异常
    expect(r.exitCode, isNot(0), reason: '不存在的进程名应返回非 0（通常 128）');
  });

  // 中文注释：界面日志流的接线断言（必须给 ShellLinesController 传 MixedEncoding）
  // 在 mixed_encoding_test.dart 的「接线检查」里，不在这里重复。
  // 这里只做真实解码行为验证——源码断言在前几轮反复"通过但没修好"。
  test('真实 ShellLinesController：utf-8 制表符与 GBK 中文在同一条流里都正确', () async {
    // 用与生产同款的 MixedEncoding。踩过的坑：
    //  * 无参构造 / 固定 GBK  -> 分隔线成 `鈺愨晲`
    //  * 固定 utf-8 容错      -> taskkill 的中文成 `�ɹ�: ����ֹ`
    //  * 固定 utf-8 严格      -> FormatException 终止整条流，后续日志全丢
    final controller =
        ShellLinesController(encoding: const MixedEncoding(systemEncoding));
    final lines = <String>[];
    final done = controller.stream.forEach(lines.add);

    // 1. Python 侧的 utf-8 输出：分隔线与中文必须原样还原
    controller.sink.add(utf8.encode('════ START ════ 任务开始\n'));
    // 2. taskkill 侧的 GBK 中文：既不得抛异常打断流，也不得变成替换字符
    controller.sink.add([0xB3, 0xC9, 0xB9, 0xA6, 0x3A, 0x20, 0x0A]); // "成功: "
    // 3. 流仍然活着，后续 utf-8 行照常还原
    controller.sink.add(utf8.encode('│ Uvicorn running\n'));
    controller.close();
    await done;

    expect(lines.first, contains('════ START ════ 任务开始'),
        reason: 'utf-8 分隔线与中文应原样还原，实际: ${lines.first}');
    expect(lines.first, isNot(contains('鈺')), reason: '出现 鈺 说明按 GBK 解码了');
    // 中文 Windows 上这几个字节是 GBK 的「成功: 」；非 GBK 环境下退回宽容 utf-8，
    // 只要求不抛异常、流不中断，所以中文断言按环境放行
    final isGbkHost = systemEncoding.decode([0xB3, 0xC9]) == '成';
    if (isGbkHost) {
      expect(lines[1], contains('成功'),
          reason: 'GBK 中文应还原而不是替换字符，实际: ${lines[1]}');
      expect(lines[1], isNot(contains('�')),
          reason: '出现 � 说明 GBK 字节被按 utf-8 容错解了');
    }
    expect(lines.last, contains('│ Uvicorn running'),
        reason: 'GBK 字节不得中断流，后续行仍须正确解码，实际: ${lines.last}');
  });

  test('utf-8 环境下真实跑一次 python，中文与制表符原样返回', () async {
    final root =
        '${Directory.current.parent.parent.path}\\OnmyojiAutoScript-easy-install';
    final python = '$root\\toolkit\\python.exe';
    if (!File(python).existsSync()) {
      markTestSkipped('未找到 OAS 的 toolkit/python.exe，跳过真实执行校验');
      return;
    }
    // 与 _pathEnv 同款设置：PYTHONIOENCODING=utf-8 + Dart 侧 utf-8 容错解码
    final r = await Process.run(
      python,
      ['-c', 'print("═──│ 任务开始")'],
      environment: {'PYTHONIOENCODING': 'utf-8'},
      stdoutEncoding: const Utf8Codec(allowMalformed: true),
      stderrEncoding: const Utf8Codec(allowMalformed: true),
      workingDirectory: root,
    );
    expect(r.exitCode, 0, reason: 'stderr=${r.stderr}');
    // 制表符与中文都必须原样回来，出现 `鈺` 说明按 GBK 解了
    expect(r.stdout.toString(), contains('═──│ 任务开始'),
        reason: '实际输出: ${r.stdout}');
    expect(r.stdout.toString(), isNot(contains('鈺')),
        reason: 'utf-8 字节被按 GBK 解码了');
  });
}
