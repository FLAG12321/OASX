import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import 'package:oasx/api/update_info_model.dart';
import 'package:oasx/service/updater_launcher.dart';

/// 更新器状态控制器。
///
/// 为什么状态要提到 controller 而不是留在面板的 State 里：
/// ServerView 的 floatingActionButton 与折叠面板是两个互不相邻的 widget，
/// 但 FAB 需要在更新进行中禁用、面板需要显示同一份日志与阶段。
/// 私有 State 无法跨 widget 共享，因此统一由本控制器持有。
///
/// 以 permanent 方式注册：更新跑到一半切走页面再回来时日志与状态仍然保留，
/// 而 StatefulWidget 一旦 dispose 就全部丢失。
class UpdaterController extends GetxController {
  /// 取全局唯一实例，未注册时按需注册。
  ///
  /// 不放在路由 binding 里注册：更新器面板既嵌在 /server 页，也被 Home→Updater
  /// 页复用，而后者走 LayoutBinding。由使用方按需 ensure 才能两边都拿到同一实例。
  static UpdaterController ensure() {
    if (Get.isRegistered<UpdaterController>()) {
      return Get.find<UpdaterController>();
    }
    return Get.put<UpdaterController>(UpdaterController(), permanent: true);
  }

  /// 日志上限，与 deploy/update.py 侧 UpdateProgress 的 200 行一致，
  /// 避免长时间更新把内存吃满
  static const int maxLogLines = 200;

  /// 更新日志（逐行流式追加）
  final logs = <String>[].obs;

  /// idle / running / done / failed / rejected，语义与后端 UpdateProgress 一致
  final status = 'idle'.obs;

  /// 当前阶段名，由 `> 阶段名` 输出行解析而来
  final step = ''.obs;

  UpdaterLauncher? _launcher;

  /// 更新是否正在进行；FAB 与手动更新按钮据此禁用，避免并发跑 git 撞 .git/*.lock
  bool get isRunning => status.value == 'running';

  /// OAS 安装根目录，校验失败返回 null。
  ///
  /// 每次调用都重新读 GetStorage 而不是缓存：用户可能刚在本页改过根目录，
  /// 缓存会让更新器仍然指向旧路径。
  String? get rootPath =>
      UpdaterLauncher.resolveRootPath(GetStorage().read('rootPathServer') as String?);

  /// 整页共享的 `--info` 结果，避免配置表单与远程信息区各跑一次子进程
  /// 触发并发 git fetch 造成 ref 竞争
  Future<UpdateInfoModel>? _infoFuture;

  /// 取共享的仓库信息 future，首次调用时才真正 spawn 子进程
  Future<UpdateInfoModel> get infoFuture => _infoFuture ??= _loadInfo();

  /// 丢弃已缓存的仓库信息，下次读取会重新 spawn `--info`。
  /// 更新完成后调用，让 commit 表格反映新的 HEAD。
  void invalidateInfo() {
    _infoFuture = null;
  }

  /// 跑一次 `--info` 并转成前端模型。
  ///
  /// 复用 UpdateInfoModel：--info 输出的字段与 /home/update_info 逐字段一致，
  /// 所以解析逻辑（含 commit 四元组容错）完全共用，不做第二份实现。
  Future<UpdateInfoModel> _loadInfo() async {
    final root = rootPath;
    if (root == null) {
      throw StateError('OAS root path invalid');
    }
    final json = await UpdaterLauncher(rootPath: root).fetchInfo();
    if (json == null || json.containsKey('error')) {
      throw StateError(json?['error']?.toString() ?? 'update info unavailable');
    }
    return UpdateInfoModel.fromJson(json);
  }

  /// 写入 deploy.yaml 的 Repository / Branch，返回子进程的结果 Map。
  Future<Map<String, dynamic>?> saveConfig({
    String? repository,
    String? branch,
  }) async {
    final root = rootPath;
    if (root == null) {
      return {'error': 'OAS root path invalid'};
    }
    final res = await UpdaterLauncher(rootPath: root)
        .saveConfig(repository: repository, branch: branch);
    // 分支/仓库变了，缓存的 commit 对比已失效
    if (res != null && !res.containsKey('error')) {
      invalidateInfo();
    }
    return res;
  }

  /// 执行完整更新。spawn `python -m deploy.update` 并逐行收集输出。
  ///
  /// 返回 false 表示没能启动（已在跑，或根目录不合法）。
  Future<bool> startUpdate() async {
    if (isRunning) return false;
    final root = rootPath;
    if (root == null) {
      status.value = 'failed';
      logs.assignAll(['ERROR: OAS 根目录不合法，请先在本页设置根目录']);
      return false;
    }

    final launcher = UpdaterLauncher(rootPath: root);
    _launcher = launcher;
    status.value = 'running';
    step.value = '';
    logs.clear();

    await launcher.start(
      onLog: _consume,
      onDone: (result, exitCode) {
        // 优先用子进程给出的 status（done/failed/rejected 语义与后端一致），
        // 拿不到 JSON 结果行时退回按退出码判定
        status.value =
            (result?['status'] as String?) ?? (exitCode == 0 ? 'done' : 'failed');
        step.value = (result?['step'] as String?) ?? step.value;
        _launcher = null;
        // 代码已变，commit 表格需要重新拉
        invalidateInfo();
      },
    );
    return true;
  }

  /// 阶段标记由 deploy/update.py 以 `> 阶段名` 形式输出（UpdateProgress.set_step），
  /// 这里解析出来单独存一份供状态行显示，日志区仍保留原行。
  void _consume(String line) {
    logs.add(line);
    if (logs.length > maxLogLines) {
      logs.removeRange(0, logs.length - maxLogLines);
    }
    if (line.startsWith('> ')) {
      step.value = line.substring(2);
    }
  }

  /// 终止在途更新进程。
  ///
  /// execute_pull 全程幂等，中断后重新点更新会接上剩余阶段，所以强杀是安全的。
  void kill() {
    _launcher?.kill();
    _launcher = null;
    if (isRunning) {
      status.value = 'idle';
    }
  }

  @override
  void onClose() {
    // permanent 注册下正常不会走到这里；显式清理避免热重载等场景留下孤儿进程
    _launcher?.kill();
    _launcher = null;
    super.onClose();
  }
}
