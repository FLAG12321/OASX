import 'package:get/get.dart';

/// OAS 相关操作共用的异步互斥。
///
/// 更新、读取仓库信息、保存更新配置和启动 Server 都会触碰同一套 Git、配置
/// 或 Python 进程资源，必须串行执行。锁在排队时就标记为 busy，UI 可以立即
/// 禁止相关按钮，避免用户在前一个操作结束前重复点击。
class ServerOperationLock {
  ServerOperationLock._();

  /// 全局唯一锁，ServerLauncher 与 UpdaterController 必须共用这一实例。
  static final instance = ServerOperationLock._();

  final isBusy = false.obs;
  Future<void>? _tail;
  int _pending = 0;

  /// 将操作加入队列并等待其独占执行。
  Future<T> run<T>(Future<T> Function() action) {
    _pending++;
    isBusy.value = true;

    final previous = _tail ?? Future<void>.value();
    late final Future<T> current;
    current = previous.then((_) async {
      try {
        return await action();
      } finally {
        _pending--;
        if (_pending == 0) isBusy.value = false;
      }
    });

    // 吞掉前一个操作的异常，只让异常传给当前调用方，不阻断后续队列。
    _tail = current.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return current;
  }
}
