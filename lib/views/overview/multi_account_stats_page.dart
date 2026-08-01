import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:oasx/config/translation/i18n_content.dart';
import 'package:oasx/model/stats/script_statistics_models.dart';
import 'package:oasx/views/overview/multi_account_stats_chart.dart';
import 'package:oasx/views/overview/multi_account_stats_labels.dart';
import 'package:oasx/views/overview/multi_account_stats_table.dart';
import 'package:oasx/views/overview/statistics_formatters.dart';

/// 排序方向。
enum _SortDirection { none, asc, desc }

/// 多账号统计独立全屏页。
///
/// 覆盖整个屏幕，提供概览徽章、柱状图、会话筛选、子任务对比、列勾选表格与行展开。
/// 数据源复用传入的 [ScriptStatisticsDay] 快照，本页不重新拉取 dates/day snapshot。
class MultiAccountStatsPage extends StatefulWidget {
  /// 创建多账号统计页。
  const MultiAccountStatsPage({
    super.key,
    required this.statisticsDay,
    this.initialDateKey,
    this.initialSessionIndex,
  });

  /// 已加载的统计快照，本页只读消费。
  final ScriptStatisticsDay statisticsDay;

  /// 进入时携带的日期 key，用于标题展示。
  final String? initialDateKey;

  /// 进入时携带的会话索引。
  final int? initialSessionIndex;

  @override
  State<MultiAccountStatsPage> createState() => _MultiAccountStatsPageState();
}

class _MultiAccountStatsPageState extends State<MultiAccountStatsPage> {
  /// 当前柱状图指标。
  MultiStatsChartMetric _chartMetric = MultiStatsChartMetric.duration;

  /// 账号显示名组合规则。
  MultiAccountLabelStyle _labelStyle = MultiAccountLabelStyle.charSvr;

  /// 单选的子任务名（null = 总耗时等指标；非空 = 子任务耗时对比）。
  String? _selectedTask;

  /// 当前选择的会话索引，null 表示全天。
  int? _selectedSessionIndex;

  /// 排序方向。
  _SortDirection _sortDirection = _SortDirection.none;

  /// 柱子宽度。
  double _barWidth = 80;

  /// 柱子间隔。
  double _barGap = 12;

  /// GetStorage key：显示名组合。
  static const String _labelStyleKey = 'multi_stats_label_style';

  /// GetStorage key：单选子任务。
  static const String _selectedTaskKey = 'multi_stats_selected_task';

  /// GetStorage key：排序方向。
  static const String _sortDirectionKey = 'multi_stats_sort_dir';

  /// GetStorage key：柱子宽度。
  static const String _barWidthKey = 'multi_stats_bar_width';

  /// GetStorage key：柱子间隔。
  static const String _barGapKey = 'multi_stats_bar_gap';

  @override
  void initState() {
    super.initState();
    final storage = GetStorage();
    final storedStyle = storage.read<String>(_labelStyleKey);
    if (storedStyle != null) {
      _labelStyle = MultiAccountLabelStyle.values.firstWhere(
        (s) => s.name == storedStyle,
        orElse: () => MultiAccountLabelStyle.charSvr,
      );
    }
    final storedTask = storage.read<String>(_selectedTaskKey);
    if (storedTask != null && storedTask.isNotEmpty) {
      _selectedTask = storedTask;
      _chartMetric = MultiStatsChartMetric.taskDuration;
    }

    // 恢复排序方向。
    final storedSort = storage.read<String>(_sortDirectionKey);
    if (storedSort != null) {
      _sortDirection = _SortDirection.values.firstWhere(
        (d) => d.name == storedSort,
        orElse: () => _SortDirection.none,
      );
    }

    // 恢复柱宽和间隔。
    _barWidth = storage.read<double>(_barWidthKey) ?? 80;
    _barGap = storage.read<double>(_barGapKey) ?? 12;

    // 中文注释：从 Stats 首页进入时恢复会话索引（build 方法有 session 存在性校验，安全兜底）。
    if (widget.initialSessionIndex != null) {
      _selectedSessionIndex = widget.initialSessionIndex;
    }
  }

