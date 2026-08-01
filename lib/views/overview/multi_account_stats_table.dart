import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:oasx/config/translation/i18n_content.dart';
import 'package:oasx/model/stats/script_statistics_models.dart';
import 'package:oasx/views/overview/multi_account_stats_labels.dart';
import 'package:oasx/views/overview/statistics_formatters.dart';

/// 多号统计表格的列 key 常量集合，集中管理可勾选列。
class _ColumnKeys {
  static const String account = 'account';
  static const String duration = 'duration';
  static const String switchOk = 'switchOk';
  static const String errorCount = 'errorCount';
  static const String battleCount = 'battleCount';
  static const String coopTotal = 'coopTotal';
  static const String mshopSummary = 'mshopSummary';
  // 中文注释：战斗耗时列 key。
  static const String battleAvgDuration = 'battleAvgDuration';
  static const String battleTotalDuration = 'battleTotalDuration';

  static const String storageKey = 'multi_stats_visible_columns';

  /// 默认可见列。
  static List<String> get defaultColumns => [
        duration,
        switchOk,
        errorCount,
        battleCount,
        coopTotal,
      ];

  /// 所有可选列（不含固定列 account）。
  static List<String> get allOptionalColumns => [
        duration,
        switchOk,
        errorCount,
        battleCount,
        coopTotal,
        mshopSummary,
        // 中文注释：战斗耗时列供用户按需勾选。
        battleAvgDuration,
        battleTotalDuration,
      ];

  /// 列显示名称。
  static String labelFor(String key) {
    return switch (key) {
      account => I18n.multiStatsColumnAccount.tr,
      duration => I18n.multiStatsColumnDuration.tr,
      switchOk => I18n.multiStatsColumnSwitch.tr,
      errorCount => I18n.multiStatsColumnError.tr,
      battleCount => I18n.multiStatsColumnBattle.tr,
      coopTotal => I18n.multiStatsColumnCoop.tr,
      mshopSummary => I18n.multiStatsColumnMshop.tr,
      // 中文注释：战斗耗时列标签使用翻译 key。
      battleAvgDuration => I18n.multiStatsBattleAvgDuration.tr,
      battleTotalDuration => I18n.multiStatsBattleTotalDuration.tr,
      _ => key,
    };
  }

  /// 从账号统计数据列读取值。
  static String valueFor(String key, ScriptMultiAccountStatistics account) {
    return switch (key) {
      duration => formatStatisticsDuration(account.durationSeconds),
      switchOk => account.switchOk == true
          ? '✓'
          : (account.switchOk == false ? '✗' : '-'),
      errorCount => account.errorCount.toString(),
      battleCount => account.battleCount.toString(),
      coopTotal => account.coopTotal.toString(),
      mshopSummary => account.mshopSummary,
      // 中文注释：战斗耗时列取值并格式化。
      battleAvgDuration =>
        formatStatisticsDuration(account.battleAvgDurationSeconds),
      battleTotalDuration =>
        formatStatisticsDuration(account.battleTotalDurationSeconds),
      _ => '-',
    };
  }
}

/// 多号统计可排序字段。
enum MultiStatsSortField {
  /// 账号名。
  displayName,

  /// 耗时。
  duration,

  /// 协作数。
  coopTotal,

  /// 战斗数。
  battleCount,

  /// 错误数。
  errorCount,

  /// 切号状态。
  switchOk,

  /// 单个子任务耗时（配合 selectedTask）。
  taskDuration,

  /// 战斗均耗时。
  battleAvgDuration,

  /// 战斗总耗时。
  battleTotalDuration,
}

/// 多号统计表格组件，支持列勾选、排序与行展开明细。
class MultiAccountStatsTable extends StatefulWidget {
  /// 创建多号统计表格。
  const MultiAccountStatsTable({
    super.key,
    required this.accounts,
    this.labelStyle = MultiAccountLabelStyle.charSvr,
    this.selectedTask,
  });

  /// 账号统计数据列表。
  final List<ScriptMultiAccountStatistics> accounts;

