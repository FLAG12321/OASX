import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show kIsWeb;

/// 多号账号显示名组合规则。
enum MultiAccountLabelStyle {
  /// 仅角色名。
  char,

  /// 角色 + 区服。
  charSvr,

  /// 角色 + 账号。
  charAcc,

  /// 角色 + 账号 + 区服。
  charAccSvr,
}

/// 统计面板连接状态。
enum ScriptStatisticsConnectionState {
  idle,
  connecting,
  connected,
  reconnecting,
  error,
}

/// 统计图支持的指标。
enum ScriptStatisticsChartMetric {
  totalDuration,
  runCount,
  battleCount,
  battleAvgDuration,
  avgRunDuration,
}

/// 统计图支持的排序字段。
enum ScriptStatisticsChartSortField { data, time }

/// 日期列表响应。
class ScriptStatisticsDateList {
  /// 创建日期列表模型。
  ScriptStatisticsDateList({required this.scriptName, required this.dates});

  /// 从服务端 JSON 构建日期列表模型。
  factory ScriptStatisticsDateList.fromJson(Map<String, dynamic> json) {
    final rawDates = json['dates'];
    final dates = rawDates is List
        ? rawDates
              .map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty)
              .toList()
        : <String>[];
    return ScriptStatisticsDateList(
      scriptName: _readString(json['script_name']),
      dates: dates,
    );
  }

  /// 脚本名。
  final String scriptName;

  /// 可选择的日期列表。
  final List<String> dates;
}

/// 战斗汇总。
class ScriptStatisticsBattleSummary {
  /// 创建战斗汇总。
  ScriptStatisticsBattleSummary({
    required this.count,
    required this.avgDurationSeconds,
  });

  /// 从服务端 JSON 构建战斗汇总。
  factory ScriptStatisticsBattleSummary.fromJson(Map<String, dynamic> json) {
    return ScriptStatisticsBattleSummary(
      count: _readInt(json['count']),
      avgDurationSeconds: _readDouble(json['avg_duration_seconds']),
    );
  }

  /// 战斗次数。
  final int count;

  /// 平均战斗耗时（秒）。
  final double avgDurationSeconds;
}

/// 单次任务运行记录。
class ScriptTaskRunRecord {
  /// 创建任务运行记录。
  ScriptTaskRunRecord({
    required this.startTimeText,
    required this.endTimeText,
    required this.durationSeconds,
    required this.battle,
    required DateTime? startTime,
    required DateTime? endTime,
  }) : _startTime = startTime,
       _endTime = endTime;

  /// 从服务端 JSON 构建任务运行记录。
  factory ScriptTaskRunRecord.fromJson(Map<String, dynamic> json) {
    final battleJson = json['battle'];
    final startTimeText = _readString(json['start_time']);
    final endTimeText = _readString(json['end_time']);
    return ScriptTaskRunRecord(
      startTimeText: startTimeText,
      endTimeText: endTimeText,
      durationSeconds: _readDouble(json['duration_seconds']),
      battle: battleJson is Map
          ? ScriptStatisticsBattleSummary.fromJson(
              Map<String, dynamic>.from(battleJson),
            )
          : null,
      startTime: _tryParseDateTime(startTimeText),
      endTime: _tryParseDateTime(endTimeText),
    );
  }

  /// 原始开始时间文本。
  final String startTimeText;

  /// 原始结束时间文本。
  final String endTimeText;

  /// 本次运行耗时（秒）。
  final double durationSeconds;

  /// 可选战斗汇总。
  final ScriptStatisticsBattleSummary? battle;

  final DateTime? _startTime;
  final DateTime? _endTime;

  /// 解析后的开始时间。
  DateTime? get startTime => _startTime;

  /// 解析后的结束时间。
  DateTime? get endTime => _endTime;

  /// 当前记录的战斗次数。
  int get battleCount => battle?.count ?? 0;

  /// 当前记录的战斗均耗时。
  double get battleAvgDurationSeconds => battle?.avgDurationSeconds ?? 0;

  /// 稳定选择 key。
  String get selectionKey {
    return '$startTimeText|$endTimeText|$durationSeconds|$battleCount';
  }

  /// 是否同时拥有合法开始/结束时间。
  bool get hasTimeRange => startTime != null && endTime != null;

  /// 按指标取值，供图表层复用。
  double metricValueFor(ScriptStatisticsChartMetric metric) {
    return switch (metric) {
      ScriptStatisticsChartMetric.totalDuration => durationSeconds,
      ScriptStatisticsChartMetric.runCount => 1,
      ScriptStatisticsChartMetric.battleCount => battleCount.toDouble(),
      ScriptStatisticsChartMetric.battleAvgDuration => battleAvgDurationSeconds,
      ScriptStatisticsChartMetric.avgRunDuration => durationSeconds,
    };
  }
}

