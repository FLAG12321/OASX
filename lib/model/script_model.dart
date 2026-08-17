import 'package:get/get.dart';
import 'package:oasx/views/overview/overview_view.dart';

enum ScriptState {
  inactive,
  running,
  warning,
  updating,
  // 以下两个是「前端伪状态」：只由 ScriptService 在等待后端启停响应期间置位。
  // 后端 state 帧永远不会映射到它们（见 getState），因此不改动任何后端契约。
  starting,
  stopping,
  ;

  /// 是否处于等待后端响应的中间态。UI 据此禁用按钮并显示过渡动画；
  /// 判断运行态的地方必须用 `== running` 而不是「非 inactive」，
  /// 否则 starting 会被误当成已运行（AutoBootService 的启动成功采样依赖这一点）。
  bool get isBusy => this == starting || this == stopping;

  static ScriptState getState(dynamic value){
    return switch (value) {
      0 => inactive,
      1 => running,
      2 => warning,
      3 => updating,
      _ => inactive,
    };
  }
}

class ScriptModel {
  String name;
  final state = ScriptState.updating.obs;
  final runningTask = const TaskItemModel('', '').obs;
  final pendingTaskList = <TaskItemModel>[].obs;
  final waitingTaskList = <TaskItemModel>[].obs;

  ScriptModel(this.name);

  /// 是否处于启停中间态，转发到状态枚举，便于 UI 与服务层直接读取
  bool get isBusy => state.value.isBusy;

  void update(
      {ScriptState? state,
      TaskItemModel? runningTask,
      List<TaskItemModel>? pendingTaskList,
      List<TaskItemModel>? waitingTaskList}) {
    if (state != null && this.state.value != state) this.state.value = state;
    if (runningTask != null && this.runningTask.value != runningTask) {
      this.runningTask.value = runningTask;
    }
    if (pendingTaskList != null) this.pendingTaskList.value = pendingTaskList;
    if (waitingTaskList != null) this.waitingTaskList.value = waitingTaskList;
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'state': state.toJson(),
        'runningTask': runningTask.toJson(),
        'pendingTaskList': pendingTaskList.toJson(),
        'waitingTaskList': waitingTaskList.toJson()
      };
}
