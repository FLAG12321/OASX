import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:oasx/controller/stats/stats_page_controller.dart';
import 'package:oasx/model/stats/script_statistics_models.dart';
import 'package:oasx/views/overview/multi_account_stats_page.dart';
import 'package:oasx/views/overview/statistics_formatters.dart';

/// Stats 概览面板顶部指标下拉支持的指标项。
class _MetricOption {
  const _MetricOption({
    required this.value,
    required this.label,
    required this.isDuration,
  });

  final ScriptStatisticsChartMetric value;
  final String label;
  final bool isDuration;
}

/// Stats 首页面板：承接日期切换、指标切换、任务对比图表、任务明细与多账号入口。
///
/// 本面板自包含绘制，不依赖来源项目的完整图表组件，仅还原其视觉结构与信息层级。
class StatsOverviewPanel extends StatefulWidget {
  /// 创建 Stats 首页面板。
  const StatsOverviewPanel({super.key, required this.scriptName});

  /// 当前脚本名。
  final String scriptName;

  @override
  State<StatsOverviewPanel> createState() => _StatsOverviewPanelState();
}

class _StatsOverviewPanelState extends State<StatsOverviewPanel> {
  /// Stats 编排层，按脚本名持有。
  late final StatsPageController controller;

  /// 当前选中的统计指标。
  ScriptStatisticsChartMetric _metric = ScriptStatisticsChartMetric.totalDuration;

  /// 是否按指标降序排列任务柱条。
  bool _descending = true;

  /// 当前在图表中聚焦的任务名。
  String _focusedTaskName = '';

  /// 指标下拉可选项（自包含中文文案，不依赖来源项目的 I18n key）。
  static const List<_MetricOption> _metricOptions = [
    _MetricOption(
      value: ScriptStatisticsChartMetric.totalDuration,
      label: '总耗时',
      isDuration: true,
    ),
    _MetricOption(
      value: ScriptStatisticsChartMetric.runCount,
      label: '运行次数',
      isDuration: false,
    ),
    _MetricOption(
      value: ScriptStatisticsChartMetric.battleCount,
      label: '战斗次数',
      isDuration: false,
    ),
    _MetricOption(
      value: ScriptStatisticsChartMetric.battleAvgDuration,
      label: '平均战斗耗时',
      isDuration: true,
    ),
    _MetricOption(
      value: ScriptStatisticsChartMetric.avgRunDuration,
      label: '平均单次耗时',
      isDuration: true,
    ),
  ];

  @override
  void initState() {
    super.initState();
    controller = Get.isRegistered<StatsPageController>(tag: widget.scriptName)
        ? Get.find<StatsPageController>(tag: widget.scriptName)
        : Get.put(StatsPageController(), tag: widget.scriptName);
    // 中文注释：Stats 首页首次显示时立即启动快照编排层，并在页面可见期间开启自动刷新。
    unawaited(controller.bootstrap(widget.scriptName));
    controller.startAutoRefresh();
  }