/// 单个任务在某天的聚合统计。
class ScriptTaskStatistics {
  /// 创建任务聚合统计。
  ScriptTaskStatistics({
    required this.runCount,
    required this.totalDurationSeconds,
    required this.battle,
    required this.runs,
    required this.latestRunStartTime,
  });

  /// 从服务端 JSON 构建任务聚合统计。
  factory ScriptTaskStatistics.fromJson(Map<String, dynamic> json) {
    final battleJson = json['battle'];
    final runsJson = json['runs'];
    final runs = runsJson is List
        ? runsJson
              .whereType<Map>()
              .map(
                (item) =>
                    ScriptTaskRunRecord.fromJson(item.cast<String, dynamic>()),
              )
              .toList()
        : <ScriptTaskRunRecord>[];
    runs.sort((left, right) {
      final leftTime = left.startTime;
      final rightTime = right.startTime;
      if (leftTime == null && rightTime == null) {
        return 0;
      }
      if (leftTime == null) {
        return 1;
      }
      if (rightTime == null) {
        return -1;
      }
      return leftTime.compareTo(rightTime);
    });
    return ScriptTaskStatistics(
      runCount: _readInt(json['run_count']),
      totalDurationSeconds: _readDouble(json['total_duration_seconds']),
      battle: battleJson is Map
          ? ScriptStatisticsBattleSummary.fromJson(
              Map<String, dynamic>.from(battleJson),
            )
          : null,
      runs: runs,
      latestRunStartTime: _readLatestRunStartTime(runs),
    );
  }

  /// 运行次数。
  final int runCount;

  /// 总耗时（秒）。
  final double totalDurationSeconds;

  /// 可选战斗汇总。
  final ScriptStatisticsBattleSummary? battle;

  /// 运行明细。
  final List<ScriptTaskRunRecord> runs;

  /// 最近一次运行开始时间。
  final DateTime? latestRunStartTime;

  /// 战斗次数。
  int get battleCount => battle?.count ?? 0;

  /// 战斗均耗时。
  double get battleAvgDurationSeconds => battle?.avgDurationSeconds ?? 0;

  /// 平均单次运行耗时。
  double get avgRunDurationSeconds {
    if (runCount <= 0) {
      return 0;
    }
    return totalDurationSeconds / runCount;
  }

  /// 按指标取值，供图表层复用。
  double metricValueFor(ScriptStatisticsChartMetric metric) {
    return switch (metric) {
      ScriptStatisticsChartMetric.totalDuration => totalDurationSeconds,
      ScriptStatisticsChartMetric.runCount => runCount.toDouble(),
      ScriptStatisticsChartMetric.battleCount => battleCount.toDouble(),
      ScriptStatisticsChartMetric.battleAvgDuration => battleAvgDurationSeconds,
      ScriptStatisticsChartMetric.avgRunDuration => avgRunDurationSeconds,
    };
  }
}

/// 某一天的统计快照。
class ScriptStatisticsDay {
  /// 创建某一天的统计快照。
  ScriptStatisticsDay({
    required this.scriptName,
    required this.dateKey,
    required this.totalRuntimeSeconds,
    required this.totalTaskRunCount,
    required this.totalBattleCount,
    required this.tasks,
    required this.multi,
  });

  /// 从 snapshot JSON 构建统计快照。
  factory ScriptStatisticsDay.fromSnapshotJson(
    Map<String, dynamic> json, {
    required String dateKey,
  }) {
    return ScriptStatisticsDay(
      scriptName: _readString(json['script_name']),
      dateKey: dateKey,
      totalRuntimeSeconds: _readDouble(json['total_runtime_seconds']),
      totalTaskRunCount: _readInt(json['total_task_run_count']),
      totalBattleCount: _readInt(json['total_battle_count']),
      tasks: _readTasks(json['tasks']),
      multi: _readMultiStatistics(json['multi']),
    );
  }

  /// 脚本名。
  final String scriptName;

  /// 日期 key。
  final String dateKey;

  /// 总运行耗时（秒）。
  final double totalRuntimeSeconds;

  /// 总任务运行次数。
  final int totalTaskRunCount;

  /// 总战斗次数。
  final int totalBattleCount;

  /// 任务聚合统计。
  final Map<String, ScriptTaskStatistics> tasks;

  /// 多号统计信息。
  final ScriptMultiStatistics? multi;

  /// 该日期是否是今天。
  bool get isToday => isStatisticsDateToday(dateKey);

  /// 不同任务数。
  int get taskCount => tasks.length;

