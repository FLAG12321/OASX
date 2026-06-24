/// 统计页常用格式化函数。
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
  return dateKey.trim();
}
