import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:oasx/config/translation/i18n_content.dart';
import 'package:oasx/model/stats/script_statistics_models.dart';
import 'package:oasx/views/overview/statistics_formatters.dart';

/// 多号统计指标类型。
enum MultiStatsChartMetric {
  /// 总耗时。
  duration,

  /// 战斗次数。
  battleCount,

  /// 错误数。
  errorCount,

  /// 协作数。
  coopTotal,

  /// 单个子任务耗时（配合 taskName）。
  taskDuration,

  /// 战斗均耗时（秒）。
  battleAvgDuration,

  /// 战斗总耗时（秒）。
  battleTotalDuration,
}

/// 多号统计纵向柱状图。
///
/// 自包含绘制：左侧固定 Y 轴刻度列、右侧横向滚动柱体区、ShaderMask 边缘渐隐。
class MultiAccountBarChart extends StatelessWidget {
  /// Y 轴左侧留白宽度，为刻度标签留出显示空间，避免柱体遮挡标签。
  static const _kYAxisPaddingWidth = 23.0;

  /// 图表顶部留白，避免柱体最大值时顶到图表顶部边界。
  static const _kChartTopPadding = 16.0;

  /// X 轴标签区域高度。
  static const _kAxisHeight = 28.0;

  /// 柱状图绘制区域高度（增大以保证 Y 轴刻度完整显示不截断）。
  static const _kChartHeight = 180.0;

  /// 扣除顶部留白后的有效绘制高度（柱体 / 网格线 / Y 轴刻度均基于此高度缩放）。
  static const _kEffectiveChartHeight = _kChartHeight - _kChartTopPadding;

  /// 创建柱状图。
  const MultiAccountBarChart({
    super.key,
    required this.accounts,
    required this.metric,
    this.labelStyle = MultiAccountLabelStyle.charSvr,
    this.taskName,
    this.barWidth = 80,
    this.barGap = 12,
  });

  /// 已排序的账号列表。
  final List<ScriptMultiAccountStatistics> accounts;

  /// 当前指标。
  final MultiStatsChartMetric metric;

  /// 账号显示名组合规则。
  final MultiAccountLabelStyle labelStyle;

  /// 当 metric 为 [MultiStatsChartMetric.taskDuration] 时，指定对比的子任务名。
  final String? taskName;

  /// 柱子宽度（所有柱子一致）。
  final double barWidth;

  /// 柱子之间的间隔。
  final double barGap;

