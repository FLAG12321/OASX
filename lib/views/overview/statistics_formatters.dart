import 'package:flutter/material.dart';
import 'package:oasx/model/stats/script_statistics_models.dart';

/// 将秒数格式化为可读的时长标签。
String formatStatisticsDuration(double seconds) {
  final normalizedSeconds = seconds < 0 ? 0 : seconds;
  final totalSeconds = normalizedSeconds.round();
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final remainSeconds = totalSeconds % 60;

  if (hours > 0) {
    return '${hours}h ${minutes}m ${remainSeconds}s';
  }
  if (minutes > 0) {
    return '${minutes}m ${remainSeconds}s';
  }
  return '${remainSeconds}s';
}

/// 将 yyyy-MM-dd 日期 key 转成直接可展示文本。
String formatStatisticsDayLabel(String dateKey) {
  final value = DateTime.tryParse(dateKey);
  if (value == null) {
    return dateKey.trim();
  }
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(value.month)}-${two(value.day)}';
}

/// 将 DateTime 格式化为 HH:mm:ss 时钟标签。
String formatStatisticsClockTime(DateTime? value) {
  if (value == null) {
    return '--';
  }
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
}

/// 将一次运行的起止时间格式化为时钟区间标签。
String formatStatisticsClockTimeRange(DateTime? start, DateTime? end) {
  return '${formatStatisticsClockTime(start)} -> ${formatStatisticsClockTime(end)}';
}

/// 按指标类型格式化数值：时长类指标按时长格式化，计数类按整数展示。
String formatStatisticsMetricByType(
  double value,
  ScriptStatisticsChartMetric metric,
) {
  if (statisticsMetricUsesDuration(metric)) {
    return formatStatisticsDuration(value);
  }
  return value.toInt().toString();
}

/// 将任务名映射为稳定的展示颜色，供图表/明细复用。
Color statisticsTaskColor(String taskName) {
  const palette = <Color>[
    Color(0xFF2563EB),
    Color(0xFFDC2626),
    Color(0xFF16A34A),
    Color(0xFFD97706),
    Color(0xFF7C3AED),
    Color(0xFF0891B2),
  ];
  final seed = statisticsTaskColorSeed(taskName);
  return palette[seed % palette.length];
}
