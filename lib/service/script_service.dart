import 'dart:async';
import 'dart:convert';

import 'package:get/get.dart';
import 'package:oasx/api/api_client.dart';
import 'package:oasx/model/script_model.dart';
import 'package:oasx/service/auto_boot_service.dart';
import 'package:oasx/service/websocket_service.dart';
import 'package:oasx/views/overview/overview_view.dart';

class ScriptService extends GetxService {
  final wsService = Get.find<WebSocketService>();
  final scriptModelMap = <String, ScriptModel>{}.obs;

  // 判断脚本是否处于运行态，用于自动流程跳过已运行脚本与启动成功采样。
  // 必须严格等于 running：starting/stopping 是前端伪状态，把 starting 算作已运行
  // 会让 AutoBootService 的启动结果采样在启动尚未确认时就报成功。
  bool isRunning(String name) {
    final model = scriptModelMap[name];
    return model != null && model.state.value == ScriptState.running;
  }

  @override
  Future<void> onInit() async {
    final scriptList = await ApiClient().getScriptList();
    if (scriptList.isNotEmpty) {
      await Future.wait(scriptList.map((name) => connectScript(name)));
    }
    super.onInit();
    // 脚本连接完成后通知自动流程编排者（非自动流程时该回调为 no-op）；
    // 自动启动脚本的触发与延时调度全部由 AutoBootService 负责
    if (Get.isRegistered<AutoBootService>()) {
      Get.find<AutoBootService>().onScriptServiceReady();
    }
  }

  @override
  Future<void> onClose() async {
    await Future.wait([
      ...scriptModelMap.keys.map((e) => Future.wait([
            stopScript(e),
            wsService.close(e),
            Get.delete<OverviewController>(tag: e, force: true)
          ])),
    ]);
    scriptModelMap.clear();
    super.onClose();
  }

  Future<void> connectScript(String name) async {
    if (!scriptModelMap.containsKey(name)) {
      addScriptModel(name);
    }
    wsService.removeAllListeners(name);
    await wsService.connect(name: name, listener: (mg) => wsListener(mg, name));
    // 主动请求一次调度数据：不依赖 WS 连接时的首帧推送，避免任务列表
    // 因首帧推送丢失/后端调度器尚未就绪而一直为空。
    await wsService.send(name, 'get_schedule');
  }

  /// 启动脚本。分三段：置「启动中」伪状态 → 等 HTTP 启停接口落定 → 落定终态。
  ///
  /// 后端 `GET /{name}/start` 在子进程 generation 握手完成后才返回（最长约 5s），
  /// 且只在确实启动成功时返回 200，因此 await 落地即可直接落定 running，
  /// 不必靠超时猜测。原实现走 WS 单向 'start'，既无结束信号也无失败通路。
  Future<void> startScript(String name) async {
    await connectScript(name);
    final model = scriptModelMap[name];
    model?.update(state: ScriptState.starting);
    final result = await _guardedAction(
        () => ApiClient().startScript(name), name, ScriptState.inactive);
    if (result == null) return;
    if (!result.ok) {
      // 启动失败回落到点击前的状态；错误提示已由 ApiClient 按状态码弹出。
      // 只在仍停留在伪状态时回落，避免覆盖 await 期间已到达的后端 state 帧。
      _resetIfBusy(name, ScriptState.inactive);
      return;
    }
    _resetIfBusy(name, ScriptState.running);
    // 与后端对齐一次：若后端已推送 state 帧，值相同不会造成闪烁
    await wsService.send(name, 'get_state');
  }