  @override
  Widget build(BuildContext context) {
    if (accounts.isEmpty) {
      return const SizedBox.shrink();
    }

    final maxVal = accounts.fold<double>(
      0,
      (prev, acc) => math.max(prev, _valueForAccount(acc)),
    );
    if (maxVal <= 0) {
      // 全部为零时显示空柱占位。
      return SizedBox(
        height: _kChartHeight + _kAxisHeight,
        child: Center(
          child: Text(
            metric == MultiStatsChartMetric.taskDuration
                ? I18n.multiStatsChartNoTaskData.tr
                : I18n.multiStatsChartNoData.tr,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }

    // 中文注释：Y 轴固定 4 个刻度（0、x/3、2x/3、x），x 由最大值按数量级向上取整并凑到 3 的倍数。
    final axisMax = _resolveAxisMax(maxVal);
    final interval = axisMax / 3;

    // 计算 Y 轴刻度值列表：0、interval、2*interval、axisMax，共 4 个刻度。
    final ticks = <double>[0, interval, interval * 2, axisMax];

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        // 滚动区可用宽度 = 总宽减去左侧 Y 轴固定列宽度。
        final scrollAvailableWidth = availableWidth - _kYAxisPaddingWidth;
        // 每个账号占据的横向空间（柱宽 + 间隔）。
        final slotWidth = barWidth + barGap;
        // 中文注释：滚动区内容宽度 = 取可用宽度与所有柱子所需宽度的较大值。
        // 柱体 Row 和 X 轴 Row 左侧各有一个 20px 前导留白。
        final scrollContentWidth = math.max(
          scrollAvailableWidth,
          accounts.length * slotWidth + barGap + 20,
        );

        return SizedBox(
          width: availableWidth,
          // 中文注释：Row 左侧为固定 Y 轴刻度列，右侧为横向滚动绘图区。
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 中文注释：Y 轴刻度标签固定列——不随柱状图横向滚动。
              _buildFixedYAxis(
                context,
                axisMax,
                ticks,
                Theme.of(context).textTheme.labelSmall,
              ),
              // 中文注释：柱状图横向滚动区，ShaderMask 在左右边缘 10px 渐隐至透明。
              Expanded(
                child: ShaderMask(
                  shaderCallback: (Rect bounds) {
                    // 中文注释：左右各 10px 渐隐，柱体淡出至透明露出背景色。
                    final edgeRatio = bounds.width > 0 ? 10.0 / bounds.width : 0.0;
                    return LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: const [
                        Colors.transparent,
                        Colors.white,
                        Colors.white,
                        Colors.transparent,
                      ],
                      stops: [0.0, edgeRatio, 1.0 - edgeRatio, 1.0],
                    ).createShader(bounds);
                  },
                  blendMode: BlendMode.dstIn,
                  // 中文注释：滚动区用 ClipRect 裁剪超出边界内容。
                  child: ClipRect(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      clipBehavior: Clip.hardEdge,
                      child: SizedBox(
                        width: scrollContentWidth,
                        height: _kChartHeight + _kAxisHeight,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            // 网格线（水平参考线，底层，left: 0 覆盖整个滚动区）。
                            ..._buildGridLines(
                              context,
                              scrollContentWidth,
                              axisMax,
                              ticks,
                            ),
                            // 柱体（每根柱底部接地，顶部显示指标数值）。
                            Positioned(
                              left: 0,
                              right: 0,
                              top: 0,
                              bottom: _kAxisHeight,
                              child: _buildBarsRow(context, axisMax),
                            ),
                            // X 轴标签（账号名，底部）。
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              height: _kAxisHeight,
                              child: _buildXAxisRow(context),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Y 轴固定列：刻度标签垂直排列，高度与柱体绘图区一致，不随横向滚动移动。
  Widget _buildFixedYAxis(
    BuildContext context,
    double axisMax,
    List<double> ticks,
    TextStyle? labelStyle,
  ) {
    // 中文注释：刻度文本可用宽度 = 列宽 - 右侧 4px 间距。
    const textMaxWidth = _kYAxisPaddingWidth - 4.0;
    return SizedBox(
      width: _kYAxisPaddingWidth,
      height: _kChartHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: ticks.map((tick) {
          final ratio = axisMax > 0 ? tick / axisMax : 0.0;
          final bottom = _kEffectiveChartHeight * ratio;
          return Positioned(
            left: 0,
            bottom: bottom - 6, // 中文注释：微调使文本与网格线对齐。
            width: _kYAxisPaddingWidth,
            child: ConstrainedBox(
              // 中文注释：约束刻度文本最大宽度，配合 FittedBox 动态缩小避免换行。
              constraints: const BoxConstraints(maxWidth: textMaxWidth),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  useDurationAxis
                      ? _formatAxisDurationLabel(tick)
                      : tick.toInt().toString(),
                  maxLines: 1,
                  softWrap: false,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// 水平参考线（仅网格线，不含 Y 轴标签），覆盖整个滚动区宽度。
  List<Widget> _buildGridLines(
    BuildContext context,
    double width,
    double axisMax,
    List<double> ticks,
  ) {
    return ticks.map((tick) {
      final ratio = axisMax > 0 ? tick / axisMax : 0.0;
      // 中文注释：网格线相对滚动区 Stack 底部定位，需叠加 X 轴标签区高度，
      // 使 0 刻度与柱体底部持平，其余刻度按 ratio 等间距上移。
      final bottom = _kAxisHeight + _kEffectiveChartHeight * ratio;
      return Positioned(
        left: 0, // 中文注释：从 0 开始，不再需要 Y 轴标签区偏移。
        right: 0,
        bottom: bottom,
        child: Container(
          height: 1,
          color: Theme.of(context)
              .colorScheme
              .outlineVariant
              .withValues(alpha: 0.35),
        ),
      );
    }).toList();
  }

  /// 柱体 Row：每根柱体底部接地，顶部显示当前指标数值。
  Widget _buildBarsRow(BuildContext context, double axisMax) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end, // 中文注释：柱体底部接地对齐。
      children: [
        // 中文注释：柱体前导留白 20px —— 第一个柱体距滚动区起点 20px。
        const SizedBox(width: 20),
        ...accounts.map((account) {
          final val = _valueForAccount(account);
          final ratio = axisMax > 0 ? val / axisMax : 0.0;
          final color = _colorForAccount(account);
          return Padding(
            padding: EdgeInsets.only(right: barGap),
            // 中文注释：Column 包裹柱顶数值 + 柱体 Tooltip，底部接地。
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 中文注释：柱体顶部数值标签，按指标类型格式化（时长/次数）。
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: SizedBox(
                    width: barWidth,
                    child: Text(
                      _formatValue(val),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontSize: 9, // 中文注释：小字号避免遮挡柱体。
                          ),
                    ),
                  ),
                ),
                Tooltip(
                  preferBelow: false,
                  // 中文注释：子任务消耗视图复用总耗时 tooltip 样式，避免专用多行 hover 明细触发布局抖动。
                  message: '${account.displayLabelFor(labelStyle)}\n'
                      '${_metricLabel()}：${_formatValue(val)}\n'
                      '${I18n.multiStatsBattleSummary.trParams({
                        'battleCount': '${account.battleCount}',
                        'total': formatStatisticsDuration(
                            account.battleTotalDurationSeconds),
                        'avg': formatStatisticsDuration(
                            account.battleAvgDurationSeconds),
                      })}',
                  child: Container(
                    width: barWidth,
                    height: (_kEffectiveChartHeight * ratio)
                        .clamp(4.0, _kEffectiveChartHeight),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.82),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(6),
                      ),
                      border: Border.all(color: color, width: 1),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
        // 末尾占位抵消最后一个 gap。
        SizedBox(width: barGap),
      ],
    );
  }

  /// X 轴标签 Row：显示各账号名称。
  Widget _buildXAxisRow(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        // 中文注释：X 轴前导留白 20px —— 第一个柱体标签距滚动区起点 20px。
        const SizedBox(width: 20),
        ...accounts.map((account) {
          return Padding(
            padding: EdgeInsets.only(right: barGap),
            child: SizedBox(
              width: barWidth,
              child: Text(
                account.displayLabelFor(labelStyle),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          );
        }),
        SizedBox(width: barGap),
      ],
    );
  }

  /// 取账号指标值。
  double _valueForAccount(ScriptMultiAccountStatistics account) {
    return switch (metric) {
      MultiStatsChartMetric.duration => account.durationSeconds,
      MultiStatsChartMetric.battleCount => account.battleCount.toDouble(),
      MultiStatsChartMetric.errorCount => account.errorCount.toDouble(),
      MultiStatsChartMetric.coopTotal => account.coopTotal.toDouble(),
      MultiStatsChartMetric.taskDuration =>
        account.durationForTask(taskName ?? ''),
      MultiStatsChartMetric.battleAvgDuration =>
        account.battleAvgDurationSeconds,
      MultiStatsChartMetric.battleTotalDuration =>
        account.battleTotalDurationSeconds,
    };
  }

  /// 格式化指标值。
  String _formatValue(double value) {
    if (useDurationAxis) {
      return formatStatisticsDuration(value);
    }
    return value.toInt().toString();
  }

  /// 中文注释：Y 轴刻度用时简化格式——有 h 不显示 m/s，有 m 不显示 s，数字向上取整。
  String _formatAxisDurationLabel(double seconds) {
    if (seconds <= 0) {
      return '0s';
    }
    if (seconds >= 3600) {
      final hours = (seconds / 3600).ceil();
      return '${hours}h';
    }
    if (seconds >= 60) {
      final minutes = (seconds / 60).ceil();
      return '${minutes}m';
    }
    final secs = seconds.ceil();
    return '${secs}s';
  }

  /// 指标中文名。
  String _metricLabel() {
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

  /// 取账号颜色。
  Color _colorForAccount(ScriptMultiAccountStatistics account) {
    const palette = <Color>[
      Color(0xFF2563EB),
      Color(0xFFDC2626),
      Color(0xFF16A34A),
      Color(0xFFD97706),
      Color(0xFF7C3AED),
      Color(0xFF0891B2),
    ];
    return palette[account.account.hashCode.abs() % palette.length];
  }

  /// 计算 Y 轴最大值 x：固定 4 个刻度（0、x/3、2x/3、x）。
  ///
  /// 时长类指标按数量级自动选单位（秒/分/时），把最大值向上取整到该单位的整数 n，
  /// 再把 n 向上补到 3 的倍数，最后乘回单位秒数。例如 5h5m5s → 小时 → 6h。
  /// 计数类指标单位为「个」，直接把最大值向上取整并补到 3 的倍数。
  double _resolveAxisMax(double maxValue) {
    if (maxValue <= 0) {
      return 3.0;
    }
    final unit = _axisUnitSeconds(maxValue);
    final count = (maxValue / unit).ceil();
    // 中文注释：把单位个数向上补到 3 的倍数，确保 interval = x/3 是整数个单位。
    final aligned = count + ((3 - (count % 3)) % 3);
    return aligned * unit;
  }

  /// 按数量级选择 Y 轴取整单位（秒）：<1 分按秒，<1 时按分，否则按时。
  double _axisUnitSeconds(double maxValue) {
    if (useDurationAxis) {
      if (maxValue < 60) {
        return 1; // 秒。
      }
      if (maxValue < 3600) {
        return 60; // 分。
      }
      return 3600; // 时。
    }
    return 1; // 计数类指标单位为「个」。
  }

  /// 是否为时长类指标（决定刻度单位与标签是否按时长格式化）。
  bool get useDurationAxis =>
      metric == MultiStatsChartMetric.duration ||
      metric == MultiStatsChartMetric.taskDuration ||
      metric == MultiStatsChartMetric.battleAvgDuration ||
      metric == MultiStatsChartMetric.battleTotalDuration;
}
