import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import 'package:oasx/api/update_info_model.dart';
import 'package:oasx/service/server_operation_lock.dart';
import 'package:oasx/service/updater_launcher.dart';

/// 更新器状态控制器。
///
/// 更新器面板、Server 页 FAB 和 Home 页入口共用此控制器，所有仓库相关操作
/// 还要经过 ServerOperationLock，避免 Git、deploy.yaml 与 Python 进程并发互相踩踏。
class UpdaterController extends GetxController {
  /// 取全局唯一实例，未注册时按需注册。
  static UpdaterController ensure() {
    if (Get.isRegistered<UpdaterController>()) {
      return Get.find<UpdaterController>();
    }
    return Get.put<UpdaterController>(UpdaterController(), permanent: true);
  }

  /// 日志上限，与 deploy/update.py 侧 UpdateProgress 的 200 行一致。
  static const int maxLogLines = 200;

  /// 更新日志（逐行流式追加）。
  final logs = <String>[].obs;

  /// idle / running / done / failed / rejected。
  final status = 'idle'.obs;

  /// 当前阶段名，由 `> 阶段名` 输出行解析而来。
  final step = ''.obs;

  UpdaterLauncher? _launcher;

  /// 是否有任意 OAS 仓库/Server 操作正在执行或排队。
  bool get isBusy => ServerOperationLock.instance.isBusy.value;

  /// 更新进程是否正在执行。
  bool get isRunning => status.value == 'running';

  /// OAS 安装根目录，校验失败返回 null。
  String? get rootPath => UpdaterLauncher.resolveRootPath(
      GetStorage().read('rootPathServer') as String?);

  /// 整页共享的 --info 结果，避免多个区块并发 fetch。
  Future<UpdateInfoModel>? _infoFuture;

  /// 读取仓库信息时也进入统一锁，避免与更新/写配置并发操作 Git。
  ///
  /// 取锁必须推迟到 build 之后：`ServerOperationLock.run` 会**同步**执行
  /// `isBusy.value = true`，而本 getter 被 `_RemoteSection.build`
  /// （lib/views/server/updater_panel.dart）在 build 期读取，写 Rx 会经
  /// `markNeedsBuild` 抛 `setState() or markNeedsBuild() called during build`。
  /// 用 Future.microtask 把入队推到当前同步帧结束之后，此时改 Rx 只是安排下一帧。
  Future<UpdateInfoModel> get infoFuture => _infoFuture ??=
      Future.microtask(() => ServerOperationLock.instance.run(_loadInfo));

  /// 丢弃已缓存的仓库信息。
  void invalidateInfo() {
    _infoFuture = null;
  }

  Future<UpdateInfoModel> _loadInfo() async {
    final root = rootPath;
    if (root == null) throw StateError('OAS root path invalid');
    final json = await UpdaterLauncher(rootPath: root).fetchInfo();
    if (json == null || json.containsKey('error')) {
      throw StateError(json?['error']?.toString() ?? 'update info unavailable');
    }
    return UpdateInfoModel.fromJson(json);
  }

  /// 写入 deploy.yaml；调用进入统一锁，避免与 fetch/update 并发。
  Future<Map<String, dynamic>?> saveConfig({
    String? repository,
    String? branch,
  }) {
    return ServerOperationLock.instance.run(() async {
      final root = rootPath;
      if (root == null) return {'error': 'OAS root path invalid'};
      final res = await UpdaterLauncher(rootPath: root)
          .saveConfig(repository: repository, branch: branch);
      if (res != null && !res.containsKey('error')) invalidateInfo();
      return res;
    });
  }

  /// 执行完整更新；更新、读取、保存和 Server 启动共享同一异步互斥。
  Future<bool> startUpdate() async {
    // 按钮层会同步禁用；这里再检查一次，防止非 UI 调用制造竞态。
    if (isRunning || isBusy) return false;
    final root = rootPath;
    if (root == null) {
      status.value = 'failed';
      logs.assignAll(['ERROR: OAS 根目录不合法，请先在本页设置根目录']);
      return false;
    }

    return ServerOperationLock.instance.run(() async {
      if (isRunning) return false;
      final launcher = UpdaterLauncher(rootPath: root);
      _launcher = launcher;
      status.value = 'running';
      step.value = '';
      logs.clear();

      await launcher.start(
        onLog: _consume,
        onDone: (result, exitCode) {
          status.value = (result?['status'] as String?) ??
              (exitCode == 0 ? 'done' : 'failed');
          step.value = (result?['step'] as String?) ?? step.value;
          _launcher = null;
          invalidateInfo();
        },
      );
      return true;
    });
  }

  /// 解析阶段行并保留最近日志。
  void _consume(String line) {
    logs.add(line);
    if (logs.length > maxLogLines) {
      logs.removeRange(0, logs.length - maxLogLines);
    }
    if (line.startsWith('> ')) step.value = line.substring(2);
  }

  /// 终止在途更新；具体状态由 launcher.start 收尾，避免空引用竞态。
  void kill() {
    _launcher?.kill();
  }

  @override
  void onClose() {
    _launcher?.kill();
    _launcher = null;
    super.onClose();
  }
}