  /// 打平后的运行记录列表。
  List<MapEntry<String, ScriptTaskRunRecord>> get runEntries {
    final entries = <MapEntry<String, ScriptTaskRunRecord>>[];
    for (final entry in tasks.entries) {
      for (final run in entry.value.runs) {
        if (run.hasTimeRange) {
          entries.add(MapEntry(entry.key, run));
        }
      }
    }
    entries.sort((left, right) {
      final leftStart = left.value.startTime;
      final rightStart = right.value.startTime;
      if (leftStart == null && rightStart == null) {
        return 0;
      }
      if (leftStart == null) {
        return 1;
      }
      if (rightStart == null) {
        return -1;
      }
      return leftStart.compareTo(rightStart);
    });
    return entries;
  }

  /// 应用一次增量更新。
  ScriptStatisticsDay applyUpdate(ScriptStatisticsUpdate update) {
    final nextTasks = Map<String, ScriptTaskStatistics>.from(tasks);
    for (final entry in update.changedTasks.entries) {
      nextTasks[entry.key] = entry.value;
    }
    for (final taskName in update.removedTasks) {
      nextTasks.remove(taskName);
    }
    return ScriptStatisticsDay(
      scriptName: update.scriptName.isEmpty ? scriptName : update.scriptName,
      dateKey: dateKey,
      totalRuntimeSeconds: update.totalRuntimeSeconds,
      totalTaskRunCount: update.totalTaskRunCount,
      totalBattleCount: update.totalBattleCount,
      tasks: nextTasks,
      multi: update.multi,
    );
  }
}

/// 单次 SSE 增量更新。
class ScriptStatisticsUpdate {
  /// 创建统计增量更新。
  ScriptStatisticsUpdate({
    required this.scriptName,
    required this.totalRuntimeSeconds,
    required this.totalTaskRunCount,
    required this.totalBattleCount,
    required this.changedTasks,
    required this.removedTasks,
    required this.multi,
  });

  /// 从服务端 JSON 构建统计增量更新。
  factory ScriptStatisticsUpdate.fromJson(Map<String, dynamic> json) {
    final removedTasks = json['removed_tasks'];
    return ScriptStatisticsUpdate(
      scriptName: _readString(json['script_name']),
      totalRuntimeSeconds: _readDouble(json['total_runtime_seconds']),
      totalTaskRunCount: _readInt(json['total_task_run_count']),
      totalBattleCount: _readInt(json['total_battle_count']),
      changedTasks: _readTasks(json['changed_tasks']),
      removedTasks: removedTasks is List
          ? removedTasks
                .map((item) => item.toString().trim())
                .where((item) => item.isNotEmpty)
                .toList()
          : <String>[],
      multi: _readMultiStatistics(json['multi']),
    );
  }

  /// 脚本名。
  final String scriptName;

  /// 更新后的总运行耗时。
  final double totalRuntimeSeconds;

  /// 更新后的总任务运行次数。
  final int totalTaskRunCount;

  /// 更新后的总战斗次数。
  final int totalBattleCount;

  /// 被替换的任务。
  final Map<String, ScriptTaskStatistics> changedTasks;

  /// 被删除的任务名列表。
  final List<String> removedTasks;

  /// 多号统计信息。
  final ScriptMultiStatistics? multi;
}

/// 解析统计时间文本。
DateTime? tryParseStatisticsDateTime(String value) {
  return _tryParseDateTime(value);
}

/// 在 isolate 中解析某一天的统计快照。
Future<ScriptStatisticsDay> parseScriptStatisticsDayAsync(
  Map<String, dynamic> json, {
  required String dateKey,
}) {
  return _runStatisticsParser(
    () => ScriptStatisticsDay.fromSnapshotJson(
      Map<String, dynamic>.from(json),
      dateKey: dateKey,
    ),
  );
}

/// 在 isolate 中解析 snapshot SSE 载荷。
Future<ScriptStatisticsDay> parseScriptStatisticsSnapshotPayloadAsync(
  String payloadText, {
  required String dateKey,
}) {
  return _runStatisticsParser(() {
    return ScriptStatisticsDay.fromSnapshotJson(
      _decodeStatisticsPayload(payloadText),
      dateKey: dateKey,
    );
  });
}

/// 在 isolate 中解析 update SSE 载荷。
Future<ScriptStatisticsUpdate> parseScriptStatisticsUpdatePayloadAsync(
  String payloadText,
) {
  return _runStatisticsParser(() {
    return ScriptStatisticsUpdate.fromJson(
      _decodeStatisticsPayload(payloadText),
    );
  });
}