  /// 当前快照下的多账号数据，可能为 null（后端无 multi 字段）。
  ScriptMultiStatistics? get _multi => widget.statisticsDay.multi;

  /// 持久化显示名组合。
  void _setLabelStyle(MultiAccountLabelStyle style) {
    setState(() => _labelStyle = style);
    GetStorage().write(_labelStyleKey, style.name);
  }

  /// 持久化排序方向。
  void _setSortDirection(_SortDirection direction) {
    setState(() => _sortDirection = direction);
    GetStorage().write(_sortDirectionKey, direction.name);
  }

  /// 持久化柱子宽度。
  void _setBarWidth(double width) {
    setState(() => _barWidth = width);
    GetStorage().write(_barWidthKey, width);
  }

  /// 持久化柱子间隔。
  void _setBarGap(double gap) {
    setState(() => _barGap = gap);
    GetStorage().write(_barGapKey, gap);
  }

  /// 对账号列表按当前排序方向排序。
  List<ScriptMultiAccountStatistics> _sortedAccounts(
    List<ScriptMultiAccountStatistics> accounts,
  ) {
    if (_sortDirection == _SortDirection.none) {
      return accounts;
    }
    final sorted = List<ScriptMultiAccountStatistics>.of(accounts);
    sorted.sort((a, b) {
      final va = _valueForMetric(a);
      final vb = _valueForMetric(b);
      return _sortDirection == _SortDirection.asc
          ? va.compareTo(vb)
          : vb.compareTo(va);
    });
    return sorted;
  }

  /// 取账号当前指标值。
  double _valueForMetric(ScriptMultiAccountStatistics account) {
    return switch (_chartMetric) {
      MultiStatsChartMetric.duration => account.durationSeconds,
      MultiStatsChartMetric.battleCount => account.battleCount.toDouble(),
      MultiStatsChartMetric.errorCount => account.errorCount.toDouble(),
      MultiStatsChartMetric.coopTotal => account.coopTotal.toDouble(),
      MultiStatsChartMetric.taskDuration =>
        account.durationForTask(_selectedTask ?? ''),
      MultiStatsChartMetric.battleAvgDuration =>
        account.battleAvgDurationSeconds,
      MultiStatsChartMetric.battleTotalDuration =>
        account.battleTotalDurationSeconds,
    };
  }

  /// 持久化单选子任务（传 null 表示取消，回到总耗时指标）。
  void _setSelectedTask(String? taskName) {
    setState(() {
      _selectedTask = taskName;
      _chartMetric = (taskName != null && taskName.isNotEmpty)
          ? MultiStatsChartMetric.taskDuration
          : MultiStatsChartMetric.duration;
    });
    GetStorage().write(_selectedTaskKey, taskName ?? '');
  }

  /// 切换会话筛选；null 表示全天。
  void _setSelectedSession(int? sessionIndex) {
    setState(() => _selectedSessionIndex = sessionIndex);
  }