  @override
  void dispose() {
    // 中文注释：离开统计页后立刻停止自动刷新，避免隐藏标签持续轮询。
    controller.stopAutoRefresh();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // 中文注释：首屏或切换日期时使用阻断式加载，占位明确反馈当前状态。
      if (controller.datesLoading.value || controller.statisticsBlockingLoading.value) {
        return const _StatsStateView(
          icon: Icons.hourglass_top_rounded,
          message: '正在加载统计…',
          loading: true,
        );
      }
      final errorMessage = controller.lastErrorMessage.value;
      if (errorMessage.isNotEmpty && controller.statistics.value == null) {
        return _StatsStateView(
          icon: Icons.error_outline_rounded,
          message: errorMessage,
          tone: StatsStateTone.error,
        );
      }
      final statistics = controller.statistics.value;
      if (statistics == null) {
        return _StatsStateView(
          icon: Icons.bar_chart_rounded,
          message: controller.availableDateKeys.isEmpty ? '暂无统计日期' : '暂无统计数据',
        );
      }
      final entries = _sortedEntries(statistics);
      _ensureFocusedTask(entries);
      final detailRuns = _detailRuns(statistics);
      return ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        children: [
          _HeaderSection(controller: controller),
          const SizedBox(height: 12),
          if (controller.hasMultiAccountEntry) ...[
            _MultiAccountEntryCard(
              statistics: statistics,
              onTap: () => _enterMultiAccount(statistics),
            ),
            const SizedBox(height: 12),
          ],
          _MetricFilterRow(
            metric: _metric,
            descending: _descending,
            canSortByTime: _canSortByTime(statistics),
            onMetricChanged: (metric) => setState(() => _metric = metric),
            onToggleSort: () =>
                setState(() => _descending = !_descending),
          ),
          const SizedBox(height: 12),
          _TaskChartCard(
            entries: entries,
            metric: _metric,
            focusedTaskName: _focusedTaskName,
            descending: _descending,
            onSelectTask: (name) => setState(() => _focusedTaskName = name),
          ),
          const SizedBox(height: 12),
          _TaskDetailCard(
            taskName: _focusedTaskName,
            runs: detailRuns,
          ),
        ],
      );
    });
  }

  /// 按当前指标与方向对任务条目排序。
  List<MapEntry<String, ScriptTaskStatistics>> _sortedEntries(
    ScriptStatisticsDay statistics,
  ) {
    final entries = statistics.tasks.entries.where((entry) {
      // 中文注释：战斗类指标隐藏无战斗记录的任务，避免出现 0 柱噪音。
      if (statisticsMetricUsesBattleFilter(_metric)) {
        return entry.value.battleCount > 0;
      }
      return entry.value.runCount > 0;
    }).toList();
    entries.sort((left, right) {
      final compare = left.value
          .metricValueFor(_metric)
          .compareTo(right.value.metricValueFor(_metric));
      if (compare != 0) {
        return _descending ? -compare : compare;
      }
      return left.key.compareTo(right.key);
    });
    return entries;
  }

  /// 保证聚焦的任务名在当前条目集合中始终有效。
  void _ensureFocusedTask(List<MapEntry<String, ScriptTaskStatistics>> entries) {
    final focused = _focusedTaskName.trim();
    final exists = entries.any((entry) => entry.key == focused);
    final next = exists ? focused : (entries.isEmpty ? '' : entries.first.key);
    if (next != _focusedTaskName) {
      // 中文注释：在 build 中改变状态需推迟到下一帧，避免脏帧异常。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _focusedTaskName = next);
        }
      });
    }
  }

  /// 当前选中任务的运行明细，按时间倒序。
  List<ScriptTaskRunRecord> _detailRuns(ScriptStatisticsDay statistics) {
    final focused = _focusedTaskName.trim();
    if (focused.isEmpty) {
      return const [];
    }
    final runs = List<ScriptTaskRunRecord>.from(
      statistics.tasks[focused]?.runs ?? const [],
    );
    runs.removeWhere((run) => !run.hasTimeRange);
    runs.sort((left, right) {
      final leftTime = left.endTime ?? left.startTime;
      final rightTime = right.endTime ?? right.startTime;
      if (leftTime == null && rightTime == null) {
        return 0;
      }
      if (leftTime == null) {
        return 1;
      }
      if (rightTime == null) {
        return -1;
      }
      return rightTime.compareTo(leftTime);
    });
    return runs;
  }

  /// 是否允许按时间排序（依赖任务明细可用）。
  bool _canSortByTime(ScriptStatisticsDay statistics) {
    return statistics.tasks.isNotEmpty;
  }

  /// 进入多账号统计独立页，传入已加载的快照，避免二次拉取。
  void _enterMultiAccount(ScriptStatisticsDay statistics) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MultiAccountStatsPage(
          statisticsDay: statistics,
          initialDateKey: controller.selectedDateKey.value,
        ),
      ),
    );
  }
}