/// 判断指标是否应按时长格式化。
bool statisticsMetricUsesDuration(ScriptStatisticsChartMetric metric) {
  return switch (metric) {
    ScriptStatisticsChartMetric.totalDuration ||
    ScriptStatisticsChartMetric.battleAvgDuration ||
    ScriptStatisticsChartMetric.avgRunDuration => true,
    ScriptStatisticsChartMetric.runCount ||
    ScriptStatisticsChartMetric.battleCount => false,
  };
}

/// 判断指标是否需要隐藏无战斗行。
bool statisticsMetricUsesBattleFilter(ScriptStatisticsChartMetric metric) {
  return switch (metric) {
    ScriptStatisticsChartMetric.battleCount ||
    ScriptStatisticsChartMetric.battleAvgDuration => true,
    ScriptStatisticsChartMetric.totalDuration ||
    ScriptStatisticsChartMetric.runCount ||
    ScriptStatisticsChartMetric.avgRunDuration => false,
  };
}

/// 判断日期 key 是否是当前本地日期。
bool isStatisticsDateToday(String dateKey) {
  final selectedDate = DateTime.tryParse(dateKey);
  if (selectedDate == null) {
    return false;
  }
  final now = DateTime.now();
  return selectedDate.year == now.year &&
      selectedDate.month == now.month &&
      selectedDate.day == now.day;
}

/// 返回任务名的稳定颜色索引值。
int statisticsTaskColorSeed(String taskName) {
  return taskName.hashCode.abs();
}

/// 多号统计按会话筛选后的页面数据。
class MultiAccountSessionViewData {
  /// 创建按会话筛选后的页面数据。
  const MultiAccountSessionViewData({
    required this.accounts,
    required this.totalDurationSeconds,
  });

  /// 筛选后参与图表、表格和概览的账号。
  final List<ScriptMultiAccountStatistics> accounts;

  /// 筛选后概览总耗时。
  final double totalDurationSeconds;
}

/// 按 MultiAcc 会话筛选账号数据，供页面和测试复用。
MultiAccountSessionViewData filterMultiAccountSessionData({
  required ScriptMultiStatistics multi,
  required int? sessionIndex,
}) {
  if (sessionIndex == null) {
    final fallbackTotal = multi.accounts.fold<double>(
      0,
      (sum, account) => sum + account.durationSeconds,
    );
    return MultiAccountSessionViewData(
      accounts: multi.accounts,
      // 中文注释：全天视图优先使用后端返回的 totalDurationSeconds，缺失时才回退账号累加。
      totalDurationSeconds: multi.totalDurationSeconds > 0
          ? multi.totalDurationSeconds
          : fallbackTotal,
    );
  }

  final session = _sessionByIndex(multi.sessions, sessionIndex);
  // 中文注释：会话不存在时回退到全天，避免把合法数据误判为空。
  if (session == null) {
    return filterMultiAccountSessionData(multi: multi, sessionIndex: null);
  }

  final accounts = multi.accounts
      .map((account) => _filterAccountForSession(account, sessionIndex, session))
      .whereType<ScriptMultiAccountStatistics>()
      .toList();
  return MultiAccountSessionViewData(
    accounts: accounts,
    // 中文注释：会话视图必须按筛选后账号重新累加总耗时，不能复用全天值。
    totalDurationSeconds: accounts.fold<double>(
      0,
      (sum, account) => sum + account.durationSeconds,
    ),
  );
}

/// 多号统计顶层模型。
class ScriptMultiStatistics {
  /// 创建多号统计顶层模型。
  ScriptMultiStatistics({
    required this.accounts,
    required this.sessions,
    required this.totalDurationSeconds,
  });

  /// 从服务端 JSON 构建多号统计顶层模型。
  factory ScriptMultiStatistics.fromJson(Map<String, dynamic> json) {
    final rawAccounts = json['accounts'];
    return ScriptMultiStatistics(
      accounts: rawAccounts is List
          ? rawAccounts
                .whereType<Map>()
                .map(
                  (item) => ScriptMultiAccountStatistics.fromJson(
                    item.cast<String, dynamic>(),
                  ),
                )
                .toList()
          : <ScriptMultiAccountStatistics>[],
      sessions: _readMultiSessionList(json['sessions']),
      totalDurationSeconds: _readDouble(json['total_duration_seconds']),
    );
  }

  /// 账号统计列表。
  final List<ScriptMultiAccountStatistics> accounts;

  /// 多号运行会话列表。
  final List<ScriptMultiSessionRecord> sessions;

  /// 全天总耗时。
  final double totalDurationSeconds;
}