  /// 汇总所有账号出现过的子任务名集合（去重保序）。
  List<String> _collectTaskKeys(List<ScriptMultiAccountStatistics> accounts) {
    final seen = <String>{};
    final result = <String>[];
    for (final account in accounts) {
      for (final name in account.taskKeys) {
        if (seen.add(name)) {
          result.add(name);
        }
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final multi = _multi;
    final dateLabel = widget.initialDateKey ?? widget.statisticsDay.dateKey;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: '返回',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          '${I18n.multiStatsTitle.tr} · $dateLabel',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
      body: multi == null || multi.accounts.isEmpty
          ? Center(
              child: Text(
                I18n.multiStatsNoData.tr,
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            )
          : _buildBody(context, multi),
    );
  }

  /// 页面主体：概览 + 工具条 + 柱状图 + 表格。
  Widget _buildBody(BuildContext context, ScriptMultiStatistics multi) {
    // 中文注释：会话索引做存在性校验，非法值回退全天。
    final sessionIndex = multi.sessions
            .any((session) => session.index == _selectedSessionIndex)
        ? _selectedSessionIndex
        : null;
    final viewData =
        filterMultiAccountSessionData(multi: multi, sessionIndex: sessionIndex);
    final accounts = viewData.accounts;
    if (accounts.isEmpty) {
      return Center(
        child: Text(
          I18n.multiStatsNoData.tr,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }
    final allTaskKeys = _collectTaskKeys(accounts);
    // 中文注释：切换到不包含当前子任务的会话时，自动退出子任务对比，避免下拉与图表状态不一致。
    final effectiveSelectedTask = _selectedTask != null &&
            allTaskKeys.contains(_selectedTask)
        ? _selectedTask
        : null;
    if (effectiveSelectedTask != _selectedTask ||
        (effectiveSelectedTask == null &&
            _chartMetric == MultiStatsChartMetric.taskDuration)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _setSelectedTask(effectiveSelectedTask);
      });
    }
    final sortedAccounts = _sortedAccounts(accounts);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部概览卡片。
          _buildOverview(context, accounts, viewData.totalDurationSeconds),
          const SizedBox(height: 12),
          // 工具条：显示名组合 + 会话筛选 + 子任务单选 + 排序 + 柱宽/间距调节。
          _buildToolbar(
            context,
            allTaskKeys,
            multi.sessions,
            sessionIndex,
            effectiveSelectedTask,
          ),
          const SizedBox(height: 12),
          // 柱状图。
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    I18n.multiStatsMetricCompare.tr,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  _buildMetricSelector(),
                  const SizedBox(height: 12),
                  MultiAccountBarChart(
                    accounts: sortedAccounts,
                    metric: _chartMetric,
                    labelStyle: _labelStyle,
                    taskName: effectiveSelectedTask,
                    barWidth: _barWidth,
                    barGap: _barGap,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 表格。
          MultiAccountStatsTable(
            accounts: accounts,
            labelStyle: _labelStyle,
            selectedTask: effectiveSelectedTask,
          ),
        ],
      ),
    );
  }

