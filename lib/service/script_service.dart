import 'dart:convert';

import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:oasx/api/api_client.dart';
import 'package:oasx/model/const/storage_key.dart';
import 'package:oasx/model/script_model.dart';
import 'package:oasx/service/websocket_service.dart';
import 'package:oasx/views/overview/overview_view.dart';

class ScriptService extends GetxService {
  final _storage = GetStorage();
  final wsService = Get.find<WebSocketService>();
  final scriptModelMap = <String, ScriptModel>{}.obs;

  // 自动启动脚本列表（持久化脚本名，应用启动后自动运行）
  final autoScriptList = <String>[].obs;

  // 从本地存储恢复自动启动脚本列表，兼容历史 List 直存与 JSON 字符串两种格式
  void _loadAutoScriptListFromStorage() {
    final raw = _storage.read(StorageKey.autoScriptList.name);
    if (raw is List) {
      autoScriptList.value = raw.map((e) => e.toString()).toList();
      return;
    }
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          autoScriptList.value = decoded.map((e) => e.toString()).toList();
          return;
        }
      } catch (_) {}
    }
    autoScriptList.clear();
  }

  // 写入自动启动脚本列表（JSON 数组形式持久化）
  void _persistAutoScriptList() {
    _storage.write(
        StorageKey.autoScriptList.name, jsonEncode(autoScriptList.toList()));
  }

  // 判断脚本是否处于运行态，用于跳过已运行脚本与延迟采样成功判断
  bool isRunning(String name) {
    final model = scriptModelMap[name];
    return model != null && model.state.value == ScriptState.running;
  }

  // 增删自动启动脚本并持久化，保持列表稳定排序
  void updateAutoScript(String script, bool selected) {
    if (selected) {
      if (!autoScriptList.contains(script)) autoScriptList.add(script);
    } else {
      autoScriptList.remove(script);
    }
    autoScriptList.sort();
    _persistAutoScriptList();
  }

  @override
  Future<void> onInit() async {
    _loadAutoScriptListFromStorage(); // 新增：先恢复列表
    final scriptList = await ApiClient().getScriptList();
    if (scriptList.isNotEmpty) {
      await Future.wait(scriptList.map((name) => connectScript(name)));
    }
    super.onInit();
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
  }

  Future<void> startScript(String name) async {
    await connectScript(name);
    await wsService.send(name, 'start');
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

  Future<void> stopScript(String name) async {
    if (!scriptModelMap.containsKey(name)) return;
    await wsService.send(name, 'stop');
  }

  void addScriptModel(dynamic sm) {
    if (sm is String) {
      sm = ScriptModel(sm);
    }
    if (scriptModelMap.containsKey(sm.name)) return;
    scriptModelMap[sm.name] = sm;
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
    // 同步移除自启标记（覆盖真实删除场景；重命名场景由 renameConfig 单独迁移）
    if (autoScriptList.remove(name)) {
      _persistAutoScriptList();
    }
  }

  ScriptModel? findScriptModel(String name) {
    return scriptModelMap[name];
  }
}
