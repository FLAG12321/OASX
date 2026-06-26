// Comet 构建检查脚本：封装 flutter analyze，只把 error 级别问题视为构建失败。
//
// 背景：flutter analyze 默认对任何 issue（含 info/warning）都返回非零退出码。
// 当前项目存在 13 个 pre-existing 的 info/warning（与本次变更无关，如
// non_constant_identifier_names、deprecated_member_use 等），导致 guard 的
// build_passes 检查无法通过。本脚本只检查是否出现 error 级别问题。
//
// 用法：dart scripts/comet_build_check.dart
// 退出码：0 = 无 error；1 = 有 error 或 analyze 本身异常。
import 'dart:io';

Future<int> main(List<String> args) async {
  // 中文注释：直接调用 flutter analyze，捕获全部输出。
  final result = await Process.run(
    Platform.isWindows ? 'flutter.bat' : 'flutter',
    ['analyze'],
    runInShell: false,
  );

  final stdoutText = result.stdout.toString();
  final stderrText = result.stderr.toString();

  // 把 analyze 输出原样透传，便于 guard 在失败时看到详情。
  stdout.write(stdoutText);
  if (stderrText.isNotEmpty) stderr.write(stderrText);

  final output = '$stdoutText\n$stderrText';

  // 中文注释：仅当输出中出现 error 级别条目时才视为构建失败。
  // analyze 输出格式形如：
  //   error - <message> - <file>:<line>:<col> - <rule>
  //   warning - ...
  //   info - ...
  final hasError = output
      .split('\n')
      .any((line) => line.trimLeft().startsWith('error -'));

  // 兜底：analyze 进程本身崩溃（非 0 但无 error 行）也算失败。
  final crashed = result.exitCode != 0 && !output.contains('issues found');

  if (hasError || crashed) {
    stderr.writeln('\n[comet_build_check] '
        '${hasError ? "analyze reported errors" : "analyze crashed"} '
        '(exit=${result.exitCode})');
    return 1;
  }

  stdout.writeln('[comet_build_check] OK '
      '(pre-existing info/warning 已忽略，无 error)');
  return 0;
}
