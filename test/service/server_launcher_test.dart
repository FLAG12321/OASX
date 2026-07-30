// test/service/server_launcher_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/service/server_launcher.dart';

// 中文注释：测试 ServerLauncher.validatePath 的目录结构校验（原
// ServerController.authenticatePath 逻辑迁移）。launch() 涉及真实 shell，
// 不做单测，由端到端手动验证覆盖。
void main() {
  test('validatePath 校验 toolkit/git/installer/deploy 缺一不可', () async {
    final root = Directory.systemTemp.createTempSync('oasx_launcher_test');
    addTearDown(() => root.deleteSync(recursive: true));

    // 空目录 → false
    expect(ServerLauncher.validatePath(root.path), isFalse);

    // 补齐全部标记文件 → true
    File('${root.path}/toolkit/python.exe').createSync(recursive: true);
    File('${root.path}/toolkit/Git/cmd/git.exe').createSync(recursive: true);
    File('${root.path}/deploy/installer.py').createSync(recursive: true);
    File('${root.path}/config/deploy.yaml').createSync(recursive: true);
    expect(ServerLauncher.validatePath(root.path), isTrue);

    // 不存在的根目录 → false
    expect(ServerLauncher.validatePath('${root.path}/nope'), isFalse);
  });
}
