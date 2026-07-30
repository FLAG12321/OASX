// lib/service/auto_boot_service.dart
import 'dart:async';

import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:oasx/api/api_client.dart';
import 'package:oasx/config/translation/i18n_content.dart';
import 'package:oasx/model/auto_script_entry.dart';
import 'package:oasx/model/const/storage_key.dart';
import 'package:oasx/service/script_service.dart';
import 'package:oasx/service/server_launcher.dart';
import 'package:oasx/utils/platform_utils.dart';

// 开机自启全自动流程编排者 + 自启脚本配置状态持有者。
// 所有平台注册（配置面板登录前即需数据源）；流程编排仅桌面且 --autostart 时执行，
// 见 spec docs/superpowers/specs/2026-07-30-auto-boot-design.md。
class AutoBootService extends GetxService {
  final _storage = GetStorage();

  // 自启脚本条目（勾选即存在条目），持久化于 StorageKey.autoScriptList
  final autoScriptEntries = <AutoScriptEntry>[].obs;

  // 从存储读取并迁移：解析出条目后按新格式写回（幂等）。
  // 首次运行（无存储值）与解析结果为空（无条目或脏数据）时都不写回：
  // 避免无意义的空数组落盘，也避免脏数据场景抹掉用户原始存储内容
  void loadEntries() {
    final raw = _storage.read(StorageKey.autoScriptList.name);
    autoScriptEntries.value = AutoScriptEntry.parseStored(raw);
    if (raw != null && autoScriptEntries.isNotEmpty) _persist();
  }

  // 按新格式（对象数组 JSON 字符串）写入存储
  void _persist() {
    _storage.write(StorageKey.autoScriptList.name,
        AutoScriptEntry.encodeList(autoScriptEntries.toList()));
  }

  bool isSelected(String name) =>
      autoScriptEntries.any((e) => e.name == name);

  // 未勾选返回 0
  int delayOf(String name) =>
      autoScriptEntries.firstWhereOrNull((e) => e.name == name)?.delaySeconds ??
      0;

  // 勾选/取消勾选；勾选新增延时 0 的条目，保持按名称稳定排序
  void setSelected(String name, bool selected) {
    if (selected) {
      if (!isSelected(name)) {
        autoScriptEntries.add(AutoScriptEntry(name, 0));
        autoScriptEntries.sort((a, b) => a.name.compareTo(b.name));
      }
    } else {
      autoScriptEntries.removeWhere((e) => e.name == name);
    }
    _persist();
  }

  // 修改延时（条目不存在则忽略；越界由 AutoScriptEntry 构造钳制）
  void setDelay(String name, int seconds) {
    final index = autoScriptEntries.indexWhere((e) => e.name == name);
    if (index < 0) return;
    autoScriptEntries[index] = AutoScriptEntry(name, seconds);
    _persist();
  }

  // 脚本被删除时同步移除自启条目（由 ScriptService.deleteScriptModel 调用）
  void removeEntry(String name) {
    final before = autoScriptEntries.length;
    autoScriptEntries.removeWhere((e) => e.name == name);
    if (autoScriptEntries.length != before) _persist();
  }

  // ScriptService 完成脚本连接后的回调；仅 scheduling 态才执行延时调度，
  // 手动登录（流程未激活）时为 no-op —— 手动登录不再自动启动脚本。
  // 若回调早于流程置 scheduling（用户在轮询窗口内手动登录），先记标记，
  // 由 start() 步骤 4 补触发，避免回调丢失导致脚本永不启动
  void onScriptServiceReady() {
    _scriptServiceReady = true;
    if (_flowState != _stateScheduling || _readyAt == null) return;
    _flowState = _stateDone;
    _scheduleAutoRun(_readyAt!);
  }

  // ScriptService 是否已完成脚本连接（回调早到时的补偿标记）
  bool _scriptServiceReady = false;