  /// 顶部概览徽章：账号数 / 总耗时 / 错误数 / 战斗数。
  Widget _buildOverview(
    BuildContext context,
    List<ScriptMultiAccountStatistics> accounts,
    double totalDuration,
  ) {
    final totalAccounts = accounts.length;
    final totalErrors = accounts.fold<int>(0, (s, a) => s + a.errorCount);
    final totalBattles = accounts.fold<int>(0, (s, a) => s + a.battleCount);

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            _StatBadge(
              label: I18n.multiStatsOverviewAccounts.tr,
              value: totalAccounts.toString(),
              icon: Icons.people_rounded,
              color: const Color(0xFF2563EB),
            ),
            const SizedBox(width: 16),
            _StatBadge(
              label: I18n.multiStatsOverviewDuration.tr,
              value: formatStatisticsDuration(totalDuration),
              icon: Icons.timer_rounded,
              color: const Color(0xFF7C3AED),
            ),
            const SizedBox(width: 16),
            _StatBadge(
              label: I18n.multiStatsOverviewErrors.tr,
              value: totalErrors.toString(),
              icon: Icons.error_outline_rounded,
              color: const Color(0xFFDC2626),
            ),
            const SizedBox(width: 16),
            _StatBadge(
              label: I18n.multiStatsOverviewBattles.tr,
              value: totalBattles.toString(),
              icon: Icons.sports_kabaddi_rounded,
              color: const Color(0xFF16A34A),
            ),
          ],
        ),
      ),
    );
  }

  /// 工具条：显示名组合下拉 + 会话筛选 + 子任务单选下拉 + 排序 + 柱宽/间距调节。
  Widget _buildToolbar(
    BuildContext context,
    List<String> taskKeys,
    List<ScriptMultiSessionRecord> sessions,
    int? sessionIndex,
    String? effectiveSelectedTask,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Wrap(
          spacing: 16,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // 显示名组合。
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  I18n.multiStatsAccountName.tr,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(width: 8),
                _LabelStyleDropdown(
                  value: _labelStyle,
                  onChanged: _setLabelStyle,
                ),
              ],
            ),
            // 会话筛选。
            if (sessions.isNotEmpty)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    I18n.multiStatsTimeRange.tr,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(width: 8),
                  _SessionDropdown(
                    sessions: sessions,
                    selectedIndex: sessionIndex,
                    onChanged: _setSelectedSession,
                  ),
                ],
              ),
            // 子任务单选。
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  I18n.multiStatsTaskCompare.tr,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(width: 8),
                _TaskDropdown(
                  taskKeys: taskKeys,
                  selectedTask: effectiveSelectedTask,
                  onChanged: _setSelectedTask,
                ),
              ],
            ),
            // 排序。
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  I18n.multiStatsSort.tr,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(width: 8),
                _SortDropdown(
                  value: _sortDirection,
                  onChanged: _setSortDirection,
                ),
              ],
            ),
            // 柱宽滑块。
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  I18n.multiStatsBarWidth.tr,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 100,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 7,
                      ),
                    ),
                    child: Slider(
                      value: _barWidth,
                      min: 30,
                      max: 200,
                      divisions: 17,
                      label: '${_barWidth.round()}px',
                      onChanged: _setBarWidth,
                    ),
                  ),
                ),
                SizedBox(
                  width: 32,
                  child: Text(
                    '${_barWidth.round()}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
            ),
            // 间隔滑块。
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  I18n.multiStatsBarGap.tr,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 100,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 7,
                      ),
                    ),
                    child: Slider(
                      value: _barGap,
                      min: 2,
                      max: 40,
                      divisions: 19,
                      label: '${_barGap.round()}px',
                      onChanged: _setBarGap,
                    ),
                  ),
                ),
                SizedBox(
                  width: 32,
                  child: Text(
                    '${_barGap.round()}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 柱状图指标切换器（单选子任务时锁定为子任务耗时，不可切换）。
  Widget _buildMetricSelector() {
    if (_chartMetric == MultiStatsChartMetric.taskDuration) {
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          ChoiceChip(
            label: Text(
              '${formatMultiStatsTaskLabel(_selectedTask ?? '')}'
              '${I18n.multiStatsTaskDurationPrefix.tr}',
              style: const TextStyle(fontSize: 12),
            ),
            selected: true,
            showCheckmark: false,
            onSelected: (_) {},
          ),
          TextButton.icon(
            icon: const Icon(Icons.close_rounded, size: 16),
            label: Text(
              I18n.multiStatsExitTaskCompare.tr,
              style: const TextStyle(fontSize: 12),
            ),
            onPressed: () => _setSelectedTask(null),
          ),
        ],
      );
    }
    final selectableMetrics = MultiStatsChartMetric.values
        .where((m) => m != MultiStatsChartMetric.taskDuration)
        .toList();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: selectableMetrics.map((metric) {
        final selected = metric == _chartMetric;
        return ChoiceChip(
          label: Text(
            _metricLabel(metric),
            style: const TextStyle(fontSize: 12),
          ),
          selected: selected,
          showCheckmark: false,
          visualDensity: VisualDensity.compact,
          onSelected: (_) => setState(() {
            _chartMetric = metric;
          }),
        );
      }).toList(),
    );
  }

  /// 指标名称（用于 ChoiceChip 标签）。
  String _metricLabel(MultiStatsChartMetric metric) {
    return switch (metric) {
      MultiStatsChartMetric.duration => I18n.multiStatsMetricDuration.tr,
      MultiStatsChartMetric.battleCount => I18n.multiStatsMetricBattle.tr,
      MultiStatsChartMetric.errorCount => I18n.multiStatsMetricError.tr,
      MultiStatsChartMetric.coopTotal => I18n.multiStatsMetricCoop.tr,
      MultiStatsChartMetric.taskDuration =>
        I18n.multiStatsMetricTaskDuration.tr,
      MultiStatsChartMetric.battleAvgDuration =>
        I18n.multiStatsBattleAvgDuration.tr,
      MultiStatsChartMetric.battleTotalDuration =>
        I18n.multiStatsBattleTotalDuration.tr,
    };
  }
}

/// 账号显示名组合下拉。
class _LabelStyleDropdown extends StatelessWidget {
  const _LabelStyleDropdown({required this.value, required this.onChanged});

