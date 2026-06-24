/// 统一翻译多号统计中后端透传的子任务名，未知值原样显示避免空白。
String formatMultiStatsTaskLabel(String raw) {
  final key = raw.trim().toLowerCase();
  return switch (key) {
    'mail' => '邮件',
    'allieteam' => '盟友组队',
    'courtyard' => '庭院',
    'cooperation' => '协作',
    'alliedteam' => '盟友队伍',
    'returngift' => '回礼',
    _ => raw,
  };
}

/// 统一翻译协作类型，未知值原样显示，避免后端新增值导致空白。
String formatMultiStatsCoopTypeLabel(String raw) {
  final key = raw.trim().toLowerCase();
  return switch (key) {
    'gold' => '金币',
    'jade' => '勾玉',
    'sushi' => '寿司',
    'food' => '食物',
    _ => raw,
  };
}

/// 统一翻译商店物品名，未知值原样显示。
String formatMultiStatsGoodsLabel(String raw) {
  final key = raw.trim().toLowerCase();
  return switch (key) {
    'gold' => '金币',
    'jade' => '勾玉',
    'sushi' => '寿司',
    'food' => '食物',
    _ => raw,
  };
}