/// 状态视图的色调。
enum StatsStateTone { normal, error }

/// 加载/错误/空态统一占位视图。
class _StatsStateView extends StatelessWidget {
  const _StatsStateView({
    required this.icon,
    required this.message,
    this.loading = false,
    this.tone = StatsStateTone.normal,
  });

  final IconData icon;
  final String message;
  final bool loading;
  final StatsStateTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = tone == StatsStateTone.error
        ? scheme.error
        : scheme.onSurfaceVariant;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading) ...[
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.6),
              ),
              const SizedBox(height: 14),
            ] else ...[
              Icon(icon, size: 36, color: color),
              const SizedBox(height: 10),
            ],
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: color,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 头部：状态图标 + 日期下拉 + 总耗时。
class _HeaderSection extends StatelessWidget {
  const _HeaderSection({required this.controller});

  final StatsPageController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Obx(() {
      final statistics = controller.statistics.value;
      final totalDuration = statistics?.totalRuntimeSeconds ?? 0;
      final isLoading = controller.statisticsLoading.value;
      final tone = isLoading ? scheme.primary : scheme.onSurfaceVariant;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _HeaderStatusIcon(
            loading: isLoading,
            hasData: statistics != null,
            isError: controller.lastErrorMessage.value.isNotEmpty,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _DateDropdown(
              dates: controller.availableDateKeys.toList(),
              selected: controller.selectedDateKey.value,
              onChanged: controller.selectDate,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            formatStatisticsDuration(totalDuration),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: tone,
                ),
          ),
        ],
      );
    });
  }
}

/// 头部状态圆角图标。
class _HeaderStatusIcon extends StatelessWidget {
  const _HeaderStatusIcon({
    required this.loading,
    required this.hasData,
    required this.isError,
  });

  final bool loading;
  final bool hasData;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = isError
        ? scheme.error
        : (loading ? scheme.primary : (hasData ? Colors.teal : scheme.primary));
    final icon = isError
        ? Icons.error_outline_rounded
        : (loading
            ? Icons.hourglass_top_rounded
            : (hasData ? Icons.cloud_done_outlined : Icons.query_stats_rounded));
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Icon(icon, size: 18, color: color),
    );
  }
}

/// 日期下拉选择器。
class _DateDropdown extends StatelessWidget {
  const _DateDropdown({
    required this.dates,
    required this.selected,
    required this.onChanged,
  });

  final List<String> dates;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final options = dates
        .map((dateKey) => _SelectorOption(
              value: dateKey,
              label: formatStatisticsDayLabel(dateKey),
            ))
        .toList(growable: false);
    return _PopupSelector<String>(
      options: options,
      value: selected,
      onChanged: onChanged,
      accent: scheme.primary,
    );
  }
}

/// 多账号统计入口卡片，带头像图标、账号数、总耗时与错误数。
class _MultiAccountEntryCard extends StatelessWidget {
  const _MultiAccountEntryCard({required this.statistics, required this.onTap});

  final ScriptStatisticsDay statistics;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final multi = statistics.multi!;
    final scheme = Theme.of(context).colorScheme;
    final accounts = multi.accounts;
    final totalDuration =
        accounts.fold<double>(0, (sum, acc) => sum + acc.durationSeconds);
    final totalErrors = accounts.fold<int>(0, (sum, acc) => sum + acc.errorCount);
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.groups_rounded, color: scheme.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '多账号统计',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${accounts.length} 个账号  ·  '
                      '总耗时 ${formatStatisticsDuration(totalDuration)}  ·  '
                      '错误 $totalErrors',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// 指标筛选行：指标下拉 + 排序方向切换。
class _MetricFilterRow extends StatelessWidget {
  const _MetricFilterRow({
    required this.metric,
    required this.descending,
    required this.canSortByTime,
    required this.onMetricChanged,
    required this.onToggleSort,
  });

