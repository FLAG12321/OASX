import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:oasx/controller/stats/stats_page_controller.dart';
import 'package:oasx/views/overview/multi_account_stats_page.dart';
import 'package:oasx/views/overview/statistics_formatters.dart';

/// Stats 首页面板：承接日期切换、摘要信息和多账号入口。
class StatsOverviewPanel extends StatefulWidget {
  /// 创建 Stats 首页面板。
  const StatsOverviewPanel({super.key, required this.scriptName});

  /// 当前脚本名。
  final String scriptName;

  @override
  State<StatsOverviewPanel> createState() => _StatsOverviewPanelState();
}

class _StatsOverviewPanelState extends State<StatsOverviewPanel> {
  late final StatsPageController controller;

  @override
  void initState() {
    super.initState();
    controller = Get.put(StatsPageController(), tag: widget.scriptName);
    // 中文注释：Stats 首页首次显示时立即启动快照编排层。
    controller.bootstrap(widget.scriptName);
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final statistics = controller.statistics.value;
      return ListView(
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Stats',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '日期：${controller.selectedDateKey.value.isEmpty ? '未选择' : formatStatisticsDayLabel(controller.selectedDateKey.value)}',
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '最近更新：${controller.lastUpdatedLabel.value.isEmpty ? '暂无' : controller.lastUpdatedLabel.value}',
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '总耗时：${statistics == null ? '暂无' : formatStatisticsDuration(statistics.totalRuntimeSeconds)}',
                  ),
                  const SizedBox(height: 4),
                  Text('任务数：${statistics?.taskCount ?? 0}'),
                  const SizedBox(height: 4),
                  Text('战斗数：${statistics?.totalBattleCount ?? 0}'),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: controller.hasMultiAccountEntry && statistics != null
                        ? () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => MultiAccountStatsPage(
                                  statisticsDay: statistics,
                                  initialDateKey: controller.selectedDateKey.value,
                                ),
                              ),
                            );
                          }
                        : null,
                    child: const Text('多账号统计'),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    });
  }
}