/// 多号统计中的单账号模型。
class ScriptMultiAccountStatistics {
  /// 创建单账号统计模型。
  ScriptMultiAccountStatistics({
    required this.account,
    required this.character,
    required this.svr,
    required this.switchOk,
    required this.durationSeconds,
    required this.errorCount,
    required this.battleCount,
    required this.battleTotalDurationSeconds,
    required this.battleAvgDurationSeconds,
    required this.coopTotal,
    required this.tasks,
    required this.errors,
    required this.coops,
    required this.mshops,
    required this.segments,
  });

  /// 从服务端 JSON 构建单账号统计模型。
  factory ScriptMultiAccountStatistics.fromJson(Map<String, dynamic> json) {
    return ScriptMultiAccountStatistics(
      account: _readString(json['account']),
      character: _readString(json['character']),
      svr: _readString(json['svr']),
      switchOk: json['switch_ok'] is bool ? json['switch_ok'] as bool : null,
      durationSeconds: _readDouble(json['duration_seconds']),
      errorCount: _readInt(json['error_count']),
      battleCount: _readInt(json['battle_count']),
      battleTotalDurationSeconds: _readDouble(
        json['battle_total_duration_seconds'],
      ),
      battleAvgDurationSeconds: _readDouble(
        json['battle_avg_duration_seconds'],
      ),
      coopTotal: _readInt(json['coop_total']),
      tasks: _readMultiTaskList(json['tasks']),
      errors: _readMultiErrorList(json['errors']),
      coops: _readMultiCoopList(json['coops']),
      mshops: _readMultiMshopList(json['mshops']),
      segments: _readMultiSegmentList(json['segments']),
    );
  }

  /// 账号名。
  final String account;

  /// 角色名。
  final String character;

  /// 区服名。
  final String svr;

  /// 是否切号成功。
  final bool? switchOk;

  /// 总耗时。
  final double durationSeconds;

  /// 错误数。
  final int errorCount;

  /// 战斗次数。
  final int battleCount;

  /// 战斗总耗时。
  final double battleTotalDurationSeconds;

  /// 战斗平均耗时。
  final double battleAvgDurationSeconds;

  /// 协作总数。
  final int coopTotal;

  /// 子任务记录列表。
  final List<ScriptMultiTaskRecord> tasks;

  /// 错误记录列表。
  final List<ScriptMultiErrorRecord> errors;

  /// 协作记录列表。
  final List<ScriptMultiCoopRecord> coops;

  /// 商店记录列表。
  final List<ScriptMultiMshopRecord> mshops;

  /// 运行段列表。
  final List<ScriptMultiSegmentRecord> segments;

  /// 默认展示名。
  String get displayName => displayLabelFor(MultiAccountLabelStyle.charSvr);

  /// 按指定规则生成展示名。
  String displayLabelFor(MultiAccountLabelStyle style) {
    final char = character;
    switch (style) {
      case MultiAccountLabelStyle.char:
        return char.isEmpty ? account : char;
      case MultiAccountLabelStyle.charSvr:
        return char.isEmpty ? account : (svr.isEmpty ? char : '$char-$svr');
      case MultiAccountLabelStyle.charAcc:
        return char.isEmpty ? account : (account.isEmpty ? char : '$char-$account');
      case MultiAccountLabelStyle.charAccSvr:
        if (char.isEmpty) return account;
        final tail = [
          if (account.isNotEmpty) account,
          if (svr.isNotEmpty) svr,
        ].join('-');
        return tail.isEmpty ? char : '$char-$tail';
    }
  }

  /// 获取某个子任务的耗时。
  double durationForTask(String taskName) {
    for (final item in tasks) {
      if (item.task == taskName) {
        return item.durationSeconds ?? 0;
      }
    }
    return 0;
  }

  /// 该账号出现过的全部子任务名集合。
  List<String> get taskKeys {
    final seen = <String>{};
    final result = <String>[];
    for (final item in tasks) {
      final name = item.task;
      if (name.isNotEmpty && seen.add(name)) {
        result.add(name);
      }
    }
    return result;
  }

  /// 子任务摘要。
  String get taskSummary => tasks.map((item) => item.task).join(', ');

  /// 错误摘要。
  String get errorSummary {
    return errors.isEmpty ? '无' : errors.map((item) => item.displayText).join('\n');
  }

  /// 协作摘要。
  String get coopSummary {
    if (coops.isEmpty) {
      return '未找到';
    }
    final counter = <String, int>{};
    for (final coop in coops) {
      final key = '${coop.real ? '现世' : '普通'}${coop.ctype}';
      counter[key] = (counter[key] ?? 0) + 1;
    }
    return counter.entries.map((entry) => '${entry.key}×${entry.value}').join(', ');
  }