  /// 账号显示名组合规则。
  final MultiAccountLabelStyle labelStyle;

  /// 当前单选的子任务名，非空时表格追加该子任务耗时列。
  final String? selectedTask;

  @override
  State<MultiAccountStatsTable> createState() => _MultiAccountStatsTableState();
}

class _MultiAccountStatsTableState extends State<MultiAccountStatsTable> {
  /// 排序字段。
  MultiStatsSortField _sortField = MultiStatsSortField.displayName;

  /// 是否降序。
  bool _sortDescending = true;

  /// 可见列集合（不含固定列 account）。
  late Set<String> _visibleColumns;

  /// 展开的账号索引。
  final Set<int> _expandedRows = {};

  @override
  void initState() {
    super.initState();
    final storage = GetStorage();
    // GetStorage 返回 List<dynamic>，不能直接强转为 List<String>。
    final storedRaw = storage.read(_ColumnKeys.storageKey);
    final stored = storedRaw is List
        ? storedRaw.cast<String>().toList(growable: false)
        : null;
    _visibleColumns = (stored != null ? Set<String>.from(stored) : {})
      ..retainAll(_ColumnKeys.allOptionalColumns);
    if (_visibleColumns.isEmpty) {
      _visibleColumns = _ColumnKeys.defaultColumns.toSet();
    }
  }

  /// 持久化列勾选状态。
  void _saveColumnVisibility() {
    final storage = GetStorage();
    storage.write(
      _ColumnKeys.storageKey,
      _visibleColumns.toList(growable: false),
    );
  }

  /// 切换列可见性。
  void _toggleColumn(String key) {
    setState(() {
      if (_visibleColumns.contains(key)) {
        // 至少保留一列。
        if (_visibleColumns.length > 1) {
          _visibleColumns.remove(key);
        }
      } else {
        _visibleColumns.add(key);
      }
      _saveColumnVisibility();
    });
  }

  /// 全选列。
  void _selectAllColumns() {
    setState(() {
      _visibleColumns = _ColumnKeys.allOptionalColumns.toSet();
      _saveColumnVisibility();
    });
  }

  /// 重置为默认列。
  void _resetColumns() {
    setState(() {
      _visibleColumns = _ColumnKeys.defaultColumns.toSet();
      _saveColumnVisibility();
    });
  }

  /// 排序后的账号列表。
  List<ScriptMultiAccountStatistics> get _sortedAccounts {
    final sorted = List<ScriptMultiAccountStatistics>.from(widget.accounts);
    final selectedTask = widget.selectedTask;
    sorted.sort((a, b) {
      int cmp;
      switch (_sortField) {
        case MultiStatsSortField.displayName:
          cmp = a
              .displayLabelFor(widget.labelStyle)
              .compareTo(b.displayLabelFor(widget.labelStyle));
          break;
        case MultiStatsSortField.duration:
          cmp = a.durationSeconds.compareTo(b.durationSeconds);
          break;
        case MultiStatsSortField.coopTotal:
          cmp = a.coopTotal.compareTo(b.coopTotal);
          break;
        case MultiStatsSortField.battleCount:
          cmp = a.battleCount.compareTo(b.battleCount);
          break;
        case MultiStatsSortField.errorCount:
          cmp = a.errorCount.compareTo(b.errorCount);
          break;
        case MultiStatsSortField.switchOk:
          cmp = (a.switchOk == true ? 1 : 0).compareTo(
            b.switchOk == true ? 1 : 0,
          );
          break;
        case MultiStatsSortField.taskDuration:
          cmp = a
              .durationForTask(selectedTask ?? '')
              .compareTo(b.durationForTask(selectedTask ?? ''));
          break;
        case MultiStatsSortField.battleAvgDuration:
          cmp =
              a.battleAvgDurationSeconds.compareTo(b.battleAvgDurationSeconds);
          break;
        case MultiStatsSortField.battleTotalDuration:
          cmp = a.battleTotalDurationSeconds
              .compareTo(b.battleTotalDurationSeconds);
          break;
      }
      return _sortDescending ? -cmp : cmp;
    });
    return sorted;
  }

