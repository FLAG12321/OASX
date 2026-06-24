import 'package:flutter/material.dart';
import 'package:oasx/component/log/log_mixin.dart';
import 'package:oasx/component/log/log_widget.dart';
import 'package:oasx/views/overview/stats_overview_panel.dart';

/// 日志菜单承接页：默认显示 Logs，Stats 作为同容器第二标签。
class OverviewLogsStatsView extends StatefulWidget {
  /// 创建日志/统计容器页。
  const OverviewLogsStatsView({super.key, required this.controller});

  /// 当前脚本的日志控制器。
  final LogMixin controller;

  @override
  State<OverviewLogsStatsView> createState() => _OverviewLogsStatsViewState();
}

class _OverviewLogsStatsViewState extends State<OverviewLogsStatsView> {
  bool _showStats = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            ChoiceChip(
              label: const Text('Logs'),
              selected: !_showStats,
              onSelected: (_) {
                setState(() {
                  _showStats = false;
                });
              },
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('Stats'),
              selected: _showStats,
              onSelected: (_) {
                setState(() {
                  _showStats = true;
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _showStats
              ? StatsOverviewPanel(scriptName: widget.controller.runtimeType.toString())
              : LogWidget(
                  key: ValueKey(widget.controller.hashCode),
                  controller: widget.controller,
                  title: '日志',
                  enableCollapse: false,
                ),
        ),
      ],
    );
  }
}
