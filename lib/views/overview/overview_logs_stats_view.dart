import 'package:flutter/material.dart';
import 'package:oasx/views/overview/overview_view.dart';
import 'package:oasx/views/overview/stats_overview_panel.dart';

/// 日志菜单承接页：默认显示 Logs，Stats 作为同容器第二标签。
class OverviewLogsStatsView extends StatefulWidget {
  /// 创建日志/统计容器页。
  const OverviewLogsStatsView({
    super.key,
    required this.scriptName,
  });

  /// 当前脚本名。
  final String scriptName;

  @override
  State<OverviewLogsStatsView> createState() => _OverviewLogsStatsViewState();
}

class _OverviewLogsStatsViewState extends State<OverviewLogsStatsView>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    // 中文注释：固定两页标签，默认选中“日志”。
    _tabController = TabController(length: 2, vsync: this);
    // 中文注释：监听标签切换，驱动日志/统计主体内容更新。
    _tabController.addListener(_handleTabChanged);
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  /// 中文注释：标签索引变化时刷新页面，切换日志与统计主体。
  void _handleTabChanged() {
    if (_tabController.indexIsChanging) {
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final Color selectedColor = Theme.of(context).colorScheme.primary;
    final Color unselectedColor =
        Theme.of(context).textTheme.bodyMedium?.color ??
            Theme.of(context).colorScheme.onSurface;
    // 中文注释：index 为 1 时展示统计，否则保持日志（logChild 为 null）。
    final bool showStats = _tabController.index == 1;
    return Overview(
      // 中文注释：将“日志/统计”切换改为真正的标签页形式，保留在日志面板顶部左侧。
      logTopPanelLeading: Theme(
        data: Theme.of(context).copyWith(
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
        ),
        child: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelPadding: const EdgeInsets.symmetric(horizontal: 12),
          indicatorSize: TabBarIndicatorSize.label,
          dividerColor: Colors.transparent,
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          labelColor: selectedColor,
          unselectedLabelColor: unselectedColor,
          indicator: UnderlineTabIndicator(
            borderSide: BorderSide(color: selectedColor, width: 2),
            insets: EdgeInsets.zero,
          ),
          tabs: const [
            Tab(text: '日志'),
            Tab(text: '统计'),
          ],
        ),
      ),
      // 中文注释：Stats 标签隐藏复制、自动滚动、清空等日志操作按钮，仅 Logs 标签展示。
      showLogActions: !showStats,
      // 中文注释：在同一日志面板主体区域内切换日志内容与 Stats 内容。
      logChild:
          showStats ? StatsOverviewPanel(scriptName: widget.scriptName) : null,
    );
  }
}