  /// 切换排序字段或方向。
  void _toggleSort(MultiStatsSortField field) {
    setState(() {
      if (_sortField == field) {
        _sortDescending = !_sortDescending;
      } else {
        _sortField = field;
        _sortDescending = true;
      }
    });
  }

  /// 排序箭头指示器。
  String _sortIndicator(MultiStatsSortField field) {
    if (_sortField != field) {
      return '';
    }
    return _sortDescending ? ' ▼' : ' ▲';
  }

  @override
  Widget build(BuildContext context) {
    final sorted = _sortedAccounts;
    final scheme = Theme.of(context).colorScheme;
    final selectedTask = widget.selectedTask;
    // 可见列：固定 account 列 + 已勾选可选列。
    final visibleKeys = [
      _ColumnKeys.account,
      ..._ColumnKeys.allOptionalColumns.where(
        (k) => _visibleColumns.contains(k),
      ),
    ];
    // 单选了子任务时，末尾追加该子任务耗时列。
    final hasTaskColumn = selectedTask != null && selectedTask.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 列勾选控件。
        _buildColumnToggle(context),
        const SizedBox(height: 8),
        // 表格。
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 44,
                dataRowMinHeight: 44,
                dataRowMaxHeight: 44,
                columnSpacing: 20,
                horizontalMargin: 12,
                sortColumnIndex: hasTaskColumn &&
                        _sortField == MultiStatsSortField.taskDuration
                    ? visibleKeys.length
                    : visibleKeys.indexOf(_sortFieldToKey()),
                sortAscending: !_sortDescending,
                columns: [
                  ...visibleKeys.map((key) {
                    final sortField = _keyToSortField(key);
                    return DataColumn(
                      label: Text(
                        '${_ColumnKeys.labelFor(key)}${_sortIndicator(sortField)}',
                        style: Theme.of(context)
                            .textTheme
                            .labelMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      onSort: (_, __) => _toggleSort(sortField),
                    );
                  }),
                  if (hasTaskColumn)
                    DataColumn(
                      label: Text(
                        '$selectedTask${I18n.multiStatsTaskDurationPrefix.tr}'
                        '${_sortIndicator(MultiStatsSortField.taskDuration)}',
                        style: Theme.of(context)
                            .textTheme
                            .labelMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      onSort: (_, __) =>
                          _toggleSort(MultiStatsSortField.taskDuration),
                    ),
                ],
                rows: List.generate(sorted.length, (index) {
                  final account = sorted[index];
                  final isExpanded = _expandedRows.contains(index);
                  return DataRow(
                    onSelectChanged: (_) => setState(() {
                      if (isExpanded) {
                        _expandedRows.remove(index);
                      } else {
                        _expandedRows.add(index);
                      }
                    }),
                    cells: [
                      ...visibleKeys.map((key) {
                        if (key == _ColumnKeys.account) {
                          // 账号列含展开指示和显示名。
                          return DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isExpanded
                                      ? Icons.expand_less_rounded
                                      : Icons.expand_more_rounded,
                                  size: 16,
                                  color: scheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 4),
                                Text(account.displayLabelFor(widget.labelStyle)),
                                const SizedBox(width: 6),
                                Icon(
                                  account.switchOk == true
                                      ? Icons.check_circle_rounded
                                      : Icons.error_outline_rounded,
                                  size: 14,
                                  color: account.switchOk == true
                                      ? Colors.green
                                      : Colors.orange,
                                ),
                              ],
                            ),
                          );
                        }
                        return DataCell(
                          Text(
                            _valueForCell(key, account),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }),
                      if (hasTaskColumn)
                        DataCell(
                          Text(
                            formatStatisticsDuration(
                              account.durationForTask(selectedTask),
                            ),
                          ),
                        ),
                    ],
                  );
                }),
              ),
            ),
          ),
        ),
        // 展开的行详情。
        ...List.generate(sorted.length, (index) {
          if (!_expandedRows.contains(index)) {
            return const SizedBox.shrink();
          }
          final account = sorted[index];
          return _buildExpandedDetail(context, account);
        }),
      ],
    );
  }

  /// 列勾选控件。
  Widget _buildColumnToggle(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              I18n.multiStatsColToggle.tr,
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ..._ColumnKeys.allOptionalColumns.map((key) {
                  final selected = _visibleColumns.contains(key);
                  return FilterChip(
                    label: Text(
                      _ColumnKeys.labelFor(key),
                      style: TextStyle(
                        fontSize: 12,
                        color: selected ? null : scheme.onSurfaceVariant,
                      ),
                    ),
                    selected: selected,
                    showCheckmark: true,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => _toggleColumn(key),
                  );
                }),
                const SizedBox(width: 8),
                TextButton.icon(
                  icon: const Icon(Icons.select_all_rounded, size: 16),
                  label: Text(
                    I18n.selectAll.tr,
                    style: const TextStyle(fontSize: 12),
                  ),
                  onPressed: _selectAllColumns,
                ),
                TextButton.icon(
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: Text(
                    I18n.multiStatsReset.tr,
                    style: const TextStyle(fontSize: 12),
                  ),
                  onPressed: _resetColumns,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 展开行详情：子任务、协作、商店、错误。
  Widget _buildExpandedDetail(
    BuildContext context,
    ScriptMultiAccountStatistics account,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 子任务耗时明细。
          if (account.tasks.isNotEmpty) ...[
            Text(
              I18n.multiStatsDetailTasks.tr,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            ...account.tasks.map((task) {
              final dur = task.durationSeconds ?? 0;
              // 中文注释：是否有战斗耗时数据需要展示。
              final hasBattleInfo = task.battleCount > 0 ||
                  task.battleTotalDurationSeconds > 0 ||
                  task.battleAvgDurationSeconds > 0;
              // 中文注释：子任务 tooltip 补充单次运行的执行次数、开始时间和持续时间。
              final taskStartTime = task.startTime.trim().isEmpty
                  ? I18n.multiStatsUnknown.tr
                  : task.startTime;
              final taskDuration = formatStatisticsDuration(dur);
              return Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Tooltip(
                  message: I18n.multiStatsRunTooltip.trParams({
                    'runs': '1',
                    'start': taskStartTime,
                    'duration': taskDuration,
                  }),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            task.ok
                                ? Icons.check_circle_outline_rounded
                                : Icons.error_outline_rounded,
                            size: 14,
                            color: task.ok ? Colors.green : scheme.error,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              // 中文注释：子任务名通过翻译函数展示，未知值原样显示。
                              formatMultiStatsTaskLabel(task.task),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          Text(
                            taskDuration,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                          ),
                        ],
                      ),
                      // 中文注释：子任务战斗耗时信息，仅在有效数据时展示。
                      if (hasBattleInfo)
                        Padding(
                          padding: const EdgeInsets.only(left: 20, top: 1),
                          child: Text(
                            I18n.multiStatsBattleSummary.trParams({
                              'battleCount': '${task.battleCount}',
                              'total': formatStatisticsDuration(
                                  task.battleTotalDurationSeconds),
                              'avg': formatStatisticsDuration(
                                  task.battleAvgDurationSeconds),
                            }),
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
          ],
          // 协作明细。
          if (account.coops.isNotEmpty) ...[
            Text(
              I18n.multiStatsDetailCoops.tr,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            ...account.coops.map(
              (coop) => Text(
                // 中文注释：协作类型通过翻译函数统一展示。
                '${coop.real ? I18n.multiStatsCoopReal.tr : I18n.multiStatsCoopNormal.tr}'
                '${formatMultiStatsCoopTypeLabel(coop.ctype)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 8),
          ],
          // 商店明细。
          if (account.mshops.isNotEmpty) ...[
            Text(
              I18n.multiStatsDetailMshops.tr,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            ...account.mshops.map(
              (mshop) => Text(
                // 中文注释：商店物品名通过翻译函数统一展示。
                '${formatMultiStatsGoodsLabel(mshop.goods)}'
                '${mshop.price == null ? '' : '(${mshop.price})'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 8),
          ],
          // 错误详情。
          if (account.errors.isNotEmpty) ...[
            Text(
              I18n.multiStatsDetailErrors.tr,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            ...account.errors.map(
              (err) => Text(
                err.displayText,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.error),
              ),
            ),
          ],
          if (account.tasks.isEmpty &&
              account.coops.isEmpty &&
              account.mshops.isEmpty &&
              account.errors.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                I18n.multiStatsDetailEmpty.tr,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }

  /// 取列显示值（协作列/商店列在表格摘要中做中文翻译）。
  String _valueForCell(String key, ScriptMultiAccountStatistics account) {
    if (key == _ColumnKeys.coopTotal) {
      return account.coopTotal > 0
          ? _translatedCoopSummary(account)
          : I18n.multiStatsNotFound.tr;
    }
    if (key == _ColumnKeys.mshopSummary) {
      return _translatedMshopSummary(account);
    }
    return _ColumnKeys.valueFor(key, account);
  }

  /// 将协作摘要转换为中文展示，避免直接显示 gold/jade/sushi 原始值。
  String _translatedCoopSummary(ScriptMultiAccountStatistics account) {
    if (account.coops.isEmpty) {
      return I18n.multiStatsNotFound.tr;
    }
    final counter = <String, int>{};
    for (final coop in account.coops) {
      final key =
          '${coop.real ? I18n.multiStatsCoopReal.tr : I18n.multiStatsCoopNormal.tr}'
          '${formatMultiStatsCoopTypeLabel(coop.ctype)}';
      counter[key] = (counter[key] ?? 0) + 1;
    }
    return counter.entries
        .map((entry) => '${entry.key}×${entry.value}')
        .join(', ');
  }

  /// 将商店摘要转换为中文展示，避免直接显示 gold/jade/sushi 原始值。
  String _translatedMshopSummary(ScriptMultiAccountStatistics account) {
    if (account.mshops.isEmpty) {
      return '-';
    }
    return account.mshops
        .map(
          (item) =>
              '${formatMultiStatsGoodsLabel(item.goods)}${item.price == null ? '' : '(${item.price})'}',
        )
        .join(', ');
  }

  /// 列 key 映射到排序字段。
  MultiStatsSortField _keyToSortField(String key) {
    return switch (key) {
      _ColumnKeys.account => MultiStatsSortField.displayName,
      _ColumnKeys.duration => MultiStatsSortField.duration,
      _ColumnKeys.coopTotal => MultiStatsSortField.coopTotal,
      _ColumnKeys.battleCount => MultiStatsSortField.battleCount,
      _ColumnKeys.errorCount => MultiStatsSortField.errorCount,
      _ColumnKeys.switchOk => MultiStatsSortField.switchOk,
      // 中文注释：战斗耗时列排序映射。
      _ColumnKeys.battleAvgDuration => MultiStatsSortField.battleAvgDuration,
      _ColumnKeys.battleTotalDuration =>
        MultiStatsSortField.battleTotalDuration,
      _ => MultiStatsSortField.displayName,
    };
  }

  /// 当前排序字段对应的列 key。
  String _sortFieldToKey() {
    return switch (_sortField) {
      MultiStatsSortField.displayName => _ColumnKeys.account,
      MultiStatsSortField.duration => _ColumnKeys.duration,
      MultiStatsSortField.coopTotal => _ColumnKeys.coopTotal,
      MultiStatsSortField.battleCount => _ColumnKeys.battleCount,
      MultiStatsSortField.errorCount => _ColumnKeys.errorCount,
      MultiStatsSortField.switchOk => _ColumnKeys.switchOk,
      // 中文注释：战斗耗时列/子任务耗时列为动态追加列，回退 account。
      MultiStatsSortField.taskDuration => _ColumnKeys.account,
      MultiStatsSortField.battleAvgDuration => _ColumnKeys.account,
      MultiStatsSortField.battleTotalDuration => _ColumnKeys.account,
    };
  }
}

