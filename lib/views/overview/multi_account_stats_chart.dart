import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:oasx/model/stats/script_statistics_models.dart';
import 'package:oasx/views/overview/statistics_formatters.dart';

/// 多号统计指标类型。
enum MultiStatsChartMetric {
  duration,
  battleCount,
  errorCount,
  coopTotal,
  taskDuration,
  battleAvgDuration,
  battleTotalDuration,
}

/// 多号统计柱状图。
class MultiAccountBarChart extends StatelessWidget {
  /// 创建多号统计柱状图。
  const MultiAccountBarChart({
    super.key,
    required this.accounts,
    required this.metric,
    this.labelStyle = MultiAccountLabelStyle.charSvr,
    this.taskName,
  });

  /// 参与绘制的账号列表。
  final List<ScriptMultiAccountStatistics> accounts;

  /// 当前指标。
  final MultiStatsChartMetric metric;

  /// 账号标签样式。
  final MultiAccountLabelStyle labelStyle;

  /// 当指标为 taskDuration 时指定子任务名。
  final String? taskName;

  @override
  Widget build(BuildContext context) {
    if (accounts.isEmpty) {
      return const SizedBox.shrink();
    }

    final maxValue = accounts.fold<double>(
      0,
      (prev, account) => math.max(prev, _valueForAccount(account)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('最高值：${_formatValue(maxValue)}'),
        const SizedBox(height: 8),
        ...accounts.map(
          (account) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '${account.displayLabelFor(labelStyle)}：${_formatValue(_valueForAccount(account))}',
            ),
          ),
        ),
      ],
    );
  }

  double _valueForAccount(ScriptMultiAccountStatistics account) {
    return switch (metric) {
      MultiStatsChartMetric.duration => account.durationSeconds,
      MultiStatsChartMetric.battleCount => account.battleCount.toDouble(),
      MultiStatsChartMetric.errorCount => account.errorCount.toDouble(),
      MultiStatsChartMetric.coopTotal => account.coopTotal.toDouble(),
      MultiStatsChartMetric.taskDuration => account.durationForTask(taskName ?? ''),
      MultiStatsChartMetric.battleAvgDuration => account.battleAvgDurationSeconds,
      MultiStatsChartMetric.battleTotalDuration => account.battleTotalDurationSeconds,
    };
  }

  String _formatValue(double value) {
    if (metric == MultiStatsChartMetric.duration ||
        metric == MultiStatsChartMetric.taskDuration ||
        metric == MultiStatsChartMetric.battleAvgDuration ||
        metric == MultiStatsChartMetric.battleTotalDuration) {
      return formatStatisticsDuration(value);
    }
    return value.toInt().toString();
  }
}
