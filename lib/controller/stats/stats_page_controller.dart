import 'dart:async';

import 'package:get/get.dart';
import 'package:oasx/api/api_client.dart';
import 'package:oasx/model/stats/script_statistics_models.dart';

/// 统计日期列表加载函数，便于测试中注入假数据。
typedef StatsDatesLoader = Future<List<String>> Function(String scriptName);

/// 统计日快照加载函数，便于测试中注入假数据。
typedef StatsDayLoader = Future<Map<String, dynamic>> Function(
  String scriptName,
  String dateKey,
);

/// Stats 首页编排层，负责日期列表、快照加载与派生状态。
class StatsPageController extends GetxController {
  StatsPageController({
    StatsDatesLoader? loadDates,
    StatsDayLoader? loadDay,
    Duration? autoRefreshInterval,
  }) : _loadDates = loadDates ?? ApiClient().getScriptStatisticsDates,
       _loadDay = loadDay ?? ApiClient().getScriptStatisticsDayRaw,
       _autoRefreshInterval = autoRefreshInterval ?? const Duration(seconds: 2);

  /// 可选日期列表。
  final availableDateKeys = <String>[].obs;

  /// 当前选中的统计快照。
  final statistics = Rxn<ScriptStatisticsDay>();

  /// 当前选中的日期 key。
  final selectedDateKey = ''.obs;

  /// 日期列表加载中。
  final datesLoading = false.obs;

  /// 统计快照加载中。
  final statisticsLoading = false.obs;

  /// 是否展示阻断式加载占位。
  final statisticsBlockingLoading = false.obs;

  /// 最近一次错误消息。
  final lastErrorMessage = ''.obs;

  /// 最近更新时间标签。
  final lastUpdatedLabel = ''.obs;

  /// 日期列表加载器。
  final StatsDatesLoader _loadDates;

  /// 单日快照加载器。
  final StatsDayLoader _loadDay;

  /// 自动刷新间隔。
  final Duration _autoRefreshInterval;

  /// 自动刷新定时器。
  Timer? _autoRefreshTimer;

  /// 当前页面是否允许自动刷新。
  bool _autoRefreshEnabled = false;

  /// 当前脚本名。
  String _scriptName = '';

  /// 是否允许进入多账号统计页。
  bool get hasMultiAccountEntry {
    final multi = statistics.value?.multi;
    return multi != null && multi.accounts.isNotEmpty;
  }

  @override
  void onClose() {
    // 中文注释：controller 销毁时必须停止后台轮询，避免页面离开后继续请求。
    stopAutoRefresh();
    super.onClose();
  }

  /// 启动 controller：加载日期列表并默认选中最新日期。
  Future<void> bootstrap(String scriptName) async {
    _scriptName = scriptName.trim();
    if (_scriptName.isEmpty) {
      return;
    }

    datesLoading.value = true;
    lastErrorMessage.value = '';
    try {
      final dates = await _loadDates(_scriptName);
      final orderedDates = [...dates]..sort((left, right) => right.compareTo(left));
      availableDateKeys.assignAll(orderedDates);
      if (orderedDates.isEmpty) {
        selectedDateKey.value = '';
        statistics.value = null;
        lastUpdatedLabel.value = '';
        stopAutoRefresh();
        return;
      }
      await _loadDateSnapshot(orderedDates.first, showBlockingLoading: true);
      _syncAutoRefreshTimer();
    } catch (error) {
      lastErrorMessage.value = error.toString();
    } finally {
      datesLoading.value = false;
    }
  }

  /// 切换当前选中日期并重新加载该日快照。
  Future<void> selectDate(String dateKey) async {
    if (dateKey.trim().isEmpty || _scriptName.isEmpty) {
      return;
    }
    await _loadDateSnapshot(dateKey, showBlockingLoading: true);
    _syncAutoRefreshTimer();
  }

  /// 刷新当前日期对应的快照。
  Future<void> refreshCurrentDate({bool showBlockingLoading = false}) async {
    if (selectedDateKey.value.isEmpty) {
      return;
    }
    await _loadDateSnapshot(
      selectedDateKey.value,
      showBlockingLoading: showBlockingLoading,
    );
  }

  /// 开启当前页自动刷新。
  void startAutoRefresh() {
    _autoRefreshEnabled = true;
    _syncAutoRefreshTimer();
  }

  /// 停止当前页自动刷新。
  void stopAutoRefresh() {
    _autoRefreshEnabled = false;
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
  }

  /// 统一加载某一天快照，并按场景决定是否显示整页加载态。
  Future<void> _loadDateSnapshot(
    String dateKey, {
    required bool showBlockingLoading,
  }) async {
    if (dateKey.trim().isEmpty || _scriptName.isEmpty) {
      return;
    }

    selectedDateKey.value = dateKey;
    statisticsLoading.value = true;
    statisticsBlockingLoading.value = showBlockingLoading;
    lastErrorMessage.value = '';
    try {
      final raw = await _loadDay(_scriptName, dateKey);
      statistics.value = ScriptStatisticsDay.fromSnapshotJson(raw, dateKey: dateKey);
      lastUpdatedLabel.value = dateKey;
    } catch (error) {
      lastErrorMessage.value = error.toString();
    } finally {
      statisticsLoading.value = false;
      statisticsBlockingLoading.value = false;
    }
  }

  /// 按当前页面状态同步自动刷新定时器。
  void _syncAutoRefreshTimer() {
    final canAutoRefresh = _autoRefreshEnabled && selectedDateKey.value.isNotEmpty;
    if (!canAutoRefresh) {
      _autoRefreshTimer?.cancel();
      _autoRefreshTimer = null;
      return;
    }
    _autoRefreshTimer ??= Timer.periodic(_autoRefreshInterval, (_) {
      if (statisticsLoading.value) {
        return;
      }
      // 中文注释：后台刷新只更新数据，不再把整页切回“正在加载”占位。
      unawaited(refreshCurrentDate());
    });
  }
}