  /// 商店摘要。
  String get mshopSummary {
    if (mshops.isEmpty) {
      return '-';
    }
    return mshops
        .map(
          (item) => '${item.goods}${item.price == null ? '' : '(${item.price})'}',
        )
        .join(', ');
  }
}

/// 多号统计中的子任务记录。
class ScriptMultiTaskRecord {
  /// 创建多号统计子任务记录。
  ScriptMultiTaskRecord({
    required this.task,
    required this.ok,
    required this.startTime,
    required this.durationSeconds,
    required this.battleCount,
    required this.battleTotalDurationSeconds,
    required this.battleAvgDurationSeconds,
  });

  /// 从服务端 JSON 构建多号统计子任务记录。
  factory ScriptMultiTaskRecord.fromJson(Map<String, dynamic> json) {
    return ScriptMultiTaskRecord(
      task: _readString(json['task']),
      ok: json['ok'] is bool ? json['ok'] as bool : false,
      startTime: _readString(json['start_time']),
      durationSeconds: json['duration_seconds'] == null
          ? null
          : _readDouble(json['duration_seconds']),
      battleCount: _readInt(json['battle_count']),
      battleTotalDurationSeconds: _readDouble(
        json['battle_total_duration_seconds'],
      ),
      battleAvgDurationSeconds: _readDouble(
        json['battle_avg_duration_seconds'],
      ),
    );
  }

  /// 子任务名。
  final String task;

  /// 是否成功。
  final bool ok;

  /// 子任务开始时间文本。
  final String startTime;

  /// 子任务耗时。
  final double? durationSeconds;

  /// 子任务战斗次数。
  final int battleCount;

  /// 子任务战斗总耗时。
  final double battleTotalDurationSeconds;

  /// 子任务战斗平均耗时。
  final double battleAvgDurationSeconds;
}

/// 多号统计中的错误记录。
class ScriptMultiErrorRecord {
  /// 创建多号统计错误记录。
  ScriptMultiErrorRecord({
    required this.task,
    required this.etype,
    required this.emsg,
  });

  /// 从服务端 JSON 构建多号统计错误记录。
  factory ScriptMultiErrorRecord.fromJson(Map<String, dynamic> json) {
    return ScriptMultiErrorRecord(
      task: _readString(json['task']),
      etype: _readString(json['etype']),
      emsg: _readString(json['emsg']),
    );
  }

  /// 任务名。
  final String task;

  /// 错误类型。
  final String etype;

  /// 错误信息。
  final String emsg;

  /// 对外展示文本。
  String get displayText {
    final parts = [task, etype, emsg].where((item) => item.trim().isNotEmpty);
    return parts.join(': ');
  }
}

/// 多号统计中的协作记录。
class ScriptMultiCoopRecord {
  /// 创建多号统计协作记录。
  ScriptMultiCoopRecord({
    required this.ctype,
    required this.real,
    required this.time,
  });

  /// 从服务端 JSON 构建多号统计协作记录。
  factory ScriptMultiCoopRecord.fromJson(Map<String, dynamic> json) {
    return ScriptMultiCoopRecord(
      ctype: _readString(json['ctype']),
      real: json['real'] is bool ? json['real'] as bool : false,
      time: _readString(json['time']),
    );
  }

  /// 协作类型。
  final String ctype;

  /// 是否现世协作。
  final bool real;

  /// 事件时间文本。
  final String time;
}

/// 多号统计中的商店记录。
class ScriptMultiMshopRecord {
  /// 创建多号统计商店记录。
  ScriptMultiMshopRecord({
    required this.goods,
    required this.price,
    required this.time,
  });

  /// 从服务端 JSON 构建多号统计商店记录。
  factory ScriptMultiMshopRecord.fromJson(Map<String, dynamic> json) {
    return ScriptMultiMshopRecord(
      goods: _readString(json['goods']),
      price: json['price'] is num ? json['price'] as num : null,
      time: _readString(json['time']),
    );
  }

  /// 商品名。
  final String goods;

  /// 价格。
  final num? price;

  /// 事件时间文本。
  final String time;
}

/// 多号统计中的运行段记录。
class ScriptMultiSegmentRecord {
  /// 创建多号统计运行段记录。
  ScriptMultiSegmentRecord({
    required this.startTimeText,
    required this.endTimeText,
    required this.durationSeconds,
    required this.session,
    required DateTime? startTime,
    required DateTime? endTime,
  }) : _startTime = startTime,
       _endTime = endTime;