  final MultiAccountLabelStyle value;
  final ValueChanged<MultiAccountLabelStyle> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<MultiAccountLabelStyle>(
        value: value,
        isDense: true,
        items: MultiAccountLabelStyle.values
            .map(
              (style) => DropdownMenuItem(
                value: style,
                child: Text(
                  _label(style),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            )
            .toList(),
        onChanged: (style) {
          if (style != null) {
            onChanged(style);
          }
        },
      ),
    );
  }

  String _label(MultiAccountLabelStyle style) {
    return switch (style) {
      MultiAccountLabelStyle.char => I18n.multiStatsLabelChar.tr,
      MultiAccountLabelStyle.charSvr => I18n.multiStatsLabelCharSvr.tr,
      MultiAccountLabelStyle.charAcc => I18n.multiStatsLabelCharAcc.tr,
      MultiAccountLabelStyle.charAccSvr => I18n.multiStatsLabelCharAccSvr.tr,
    };
  }
}

/// 子任务单选下拉（null = 总耗时，不按子任务对比）。
class _TaskDropdown extends StatelessWidget {
  const _TaskDropdown({
    required this.taskKeys,
    required this.selectedTask,
    required this.onChanged,
  });

  final List<String> taskKeys;
  final String? selectedTask;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final hasSelection = selectedTask != null && selectedTask!.isNotEmpty;
    final items = <DropdownMenuItem<String?>>[
      DropdownMenuItem<String?>(
        value: null,
        child: Text(
          I18n.multiStatsTotalOption.tr,
          style: const TextStyle(fontSize: 13),
        ),
      ),
      ...taskKeys.map(
        (name) => DropdownMenuItem<String?>(
          value: name,
          child: Text(
            formatMultiStatsTaskLabel(name),
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ),
    ];
    // 选中的值不在列表里时回退 null，避免 DropdownButton 报错。
    final validValue =
        hasSelection && taskKeys.contains(selectedTask) ? selectedTask : null;
    return DropdownButtonHideUnderline(
      child: DropdownButton<String?>(
        value: validValue,
        isDense: true,
        items: items,
        onChanged: onChanged,
      ),
    );
  }
}

/// 会话筛选下拉（null = 全天）。
class _SessionDropdown extends StatelessWidget {
  const _SessionDropdown({
    required this.sessions,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<ScriptMultiSessionRecord> sessions;
  final int? selectedIndex;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final validValue =
        sessions.any((session) => session.index == selectedIndex)
            ? selectedIndex
            : null;
    return DropdownButtonHideUnderline(
      child: DropdownButton<int?>(
        value: validValue,
        isDense: true,
        items: [
          DropdownMenuItem<int?>(
            value: null,
            child: Text(
              I18n.multiStatsAllDay.tr,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          ...sessions.map(
            (session) => DropdownMenuItem<int?>(
              value: session.index,
              child: Text(
                _label(session),
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ),
        ],
        onChanged: onChanged,
      ),
    );
  }

  /// 会话文案尽量短，避免工具条过宽。
  String _label(ScriptMultiSessionRecord session) {
    final start = session.startTimeText;
    final time = start.length >= 16 ? start.substring(11, 16) : start;
    return '$time · ${formatStatisticsDuration(session.durationSeconds)}';
  }
}

/// 排序方向下拉。
class _SortDropdown extends StatelessWidget {
  const _SortDropdown({required this.value, required this.onChanged});

  final _SortDirection value;
  final ValueChanged<_SortDirection> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<_SortDirection>(
        value: value,
        isDense: true,
        items: _SortDirection.values
            .map(
              (dir) => DropdownMenuItem(
                value: dir,
                child: Text(_label(dir), style: const TextStyle(fontSize: 13)),
              ),
            )
            .toList(),
        onChanged: (dir) {
          if (dir != null) {
            onChanged(dir);
          }
        },
      ),
    );
  }

  String _label(_SortDirection dir) {
    return switch (dir) {
      _SortDirection.none => I18n.multiStatsSortNone.tr,
      _SortDirection.asc => I18n.multiStatsSortAsc.tr,
      _SortDirection.desc => I18n.multiStatsSortDesc.tr,
    };
  }
}

/// 顶部概览数值标签。
class _StatBadge extends StatelessWidget {
  const _StatBadge({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

