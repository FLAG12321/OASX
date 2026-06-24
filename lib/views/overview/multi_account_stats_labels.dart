import 'package:get/get.dart';
import 'package:oasx/config/translation/i18n_content.dart';

/// 统一翻译多号统计中后端透传的子任务名，未知值原样显示避免空白。
String formatMultiStatsTaskLabel(String raw) {
  final key = raw.trim().toLowerCase();
  return switch (key) {
    'mail' => I18n.multiStatsTaskMail.tr,
    'allieteam' => I18n.multiStatsTaskAllieTeam.tr,
    'courtyard' => I18n.multiStatsTaskCourtyard.tr,
    'cooperation' => I18n.multiStatsTaskCooperation.tr,
    'alliedteam' => I18n.multiStatsTaskAlliedTeam.tr,
    'returngift' => I18n.multiStatsTaskReturnGift.tr,
    _ => raw,
  };
}

/// 统一翻译协作类型，未知值原样显示，避免后端新增值导致空白。
String formatMultiStatsCoopTypeLabel(String raw) {
  final key = raw.trim().toLowerCase();
  return switch (key) {
    'gold' => I18n.multiStatsCoopGold.tr,
    'jade' => I18n.multiStatsCoopJade.tr,
    'sushi' => I18n.multiStatsCoopSushi.tr,
    'food' => I18n.multiStatsCoopFood.tr,
    _ => raw,
  };
}

/// 统一翻译商店物品名，未知值原样显示。
String formatMultiStatsGoodsLabel(String raw) {
  final key = raw.trim().toLowerCase();
  return switch (key) {
    'gold' => I18n.multiStatsGoodsGold.tr,
    'jade' => I18n.multiStatsGoodsJade.tr,
    'sushi' => I18n.multiStatsGoodsSushi.tr,
    'food' => I18n.multiStatsGoodsFood.tr,
    _ => raw,
  };
}