  /// 从服务端 JSON 构建多号统计运行段记录。
  factory ScriptMultiSegmentRecord.fromJson(Map<String, dynamic> json) {
    final startText = _readString(json['start_time']);
    final endText = _readString(json['end_time']);
    return ScriptMultiSegmentRecord(
      startTimeText: startText,
      endTimeText: endText,
      durationSeconds: _readDouble(json['duration_seconds']),
      session: _readInt(json['session']),
      startTime: _tryParseDateTime(startText),
      endTime: _tryParseDateTime(endText),
    );
  }

  /// 运行段开始时间文本。
  final String startTimeText;

  /// 运行段结束时间文本。
  final String endTimeText;

  /// 运行段耗时。
  final double durationSeconds;

  /// 所属会话索引。
  final int session;

  final DateTime? _startTime;
  final DateTime? _endTime;

  /// 解析后的开始时间。
  DateTime? get startTime => _startTime;

  /// 解析后的结束时间。
  DateTime? get endTime => _endTime;
}

/// 多号统计中的会话记录。
class ScriptMultiSessionRecord {
  /// 创建多号统计会话记录。
  ScriptMultiSessionRecord({
    required this.index,
    required this.startTimeText,
    required this.endTimeText,
    required this.durationSeconds,
    required this.accountCount,
    required DateTime? startTime,
  }) : _startTime = startTime;

  /// 从服务端 JSON 构建多号统计会话记录。
  factory ScriptMultiSessionRecord.fromJson(Map<String, dynamic> json) {
    final startText = _readString(json['start_time']);
    return ScriptMultiSessionRecord(
      index: _readInt(json['index']),
      startTimeText: startText,
      endTimeText: _readString(json['end_time']),
      durationSeconds: _readDouble(json['duration_seconds']),
      accountCount: _readInt(json['account_count']),
      startTime: _tryParseDateTime(startText),
    );
  }

  /// 会话索引。
  final int index;

  /// 会话开始时间文本。
  final String startTimeText;

  /// 会话结束时间文本。
  final String endTimeText;

  /// 会话总耗时。
  final double durationSeconds;

  /// 会话涉及账号数。
  final int accountCount;

  final DateTime? _startTime;

  /// 解析后的开始时间。
  DateTime? get startTime => _startTime;
}

/// 按索引查找会话。
ScriptMultiSessionRecord? _sessionByIndex(
  List<ScriptMultiSessionRecord> sessions,
  int sessionIndex,
) {
  for (final session in sessions) {
    if (session.index == sessionIndex) {
      return session;
    }
  }
  return null;
}

/// 生成单个账号在指定会话内的统计副本。
ScriptMultiAccountStatistics? _filterAccountForSession(
  ScriptMultiAccountStatistics account,
  int sessionIndex,
  ScriptMultiSessionRecord session,
) {
  final segments = account.segments
      .where((segment) => segment.session == sessionIndex)
      .toList();
  // 中文注释：没有命中该 session 的账号必须被剔除，不能保留 0 值占位。
  if (segments.isEmpty) {
    return null;
  }

  final durationSeconds = segments.fold<double>(
    0,
    (sum, segment) => sum + segment.durationSeconds,
  );
  final tasks = account.tasks
      .where((task) => _isTextTimeInSession(task.startTime, session))
      .toList();
  final coops = account.coops
      .where((coop) => _isTextTimeInSession(coop.time, session))
      .toList();
  final mshops = account.mshops
      .where((mshop) => _isTextTimeInSession(mshop.time, session))
      .toList();
  final sessionBattleCount = tasks.fold<int>(
    0,
    (sum, task) => sum + task.battleCount,
  );
  final sessionBattleTotalDuration = tasks.fold<double>(
    0,
    (sum, task) => sum + task.battleTotalDurationSeconds,
  );
  final sessionBattleAvgDuration = sessionBattleCount > 0
      ? sessionBattleTotalDuration / sessionBattleCount
      : 0.0;

  return ScriptMultiAccountStatistics(
    account: account.account,
    character: account.character,
    svr: account.svr,
    switchOk: account.switchOk,
    durationSeconds: durationSeconds,
    // 中文注释：错误缺少逐事件时间戳，无法可靠归属到 session，故会话视图中置 0。
    errorCount: 0,
    battleCount: sessionBattleCount,
    battleTotalDurationSeconds: sessionBattleTotalDuration,
    battleAvgDurationSeconds: sessionBattleAvgDuration,
    coopTotal: coops.length,
    tasks: tasks,
    // 中文注释：错误明细同样不在 session 视图中保留，避免混入全天数据。
    errors: const [],
    coops: coops,
    mshops: mshops,
    segments: segments,
  );
}