  final ScriptStatisticsChartMetric metric;
  final bool descending;
  final bool canSortByTime;
  final ValueChanged<ScriptStatisticsChartMetric> onMetricChanged;
  final VoidCallback onToggleSort;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final options = _StatsOverviewPanelState._metricOptions
        .map((option) => _SelectorOption(
              value: option.value,
              label: option.label,
            ))
        .toList(growable: false);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          '指标',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
        _PopupSelector<ScriptStatisticsChartMetric>(
          options: options,
          value: metric,
          onChanged: onMetricChanged,
          accent: scheme.primary,
        ),
        const SizedBox(width: 4),
        Text(
          '排序',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
        IconButton(
          tooltip: descending ? '降序' : '升序',
          onPressed: onToggleSort,
          icon: Icon(
            descending ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
            size: 20,
          ),
        ),
      ],
    );
  }
}

/// 弹窗下拉的单一选项。
class _SelectorOption<T> {
  const _SelectorOption({required this.value, required this.label});

  final T value;
  final String label;
}

/// 通用弹窗选择器：边框圆角按钮 + 锚点 PopupMenu。
class _PopupSelector<T> extends StatelessWidget {
  const _PopupSelector({
    required this.options,
    required this.value,
    required this.onChanged,
    required this.accent,
    this.minWidth = 0,
  });

  final List<_SelectorOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;
  final Color accent;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    final resolved = options.where((option) => option.value == value).firstOrNull ??
        options.firstOrNull;
    if (resolved == null) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: minWidth),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _showMenu(context, resolved),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      resolved.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.arrow_drop_down_rounded, size: 20, color: accent),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 打开锚定到当前控件的弹窗菜单。
  Future<void> _showMenu(BuildContext context, _SelectorOption<T> resolved) async {
    final renderBox = context.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (renderBox == null || overlay == null) {
      return;
    }
    final topLeft = renderBox.localToGlobal(Offset.zero, ancestor: overlay);
    final bottomRight = renderBox.localToGlobal(
      renderBox.size.bottomRight(Offset.zero),
      ancestor: overlay,
    );
    final position = RelativeRect.fromRect(
      Rect.fromPoints(topLeft, bottomRight),
      Offset.zero & overlay.size,
    );
    final selected = await showMenu<T>(
      context: context,
      position: position,
      initialValue: resolved.value,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      constraints: const BoxConstraints(maxHeight: 4 * kMinInteractiveDimension),
      items: options
          .map((option) => PopupMenuItem<T>(
                value: option.value,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        option.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (option.value == resolved.value) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.check_rounded, size: 18, color: accent),
                    ],
                  ],
                ),
              ))
          .toList(growable: false),
    );
    if (selected != null && selected != resolved.value) {
      onChanged(selected);
    }
  }
}

/// 任务对比图表卡片：横向柱状条列表，按指标排序，可点击聚焦。
class _TaskChartCard extends StatelessWidget {
  const _TaskChartCard({
    required this.entries,
    required this.metric,
    required this.focusedTaskName,
    required this.descending,
    required this.onSelectTask,
  });