  // ---------------- 自动流程编排（spec §4.2） ----------------

  // 流程状态：idle 未触发；running（拉起/等就绪/登录）→ scheduling（等
  // ScriptService 回调）→ done；failed 为终态
  static const _stateIdle = 'idle';
  static const _stateRunning = 'running';
  static const _stateScheduling = 'scheduling';
  static const _stateDone = 'done';
  static const _stateFailed = 'failed';
  String _flowState = _stateIdle;

  // 是否携带 --autostart 启动参数（main() 注入，须在首帧前就位）
  bool hasAutostartArg = false;

  // 自动流程是否已推进（调试观测用；LoginController 的让位判断用静态触发
  // 条件而非本状态，避免首帧前后的时序竞态）
  bool get flowActive =>
      _flowState != _stateIdle && _flowState != _stateFailed;

  // 后端就绪时刻 T0（延时计时起点）
  DateTime? _readyAt;

  // 延时启动 Timer 统一持有，onClose/killServer 时取消
  final List<Timer> _pendingTimers = [];
  Timer? _sampleTimer;

  // 自动流程持有的拉起器，服务销毁时释放（在途命令 + 日志流）
  ServerLauncher? _launcher;

  // 就绪轮询参数（spec：2s 间隔、5 分钟超时）
  static const _pollInterval = Duration(seconds: 2);
  static const _pollTimeout = Duration(minutes: 5);

  // 地址取值规则（spec §3）：优先已保存登录地址，无则默认
  String resolveAddress() {
    final saved = _storage.read(StorageKey.address.name);
    if (saved is String && saved.trim().isNotEmpty) return saved.trim();
    return '127.0.0.1:22288';
  }

  // 入口：满足触发条件才推进（幂等，重复调用直接返回）
  Future<void> start() async {
    if (_flowState != _stateIdle) return;
    if (!shouldAutoBoot(
        hasAutostartArg: hasAutostartArg,
        isDesktop: PlatformUtils.isDesktop,
        entryCount: autoScriptEntries.length)) {
      return;
    }
    _flowState = _stateRunning;
    try {
      ApiClient().setAddress('http://${resolveAddress()}');
      // 1. 先探测：server 可能已在运行（如上次会话未关闭）。
      //    用静默探测，避免冷启动必然失败时刷屏网络错误 snackbar
      var ready = await ApiClient().testAddressSilent();
      if (!ready) {
        // 2. 仅 Windows 自动拉起 server；mac/Linux 降级为只探测（spec §3）
        if (GetPlatform.isWindows) {
          final rootPath =
              (_storage.read('rootPathServer') as String?) ?? '';
          if (!ServerLauncher.validatePath(rootPath)) {
            _fail('OAS root path invalid, skip auto boot');
            return;
          }
          // printInfo 是 GetX 命名参数扩展，需包一层适配 onLog 的位置参数签名；
          // 实例由字段持有，便于服务销毁时释放在途命令与日志流
          _launcher = ServerLauncher(
              rootPath: rootPath,
              onLog: (line) => printInfo(info: 'AutoBoot: $line'));
          await _launcher!.launch();
        }
        // 3. 轮询就绪（2s 间隔、5 分钟超时）
        ready = await _pollUntilReady();
      }
      if (!ready) {
        _fail('server not ready in ${_pollTimeout.inMinutes} minutes');
        return;
      }
      // 4. 首次可达时刻记为 T0；跳转主界面（地址已 set、可达已确认，
      //    与 LoginController.login 成功路径等效）
      _readyAt = DateTime.now();
      _flowState = _stateScheduling;
      if (Get.currentRoute != '/main') {
        Get.offAllNamed('/main');
      }
      // 5. 正常路径等 ScriptService 连接完成回调 onScriptServiceReady 触发调度；
      //    若回调已先到达（用户在轮询期间手动登录），此处补触发一次
      if (_scriptServiceReady && Get.isRegistered<ScriptService>()) {
        _flowState = _stateDone;
        _scheduleAutoRun(_readyAt!);
      }
    } catch (e) {
      _fail('auto boot failed: $e');
    }
  }