/// 判断文本时间是否落在指定会话窗口内。
bool _isTextTimeInSession(String timeText, ScriptMultiSessionRecord session) {
  final time = tryParseStatisticsDateTime(timeText);
  final start = session.startTime;
  final end = tryParseStatisticsDateTime(session.endTimeText);
  if (time == null || start == null || end == null) {
    return false;
  }
  return !time.isBefore(start) && !time.isAfter(end);
}

/// 读取任务映射。
Map<String, ScriptTaskStatistics> _readTasks(dynamic value) {
  final tasks = <String, ScriptTaskStatistics>{};
  if (value is! Map) {
    return tasks;
  }
  for (final entry in value.entries) {
    if (entry.value is Map) {
      tasks[entry.key.toString()] = ScriptTaskStatistics.fromJson(
        Map<String, dynamic>.from(entry.value as Map),
      );
    }
  }
  return tasks;
}

/// 读取多号统计顶层模型。
ScriptMultiStatistics? _readMultiStatistics(dynamic value) {
  if (value is! Map) {
    return null;
  }
  return ScriptMultiStatistics.fromJson(Map<String, dynamic>.from(value));
}

/// 读取多号统计子任务列表。
List<ScriptMultiTaskRecord> _readMultiTaskList(dynamic value) {
  if (value is! List) {
    return const <ScriptMultiTaskRecord>[];
  }
  return value
      .whereType<Map>()
      .map((item) => ScriptMultiTaskRecord.fromJson(item.cast<String, dynamic>()))
      .toList();
}

/// 读取多号统计错误列表。
List<ScriptMultiErrorRecord> _readMultiErrorList(dynamic value) {
  if (value is! List) {
    return const <ScriptMultiErrorRecord>[];
  }
  return value
      .whereType<Map>()
      .map((item) => ScriptMultiErrorRecord.fromJson(item.cast<String, dynamic>()))
      .toList();
}

/// 读取多号统计协作列表。
List<ScriptMultiCoopRecord> _readMultiCoopList(dynamic value) {
  if (value is! List) {
    return const <ScriptMultiCoopRecord>[];
  }
  return value
      .whereType<Map>()
      .map((item) => ScriptMultiCoopRecord.fromJson(item.cast<String, dynamic>()))
      .toList();
}

/// 读取多号统计商店列表。
List<ScriptMultiMshopRecord> _readMultiMshopList(dynamic value) {
  if (value is! List) {
    return const <ScriptMultiMshopRecord>[];
  }
  return value
      .whereType<Map>()
      .map((item) => ScriptMultiMshopRecord.fromJson(item.cast<String, dynamic>()))
      .toList();
}

/// 读取多号统计运行段列表。
List<ScriptMultiSegmentRecord> _readMultiSegmentList(dynamic value) {
  if (value is! List) {
    return const <ScriptMultiSegmentRecord>[];
  }
  return value
      .whereType<Map>()
      .map((item) => ScriptMultiSegmentRecord.fromJson(item.cast<String, dynamic>()))
      .toList();
}

/// 读取多号统计会话列表。
List<ScriptMultiSessionRecord> _readMultiSessionList(dynamic value) {
  if (value is! List) {
    return const <ScriptMultiSessionRecord>[];
  }
  return value
      .whereType<Map>()
      .map((item) => ScriptMultiSessionRecord.fromJson(item.cast<String, dynamic>()))
      .toList();
}

/// 安全读取字符串。
String _readString(dynamic value) => value?.toString().trim() ?? '';

/// 安全读取整数。
int _readInt(dynamic value) {
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(_readString(value)) ?? 0;
}

/// 安全读取浮点数。
double _readDouble(dynamic value) {
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(_readString(value)) ?? 0;
}

/// 解析后端时间文本。
DateTime? _tryParseDateTime(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    return null;
  }
  final isoText = normalized.contains('T')
      ? normalized
      : normalized.replaceFirst(' ', 'T');
  return DateTime.tryParse(isoText);
}

/// 解码统计 JSON 载荷。
Map<String, dynamic> _decodeStatisticsPayload(String payloadText) {
  final payload = jsonDecode(payloadText);
  if (payload is! Map) {
    throw const FormatException('Invalid statistics payload');
  }
  return Map<String, dynamic>.from(
    payload.map((key, value) => MapEntry(key.toString(), value)),
  );
}

/// 读取最近一次合法运行开始时间。
DateTime? _readLatestRunStartTime(List<ScriptTaskRunRecord> runs) {
  for (final run in runs.reversed) {
    final startTime = run.startTime;
    if (startTime != null) {
      return startTime;
    }
  }
  return null;
}

/// 在非 Web 环境使用 isolate 解析统计模型。
Future<T> _runStatisticsParser<T>(T Function() parser) {
  if (kIsWeb) {
    return Future<T>.value(parser());
  }
  return Isolate.run(parser);
}
