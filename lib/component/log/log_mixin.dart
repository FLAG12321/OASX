import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:oasx/component/log/log_line_width.dart';
import 'package:oasx/config/translation/i18n_content.dart';

mixin LogMixin on GetxController {
  /// max lines to store in log
  int get maxLines => 200;

  /// max logs+pending
  int get maxBuffer => 1000;

  /// max burst line when refreshing
  int get maxBurst => 50;

  /// min burst line when refreshing
  int get minBurst => 1;

  /// ui log
  final logs = <String>[].obs;

  /// auto scroll to bottom
  final autoScroll = true.obs;

  /// collapse log content
  final collapseLog = false.obs;

  /// 历史日志加载中；由支持历史加载的子类维护，UI 据此显示加载占位动画。
  /// 置位与复位（含失败路径的 finally）都由子类负责，基类不自动复位。
  final historyLoading = false.obs;

  /// logs buffer, used to limit speeded log refresh
  final _pendingLogs = <String>[];

  /// refresh timer for log
  Timer? _refreshTimer;

  double _savedScrollOffset = 0.0;

  void Function({bool isJump, bool force, int scrollOffset})? scrollLogs;

  /// 头部行数变化后由 LogWidget 保持当前阅读视口；
  /// 参数为头部变化行数（prepend 为正、移除残留历史为负）。
  void Function(int changedCount)? preserveViewportAfterPrepend;

  /// UI 日志从头部被截断后的通知钩子；默认空实现，由子类修复历史连续性。
  void onUiLogsTrimmedFromHead(int removedCount) {}

  /// 是否允许继续加载更早历史日志；默认不支持，由子类覆写。
  bool get canLoadOlderLogs => false;

  /// 接近顶部时触发的历史日志加载钩子；默认空实现。
  Future<void> loadOlderLogs() async {}

  /// 当前 UI 与 pending 中是否已经包含该日志文本。
  bool containsVisibleOrPendingLog(String log) {
    return logs.contains(log) || _pendingLogs.contains(log);
  }

  @override
  void onInit() {
    _refreshTimer ??= Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (_pendingLogs.isEmpty) {
        return;
      }
      _clearOverflowLogs();
      _updateUILogs();
      _removeUIOldLogs();
      scrollLogs?.call();
    });
    super.onInit();
  }

  @override
  void onClose() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    super.onClose();
  }

  void _removeUIOldLogs() {
    // 非自动滚动状态下,且未溢出(已删除溢出部分),则不删除旧日志,使用户可以停留
    if (!autoScroll.value) return;
    // UI 限制：只保留最新 maxLines 行
    if (logs.length > maxLines) {
      final removed = logs.length - maxLines;
      logs.removeRange(0, removed);
      // 中文注释：头部被截断会破坏已加载历史的连续性，通知子类修复。
      onUiLogsTrimmedFromHead(removed);
    }
  }

  void _updateUILogs() {
    // 根据 backlog 动态调整本次要处理多少条
    int backlog = _pendingLogs.length;
    int burst = backlog.clamp(minBurst, maxBurst);
    for (int i = 0; i < burst && _pendingLogs.isNotEmpty; i++) {
      logs.add(_pendingLogs.removeAt(0));
    }
  }

  void _clearOverflowLogs() {
    // 计算总大小
    int totalSize = logs.length + _pendingLogs.length;
    if (totalSize > maxBuffer) {
      int overflow = totalSize - maxBuffer;
      // 优先删除 logs 里最老的
      if (overflow > 0) {
        int removeFromLogs = min(overflow, logs.length);
        if (removeFromLogs > 0) {
          logs.removeRange(0, removeFromLogs);
          overflow -= removeFromLogs;
          // 中文注释：头部被截断会破坏已加载历史的连续性，通知子类修复。
          onUiLogsTrimmedFromHead(removeFromLogs);
        }
      }
      // 如果还不够，就从 pending 里删除最老的
      if (overflow > 0 && _pendingLogs.isNotEmpty) {
        int removeFromPending = min(overflow, _pendingLogs.length);
        _pendingLogs.removeRange(0, removeFromPending);
      }
    }
  }

  /// 入库前先做行宽归一：一个载荷可能含多行（后端 rich 已按 80 列折过并用
  /// `\n` 拼在一起），也可能是完全没折过的子进程 stdout。归一后每个元素恰好
  /// 是一行、且不超过分隔线宽度，满足渲染侧「一元素一行」的不变式
  /// （`prototypeItem` + `maxLines: 1`，详见 log_line_width.dart）。
  ///
  /// 因此本方法可能往 pending 里放入多条：maxLines / maxBuffer 的上限随之
  /// 按真实行数计（原先一条 30 行的 traceback 只占 1 个名额），这正是这两个
  /// 上限本来的语义。
  void addLog(String log) {
    _pendingLogs.addAll(normalizeLogLines(log));
  }

  void clearLog() {
    logs.clear();
    _pendingLogs.clear();
  }

  void copyLogs() {
    final allLogs = logs.join("");
    Clipboard.setData(ClipboardData(text: allLogs));
    Get.snackbar(I18n.tip.tr, I18n.copy_success.tr,
        duration: const Duration(seconds: 1));
  }

  void toggleAutoScroll() {
    autoScroll.value = !autoScroll.value;
    if (autoScroll.value) {
      scrollLogs?.call(force: true, scrollOffset: -1);
    }
  }

  void toggleCollapse() => collapseLog.value = !collapseLog.value;

  double get savedScrollOffsetVal => _savedScrollOffset;
  void saveScrollOffset(double offset) {
    _savedScrollOffset = offset;
  }
}