  void wsListener(dynamic message, String name) {
    if (message is! String) {
      printError(info: 'Websocket push data is not of type string and map');
      return;
    }
    if (!message.startsWith('{') || !message.endsWith('}')) {
      if (Get.isRegistered<OverviewController>(tag: name)) {
        Get.find<OverviewController>(tag: name).addLog(message);
      }
      return;
    }
    Map<String, dynamic> data = jsonDecode(message);
    if (data.containsKey('state')) {
      scriptModelMap[name]!.update(state: ScriptState.getState(data['state']));
      return;
    }
    if (data.containsKey('schedule')) {
      Map run = data['schedule']['running'];
      List<dynamic> pending = data['schedule']['pending'];
      List<dynamic> waiting = data['schedule']['waiting'];
      TaskItemModel runningTask = run.isNotEmpty
          ? TaskItemModel(run['name'], run['next_run'])
          : TaskItemModel.empty();
      final pendingList =
          pending.map((e) => TaskItemModel(e['name'], e['next_run'])).toList();
      final waitingList =
          waiting.map((e) => TaskItemModel(e['name'], e['next_run'])).toList();
      scriptModelMap[name]!.update(
          runningTask: runningTask,
          pendingTaskList: pendingList,
          waitingTaskList: waitingList);
    }
  }

  /// 停止脚本。与 [startScript] 对称：后端在 `script_process.stop()` 完成后才返回。
  Future<void> stopScript(String name) async {
    if (!scriptModelMap.containsKey(name)) return;
    scriptModelMap[name]?.update(state: ScriptState.stopping);
    final result = await _guardedAction(
        () => ApiClient().stopScript(name), name, ScriptState.running);
    if (result == null) return;
    _resetIfBusy(name, result.ok ? ScriptState.inactive : ScriptState.running);
  }

  /// 给启停请求套一层超时兜底。dio 只设了 connectTimeout，没有 receiveTimeout，
  /// 后端 hang 住时 await 可能永不返回，UI 会永久卡在转圈。超时后回落到
  /// [fallback]（点击前的状态）并主动 get_state，让后端帧来纠正。
  /// 返回 null 表示已由兜底处理，调用方不要再落定终态。
  Future<ScriptActionResult?> _guardedAction(
    Future<ScriptActionResult> Function() action,
    String name,
    ScriptState fallback,
  ) async {
    try {
      // 12s = 后端握手上限 5s 的两倍余量，够慢速环境跑完又不会让用户干等
      return await action().timeout(const Duration(seconds: 12));
    } on TimeoutException {
      printError(info: 'script[$name] action timeout, fallback to $fallback');
      _resetIfBusy(name, fallback);
      await wsService.send(name, 'get_state');
      return null;
    }
  }

  /// 仅当仍处于伪状态时改写为 [state]。await 期间后端可能已推送真实 state 帧，
  /// 那一帧才是权威值，不能被中间态的收尾逻辑覆盖回去。
  void _resetIfBusy(String name, ScriptState state) {
    final model = scriptModelMap[name];
    if (model == null || !model.isBusy) return;
    model.update(state: state);
  }

  void addScriptModel(dynamic sm) {
    if (sm is String) {
      sm = ScriptModel(sm);
    }
    if (scriptModelMap.containsKey(sm.name)) return;
    scriptModelMap[sm.name] = sm;
  }

  /// 确保脚本模型存在并返回；不存在时创建。
  /// Overview 打开时模型可能因启动时序尚未由 onInit 创建，直接 `!` 会抛空指针，
  /// 这里改为按需创建，保证任务列表页不会因模型缺失而整体渲染失败。
  ScriptModel ensureScriptModel(String name) {
    addScriptModel(name);
    return scriptModelMap[name]!;
  }

  void updateScriptModel(ScriptModel sm) {
    if (!scriptModelMap.containsKey(sm.name)) return;
    scriptModelMap[sm.name] = sm;
  }

  void addOrUpdateScriptModel(ScriptModel sm) {
    if (scriptModelMap.containsKey(sm.name)) {
      updateScriptModel(sm);
    } else {
      addScriptModel(sm);
    }
  }

  void deleteScriptModel(String name) {
    if (!scriptModelMap.containsKey(name)) return;
    scriptModelMap.remove(name);
    wsService.close(name);
    // 同步移除自启条目（覆盖真实删除场景；重命名场景由 renameConfig 单独迁移）
    if (Get.isRegistered<AutoBootService>()) {
      Get.find<AutoBootService>().removeEntry(name);
    }
  }

  ScriptModel? findScriptModel(String name) {
    return scriptModelMap[name];
  }
}
