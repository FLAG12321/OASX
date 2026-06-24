import 'package:flutter/material.dart';
import 'package:oasx/model/stats/script_statistics_models.dart';
import 'package:oasx/views/overview/multi_account_stats_chart.dart';
import 'package:oasx/views/overview/multi_account_stats_table.dart';

/// 多账号统计独立页，必须消费已有 snapshot 数据，不能自行重新拉取数据。
class MultiAccountStatsPage extends StatelessWidget {
  /// 创建多账号统计独立页。
  const MultiAccountStatsPage({
    super.key,
    required this.statisticsDay,
    this.initialDateKey,
    this.initialSessionIndex,
  });

  /// 已有的统计快照。
  final ScriptStatisticsDay statisticsDay;

  /// 初始日期 key。
  final String? initialDateKey;

  /// 初始会话索引。
  final int? initialSessionIndex;

  @override
  Widget build(BuildContext context) {
    final multi = statisticsDay.multi;
    final viewData = multi == null
        ? const MultiAccountSessionViewData(accounts: [], totalDurationSeconds: 0)
        : filterMultiAccountSessionData(
            multi: multi,
            sessionIndex: initialSessionIndex,
          );
    return Scaffold(
      appBar: AppBar(
        title: const Text('多账号统计'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text('日期：${initialDateKey ?? statisticsDay.dateKey}'),
          const SizedBox(height: 8),
          Text('账号数：${viewData.accounts.length}'),
          const SizedBox(height: 8),
          Text('总耗时：${viewData.totalDurationSeconds}'),
          const SizedBox(height: 12),
          MultiAccountBarChart(
            accounts: viewData.accounts,
            metric: MultiStatsChartMetric.duration,
          ),
          const SizedBox(height: 12),
          MultiAccountStatsTable(accounts: viewData.accounts),
        ],
      ),
    );
  }
}
