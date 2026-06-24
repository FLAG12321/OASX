import 'package:flutter/material.dart';
import 'package:oasx/model/stats/script_statistics_models.dart';
import 'package:oasx/views/overview/statistics_formatters.dart';

/// 多号统计表格组件。
class MultiAccountStatsTable extends StatelessWidget {
  /// 创建多号统计表格。
  const MultiAccountStatsTable({
    super.key,
    required this.accounts,
    this.labelStyle = MultiAccountLabelStyle.charSvr,
    this.selectedTask,
  });

  /// 账号列表。
  final List<ScriptMultiAccountStatistics> accounts;

  /// 账号名展示规则。
  final MultiAccountLabelStyle labelStyle;

  /// 当前选中的子任务名。
  final String? selectedTask;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: accounts.map((account) {
        return ListTile(
          title: Text(account.displayLabelFor(labelStyle)),
          subtitle: Text('耗时：${formatStatisticsDuration(account.durationSeconds)}'),
          trailing: selectedTask == null || selectedTask!.isEmpty
              ? null
              : Text(
                  '子任务：${formatStatisticsDuration(account.durationForTask(selectedTask!))}',
                ),
        );
      }).toList(),
    );
  }
}