  final List<MapEntry<String, ScriptTaskStatistics>> entries;
  final ScriptStatisticsChartMetric metric;
  final String focusedTaskName;
  final bool descending;
  final ValueChanged<String> onSelectTask;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.leaderboard_rounded, size: 18),
                const SizedBox(width: 6),
                Text(
                  '任务统计对比',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (entries.isEmpty)
              const _EmptyHint(text: '当前指标暂无可对比的任务')
            else ...[
              ...entries.map((entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _TaskBarRow(
                      entry: entry,
                      metric: metric,
                      maxValue: _resolveTaskMaxValue(entries, metric),
                      focused: entry.key == focusedTaskName,
                      onTap: () => onSelectTask(entry.key),
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }
}

/// 单条任务柱条：任务名 + 进度轨道 + 数值徽章。
class _TaskBarRow extends StatelessWidget {
  const _TaskBarRow({
    required this.entry,
    required this.metric,
    required this.maxValue,
    required this.focused,
    required this.onTap,
  });

  final MapEntry<String, ScriptTaskStatistics> entry;
  final ScriptStatisticsChartMetric metric;
  final double maxValue;
  final bool focused;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = statisticsTaskColor(entry.key);
    final value = entry.value.metricValueFor(metric);
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        // 中文注释：柱条长度按同批任务该指标的最大值归一化，保证视觉可比。
        final ratio = maxValue <= 0 ? 0.0 : (value / maxValue).clamp(0.0, 1.0);
        final trackWidth = constraints.maxWidth;
        final barWidth = (trackWidth * ratio).clamp(8.0, trackWidth);
        return Tooltip(
          preferBelow: false,
          message: _tooltipText(),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.key,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: focused ? color : null,
                              fontWeight: focused ? FontWeight.w700 : FontWeight.w500,
                            ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formatStatisticsMetricByType(value, metric),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: focused ? color : scheme.onSurface,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 12,
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        width: barWidth,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: focused ? 0.95 : 0.72),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: focused ? color : color.withValues(alpha: 0.4),
                            width: focused ? 1.3 : 1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 鼠标悬浮时展示的任务汇总信息。
  String _tooltipText() {
    return '总耗时：${formatStatisticsDuration(entry.value.totalDurationSeconds)}\n'
        '运行次数：${entry.value.runCount}\n'
        '战斗次数：${entry.value.battleCount}\n'
        '平均战斗耗时：${formatStatisticsDuration(entry.value.battleAvgDurationSeconds)}\n'
        '平均单次耗时：${formatStatisticsDuration(entry.value.avgRunDurationSeconds)}';
  }
}

/// 任务明细卡片：聚焦任务的每次运行记录列表。
class _TaskDetailCard extends StatelessWidget {
  const _TaskDetailCard({required this.taskName, required this.runs});

  final String taskName;
  final List<ScriptTaskRunRecord> runs;

  @override
  Widget build(BuildContext context) {
    if (taskName.trim().isEmpty) {
      return const _EmptyHint(text: '点击上方任务条以查看运行明细');
    }
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.history_rounded, size: 18, color: statisticsTaskColor(taskName)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '运行明细：$taskName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (runs.isEmpty)
              const _EmptyHint(text: '该任务暂无可用的时间明细')
            else
              ...List.generate(runs.length, (index) {
                final serial = runs.length - index;
                return Padding(
                  padding: EdgeInsets.only(bottom: index == runs.length - 1 ? 0 : 8),
                  child: _RunDetailRow(
                    taskName: taskName,
                    run: runs[index],
                    serialNumber: serial,
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

/// 单条运行明细：序号 + 时间区间 + 战斗信息 + 时长。
class _RunDetailRow extends StatelessWidget {
  const _RunDetailRow({
    required this.taskName,
    required this.run,
    required this.serialNumber,
  });

  final String taskName;
  final ScriptTaskRunRecord run;
  final int serialNumber;

  @override
  Widget build(BuildContext context) {
    final color = statisticsTaskColor(taskName);
    final scheme = Theme.of(context).colorScheme;
    final hasBattle = run.battleCount > 0;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$serialNumber',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatStatisticsClockTimeRange(run.startTime, run.endTime),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  hasBattle
                      ? '战斗 ${run.battleCount} 场  ·  均耗 ${formatStatisticsDuration(run.battleAvgDurationSeconds)}'
                      : '无战斗记录',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            formatStatisticsDuration(run.durationSeconds),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

/// 空态小提示。
class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
      ),
    );
  }
}

/// 计算一批任务在指定指标下的最大值，用于柱条横向归一化。
double _resolveTaskMaxValue(
  List<MapEntry<String, ScriptTaskStatistics>> entries,
  ScriptStatisticsChartMetric metric,
) {
  if (entries.isEmpty) {
    return 0;
  }
  return entries
      .map((entry) => entry.value.metricValueFor(metric))
      .reduce((current, value) => current > value ? current : value);
}
