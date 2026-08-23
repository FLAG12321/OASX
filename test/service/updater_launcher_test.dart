// test/service/updater_launcher_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/api/update_info_model.dart';
import 'package:oasx/service/updater_launcher.dart';

// 中文注释：UpdaterLauncher 的纯函数与契约测试。
//
// spawn 真实 python 子进程属于端到端范围，这里只覆盖两件在重构中最容易断的事：
// 1. 从混合 stdout 里定位 JSON 结果行（git/pip 输出是噪声）；
// 2. `--info` 的 JSON 能被 UpdateInfoModel 原样解析 —— 这是「不重写前端模型」
//    这个设计的前提，契约一破就会静默退化成表格全是占位符。
void main() {
  group('parseJsonLine', () {
    test('从混合输出里挑出 JSON 行', () {
      final lines = [
        'remote: Enumerating objects: 12, done.',
        'Updating c4ada74..e5f6a7b',
        '${UpdaterLauncher.jsonPrefix}{"ok":true,"status":"done"}',
        'Successfully installed onnxruntime-directml-1.23.0',
      ];
      final result = UpdaterLauncher.parseJsonLine(lines);
      expect(result, isNotNull);
      expect(result!['ok'], isTrue);
      expect(result['status'], 'done');
    });

    test('多条 JSON 行时取最后一条', () {
      // 执行更新时结尾那条才是最终结果
      final lines = [
        '${UpdaterLauncher.jsonPrefix}{"status":"running"}',
        '${UpdaterLauncher.jsonPrefix}{"status":"failed"}',
      ];
      expect(UpdaterLauncher.parseJsonLine(lines)!['status'], 'failed');
    });

    test('没有 JSON 行时返回 null', () {
      expect(UpdaterLauncher.parseJsonLine(['fatal: not a git repository']),
          isNull);
    });

    test('单行 JSON 损坏不影响其它行', () {
      final lines = [
        '${UpdaterLauncher.jsonPrefix}{这不是合法 json',
        '${UpdaterLauncher.jsonPrefix}{"status":"done"}',
      ];
      expect(UpdaterLauncher.parseJsonLine(lines)!['status'], 'done');
    });

    test('前缀出现在行中间也能解析', () {
      // deploy.logger 可能给行加前缀，JSON 不一定在行首
      final lines = [
        'INFO ${UpdaterLauncher.jsonPrefix}{"status":"done"}',
      ];
      expect(UpdaterLauncher.parseJsonLine(lines)!['status'], 'done');
    });
  });

  group('resolveRootPath', () {
    test('合法安装目录原样返回，非法与空值返回 null', () {
      final root = Directory.systemTemp.createTempSync('oasx_updater_test');
      addTearDown(() => root.deleteSync(recursive: true));

      // 目录结构不全 → null
      expect(UpdaterLauncher.resolveRootPath(root.path), isNull);

      // 补齐 ServerLauncher.validatePath 要求的标记文件 → 返回路径
      File('${root.path}/toolkit/python.exe').createSync(recursive: true);
      File('${root.path}/toolkit/Git/cmd/git.exe').createSync(recursive: true);
      File('${root.path}/deploy/installer.py').createSync(recursive: true);
      File('${root.path}/deploy/update.py').createSync(recursive: true);
      File('${root.path}/config/deploy.yaml').createSync(recursive: true);
      expect(UpdaterLauncher.resolveRootPath(root.path), root.path);

      expect(UpdaterLauncher.resolveRootPath(null), isNull);
      expect(UpdaterLauncher.resolveRootPath(''), isNull);
      expect(UpdaterLauncher.resolveRootPath('   '), isNull);
    });
  });

  test('kill 不会提前清空进程引用，并会尝试结束 Windows 子进程树', () {
    // 中文注释：start() 必须自己统一收尾，避免 kill 后 exitCode 空解包和 onDone 丢失。
    final source = File('lib/service/updater_launcher.dart').readAsStringSync();
    final killStart = source.indexOf('void kill()');
    final killEnd = source.indexOf('Future<void> _killProcessTree', killStart);
    expect(killStart, greaterThanOrEqualTo(0));
    expect(killEnd, greaterThan(killStart));
    final killBody = source.substring(killStart, killEnd);
    expect(killBody.contains('_process = null'), isFalse);
    expect(source.contains("'taskkill'"), isTrue);
    expect(source.contains('finally'), isTrue);
  });

  group('--info 输出契约', () {
    test('UpdateInfoModel 能原样解析 --info 的 JSON', () {
      // 与 deploy/update.py run_info() 的字段逐一对应；
      // 该形状取自本机真实运行输出
      final json = <String, dynamic>{
        'is_update': false,
        'fetch_ok': true,
        'branch': 'run_now_2',
        'repository': 'https://gitee.com/flag12321/OnmyojiAutoScript.git',
        'current_commit': [
          'c4ada7461c947612d41215a85ad0ab77e77bbb0a',
          'FLAG12321',
          '2026-08-22 08:11:51 +0800',
          'fix(updater): 对齐前终止外部 OCR 服务进程',
        ],
        'latest_commit': [
          'c4ada7461c947612d41215a85ad0ab77e77bbb0a',
          'FLAG12321',
          '2026-08-22 08:11:51 +0800',
          'fix(updater): 对齐前终止外部 OCR 服务进程',
        ],
        'commit': [
          [
            'c4ada7461c947612d41215a85ad0ab77e77bbb0a',
            'FLAG12321',
            '2026-08-22 08:11:51 +0800',
            'fix(updater): 对齐前终止外部 OCR 服务进程',
          ],
        ],
      };

      final model = UpdateInfoModel.fromJson(json);
      expect(model.isUpdate, isFalse);
      expect(model.fetchOk, isTrue);
      expect(model.branch, 'run_now_2');
      expect(model.repository, contains('gitee.com'));
      // commit 四元组必须解析成功，否则表格会渲染成占位符 '—'
      expect(model.currentCommit, isNotNull);
      expect(model.currentCommit!.length, 4);
      expect(model.commit!.length, 1);
    });

    test('fetch 失败时 fetchOk=false，页面据此报错而非假装最新', () {
      final model = UpdateInfoModel.fromJson({
        'is_update': false,
        'fetch_ok': false,
        'branch': 'run_now_2',
        'repository': 'https://example.com/repo.git',
        'current_commit': null,
        'latest_commit': null,
        'commit': [],
      });
      expect(model.fetchOk, isFalse);
      expect(model.latestCommit, isNull);
    });
  });
}