  Future<bool> _pollUntilReady() async {
    final deadline = DateTime.now().add(_pollTimeout);
    while (DateTime.now().isBefore(deadline)) {
      // 静默探测：轮询期间每次失败都弹 snackbar 会持续刷屏（最长 5 分钟约 150 次）
      if (await ApiClient().testAddressSilent()) return true;
      await Future.delayed(_pollInterval);
    }
    return false;
  }

  void _fail(String reason) {
    _flowState = _stateFailed;
    printError(info: 'AutoBoot: $reason');
    Get.snackbar('AutoBoot', reason);
  }

  // 按各脚本延时（相对 T0 补偿）设 Timer 依次启动（spec §4.2 步骤 6）
  void _scheduleAutoRun(DateTime t0) {
    // ScriptService 可能已被 killServer 注销（在途 onInit 仍会回调），此时放弃调度
    if (!Get.isRegistered<ScriptService>()) {
      printError(info: 'AutoBoot: ScriptService not registered, skip schedule');
      return;
    }
    final scriptService = Get.find<ScriptService>();
    final entries = autoScriptEntries.toList();
    if (entries.isEmpty) return;
    var maxDelay = Duration.zero;
    for (final entry in entries) {
      final delay = remainingDelay(entry.delaySeconds, t0, DateTime.now());
      if (delay > maxDelay) maxDelay = delay;
      _pendingTimers.add(Timer(delay, () {
        // 已运行的跳过；后端侧已删除（不在 scriptModelMap）的跳过并记日志
        if (!scriptService.scriptModelMap.containsKey(entry.name)) {
          printError(info: 'AutoBoot: ${entry.name} not found, skip');
          return;
        }
        if (scriptService.isRunning(entry.name)) return;
        scriptService.startScript(entry.name).catchError((e) {
          // 到点时 server 不可用：记日志 + 提示，跳过不重试（spec §5）
          printError(info: 'AutoBoot: start ${entry.name} failed: $e');
          Get.snackbar(I18n.autoRunScript.tr, '${entry.name} failed');
        });
      }));
    }
    // 最晚一个脚本到点后再延迟采样运行状态，成功才提示（沿用原 autoRunScript 语义）
    _sampleTimer = Timer(maxDelay + const Duration(seconds: 4), () {
      final ok = entries
          .map((e) => e.name)
          .where(scriptService.isRunning)
          .toList();
      if (ok.isNotEmpty) {
        Get.snackbar(I18n.autoRunScript.tr, '$ok ${I18n.startSuccess.tr}');
      }
    });
  }

  // 取消全部未触发的延时启动（killServer / 服务销毁时调用，spec §5）
  void cancelScheduled() {
    for (final t in _pendingTimers) {
      t.cancel();
    }
    _pendingTimers.clear();
    _sampleTimer?.cancel();
    _sampleTimer = null;
  }

  @override
  void onClose() {
    cancelScheduled();
    // 释放拉起器（在途 shell 命令 + 日志流监听）
    _launcher?.dispose();
    _launcher = null;
    super.onClose();
  }

  // 触发条件：--autostart 参数 && 桌面平台 && 自启条目非空（spec §3）
  static bool shouldAutoBoot(
      {required bool hasAutostartArg,
      required bool isDesktop,
      required int entryCount}) {
    return hasAutostartArg && isDesktop && entryCount > 0;
  }

  // 剩余延时 = max(0, delaySeconds - (now - T0))，T0 为后端就绪时刻
  static Duration remainingDelay(int delaySeconds, DateTime t0, DateTime now) {
    final remain = Duration(seconds: delaySeconds) - now.difference(t0);
    return remain.isNegative ? Duration.zero : remain;
  }
}
