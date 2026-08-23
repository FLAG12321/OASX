import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/service/server_operation_lock.dart';

void main() {
  test('OAS 操作按提交顺序串行执行并正确维护 busy 状态', () async {
    // 中文注释：第一项未释放前，第二项不得触碰 Git/进程资源。
    final lock = ServerOperationLock.instance;
    final gate = Completer<void>();
    final events = <String>[];

    final first = lock.run(() async {
      events.add('first-start');
      await gate.future;
      events.add('first-end');
      return 1;
    });
    final second = lock.run(() async {
      events.add('second');
      return 2;
    });

    await Future<void>.delayed(Duration.zero);
    expect(lock.isBusy.value, isTrue);
    expect(events, ['first-start']);

    gate.complete();
    expect(await first, 1);
    expect(await second, 2);
    expect(events, ['first-start', 'first-end', 'second']);
    expect(lock.isBusy.value, isFalse);
  });

  test('前一项异常不会阻断后续 OAS 操作', () async {
    // 中文注释：更新失败后仍允许用户重试，队列不能永久卡死。
    final lock = ServerOperationLock.instance;
    final failed = lock.run<void>(() async {
      throw StateError('expected');
    });
    final next = lock.run(() async => 'ok');

    await expectLater(failed, throwsStateError);
    expect(await next, 'ok');
    expect(lock.isBusy.value, isFalse);
  });
}
