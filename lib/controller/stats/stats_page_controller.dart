import 'package:get/get.dart';
import 'package:oasx/api/api_client.dart';
import 'package:oasx/model/stats/script_statistics_models.dart';

/// Stats 首页编排层，负责日期列表、快照加载与派生状态。
class StatsPageController extends GetxController {
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

  /// 最近一次错误消息。
  final lastErrorMessage = ''.obs;

  /// 最近更新时间标签。
  final lastUpdatedLabel = ''.obs;

  String _scriptName = '';

  /// 是否允许进入多账号统计页。
  bool get hasMultiAccountEntry {
    final multi = statistics.value?.multi;
    return multi != null && multi.accounts.isNotEmpty;
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
      final dates = await ApiClient().getScriptStatisticsDates(_scriptName);
      final orderedDates = [...dates]..sort((left, right) => right.compareTo(left));
      availableDateKeys.assignAll(orderedDates);
      if (orderedDates.isNotEmpty) {
        await selectDate(orderedDates.first);
      }
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

    selectedDateKey.value = dateKey;
    statisticsLoading.value = true;
    lastErrorMessage.value = '';
    try {
      final raw = await ApiClient().getScriptStatisticsDayRaw(_scriptName, dateKey);
      statistics.value = ScriptStatisticsDay.fromSnapshotJson(raw, dateKey: dateKey);
      lastUpdatedLabel.value = dateKey;
    } catch (error) {
      lastErrorMessage.value = error.toString();
    } finally {
      statisticsLoading.value = false;
    }
  }

  /// 刷新当前日期对应的快照。
  Future<void> refreshCurrentDate() async {
    if (selectedDateKey.value.isEmpty) {
      return;
    }
    await selectDate(selectedDateKey.value);
  }
}
