import 'dart:async';
import 'dart:math';

import 'package:easy_rich_text/easy_rich_text.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:styled_widget/styled_widget.dart';
import 'log_mixin.dart';

class LogWidget extends StatefulWidget {
  final LogMixin controller;
  final String title;
  final bool? enableCopy;
  final bool? enableAutoScroll;
  final bool? enableClear;
  final bool? enableCollapse;
  final Widget? topPanelLeading;
  final Widget? topPanelBottomChild;
  final Widget? child;

  const LogWidget({
    super.key,
    required this.controller,
    required this.title,
    this.enableCopy,
    this.enableAutoScroll,
    this.enableClear,
    this.enableCollapse,
    this.topPanelLeading,
    this.topPanelBottomChild,
    this.child,
  });

  @override
  State<StatefulWidget> createState() => _LogWidgetState();
}

class _LogWidgetState extends State<LogWidget> {
  ScrollController? _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController ??= ScrollController(
        initialScrollOffset: widget.controller.savedScrollOffsetVal);
    // 位置调整
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.controller.autoScroll.value) {
        // 自动滚动模式：强制滚动到底部
        _scrollLogs(force: true, scrollOffset: -1);
      } else if (widget.controller.savedScrollOffsetVal > 0) {
        // 非自动滚动模式：恢复到保存的位置
        _scrollLogs(
            force: true, scrollOffset: widget.controller.savedScrollOffsetVal);
      }
    });
    widget.controller.scrollLogs = _scrollLogs;
    // 中文注释：注册 prepend 历史日志后的视口补偿回调。
    widget.controller.preserveViewportAfterPrepend = _preserveViewportAfterPrepend;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TopLogPanel(
          title: widget.title,
          controller: widget.controller,
          enableCopy: widget.enableCopy,
          enableAutoScroll: widget.enableAutoScroll,
          enableClear: widget.enableClear,
          enableCollapse: widget.enableCollapse,
          leading: widget.topPanelLeading,
          bottomChild: widget.topPanelBottomChild,
        ),
        Obx(() => widget.controller.collapseLog.value
            ? const SizedBox.shrink()
            : (widget.child ??
                    LogContent(
                      controller: widget.controller,
                      scrollController: _scrollController!,
                      onUserScroll: _handleUserScroll,
                    ))
                .expanded()),
      ],
    );
  }

  @override
  void didUpdateWidget(covariant LogWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 中文注释：child 从 null 变非 null（如 Logs 切到 Stats）时日志列表即将
    // 被替换离树，先保存阅读位置；反向切回时列表重新挂载但 initState 的
    // 一次性滚动回调早已消耗，需在挂载完成后按同样语义恢复——否则列表
    // 停在最顶端（最老的行），对未运行的脚本没有实时日志来纠正。
    if (oldWidget.child == null && widget.child != null) {
      if (_scrollController != null && _scrollController!.hasClients) {
        widget.controller.saveScrollOffset(_scrollController!.offset);
      }
    } else if (oldWidget.child != null && widget.child == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_scrollController == null || !_scrollController!.hasClients) return;
        // 中文注释：postFrame 时本帧布局已完成，直接同步跳转即可，
        // 不经 _scrollLogs 以免再等一帧（切换场景本就无动画诉求）。
        final position = _scrollController!.position;
        final target = widget.controller.autoScroll.value
            ? position.maxScrollExtent
            : widget.controller.savedScrollOffsetVal
                .clamp(0.0, position.maxScrollExtent)
                .toDouble();
        _scrollController!.jumpTo(target);
      });
    }
  }

  @override
  void deactivate() {
    if (_scrollController != null && _scrollController!.hasClients) {
      widget.controller.saveScrollOffset(_scrollController!.offset);
    }
    super.deactivate();
  }

  @override
  void dispose() {
    if (_scrollController != null && _scrollController!.hasClients) {
      widget.controller.saveScrollOffset(_scrollController!.offset);
    }
    // 中文注释：仅当回调仍指向本 State 时解绑，避免误清其他 LogWidget 的注册。
    if (widget.controller.preserveViewportAfterPrepend ==
        _preserveViewportAfterPrepend) {
      widget.controller.preserveViewportAfterPrepend = null;
    }
    _scrollController?.dispose();
    _scrollController = null;
    super.dispose();
  }

  void _scrollLogs({isJump = false, force = false, scrollOffset = -1}) {
    if (_scrollController == null || !_scrollController!.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController == null || !_scrollController!.hasClients) return;
      // 强制滚动或自动滚动才允许滚动
      if (!force && !widget.controller.autoScroll.value) return;
      final double targetPos = scrollOffset == -1
          ? _scrollController!.position.maxScrollExtent
          : scrollOffset;
      if (isJump) {
        _scrollController!.jumpTo(targetPos);
        return;
      }
      final double currentPos = _scrollController!.offset;
      final double distance = (targetPos - currentPos).abs();
      // 中文注释：超长距离动画会让 SliverList 把途经的每一行都构建一遍
      // （实测 500 行滚到底构建 470 行、37 帧掉帧），直接跳转规避。
      // 阈值用视口相对量以自适应窗口尺寸；阈值内保留平滑动画不影响追尾体验。
      // 不做 animateTo 那样的 whenComplete 底部矫正：跳转后若 extent 仍增长，
      // 由下一次 50ms 计时器的 scrollLogs 或 prepend 视口补偿接管。
      if (distance > _scrollController!.position.viewportDimension * 3) {
        _scrollController!.jumpTo(targetPos);
        return;
      }
      // 使用非线性函数计算动画时间
      // 1000px 约 300ms,10000px 约 1000ms
      int animateMs = (sqrt(distance) * 10).toInt();
      const int minAnimateMs = 100; // 最快速度
      const int maxAnimateMs = 1000; // 最慢速度
      // 限制范围
      animateMs = animateMs.clamp(minAnimateMs, maxAnimateMs);
      // 滚动
      _scrollController!
          .animateTo(targetPos,
              duration: Duration(milliseconds: animateMs),
              curve: Curves.easeOut)
          .whenComplete(() {
        if (_scrollController == null || !_scrollController!.hasClients) return;
        final latestExtent = _scrollController!.position.maxScrollExtent;
        // 矫正滚动位置(最底部或自动滚动且最新位置不同,跳转到新的最底部)
        if ((scrollOffset == -1 || widget.controller.autoScroll.value) &&
            latestExtent > targetPos) {
          _scrollController!.jumpTo(latestExtent);
        }
      });
    });
  }

  // 中文注释：头部行数变化后补偿 offset，保持阅读视口。行高一致（maxLines:1），
  // 用总高度差摊到总行数变化再乘以头部变化行数，排除同一帧底部 append 的高度干扰。
  void _preserveViewportAfterPrepend(int changedCount) {
    if (_scrollController == null || !_scrollController!.hasClients) return;
    final currentOffset = _scrollController!.offset;
    final oldMaxExtent = _scrollController!.position.maxScrollExtent;
    // 中文注释：回调在 controller 变更 logs 之后同步触发，此时布局尚未更新。
    final callTimeCount = widget.controller.logs.length;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController == null || !_scrollController!.hasClients) return;
      final position = _scrollController!.position;
      final totalCountDelta =
          changedCount + (widget.controller.logs.length - callTimeCount);
      if (totalCountDelta == 0) return;
      final perLineExtent =
          (position.maxScrollExtent - oldMaxExtent) / totalCountDelta;
      final compensation = perLineExtent * changedCount;
      if (compensation == 0) return;
      _scrollController!.jumpTo(
          (currentOffset + compensation).clamp(0.0, position.maxScrollExtent));
    });
  }

  void _handleUserScroll() {
    if (_scrollController == null || !_scrollController!.hasClients) return;
    final maxExtent = _scrollController!.position.maxScrollExtent;
    final currentOffset = _scrollController!.offset;

    // 中文注释：接近顶部时请求更早历史日志；默认 controller 不支持时不会触发。
    if (currentOffset <= 80 && widget.controller.canLoadOlderLogs) {
      unawaited(widget.controller.loadOlderLogs());
    }

    // 判断是否在底部（容差80像素）
    final isAtBottom = currentOffset >= (maxExtent - 80);

    // 更新自动滚动状态
    if (isAtBottom && !widget.controller.autoScroll.value) {
      // 用户滚动到底部，开启自动滚动
      widget.controller.autoScroll.value = true;
    } else if (!isAtBottom && widget.controller.autoScroll.value) {
      // 用户向上滚动超过80像素，关闭自动滚动
      widget.controller.autoScroll.value = false;
    }
  }
}

/// 日志顶部操作栏
class TopLogPanel extends StatelessWidget {
  final LogMixin controller;
  final String title;
  final bool? enableCopy;
  final bool? enableAutoScroll;
  final bool? enableClear;
  final bool? enableCollapse;
  final Widget? leading;
  final Widget? bottomChild;

  const TopLogPanel({
    super.key,
    required this.controller,
    required this.title,
    this.enableCopy,
    this.enableAutoScroll,
    this.enableClear,
    this.enableCollapse,
    this.leading,
    this.bottomChild,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(0, 0, 0, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 顶部按钮控制面板
          Row(
            children: [
              if (leading != null)
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: leading!,
                  ),
                )
              else
                Expanded(
                  child: Text(title,
                      textAlign: TextAlign.left,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
              if (enableAutoScroll ?? true) _autoScrollButton(),
              if (enableCopy ?? true) _copyButton(),
              if (enableClear ?? true) _deleteButton(),
              if (enableCollapse ?? true) _collapseButton(),
            ],
          ).paddingAll(8).constrained(height: 48),
          // 底部
          if (bottomChild != null) ...[
            const Divider(height: 1),
            bottomChild!,
          ],
        ],
      ),
    );
  }

  Widget _copyButton() {
    return IconButton(
      icon: const Icon(Icons.content_copy_rounded, size: 18),
      onPressed: () => controller.copyLogs(),
    );
  }

  Widget _autoScrollButton() {
    return Obx(() => IconButton(
          icon: Icon(
            controller.autoScroll.value ? Icons.flash_on : Icons.flash_off,
            size: 20,
          ),
          onPressed: controller.toggleAutoScroll,
        ));
  }

  Widget _deleteButton() {
    return IconButton(
      icon: const Icon(Icons.delete_outlined, size: 20),
      onPressed: () => controller.clearLog(),
    );
  }

  Widget _collapseButton() {
    return Obx(() => IconButton(
          icon: Icon(
            controller.collapseLog.value
                ? Icons.expand_more
                : Icons.expand_less,
            size: 20,
          ),
          onPressed: () => controller.toggleCollapse(),
        ));
  }
}

/// 日志内容区
class LogContent extends StatelessWidget {
  final LogMixin controller;
  final ScrollController scrollController;
  final Function() onUserScroll;

  const LogContent({
    super.key,
    required this.controller,
    required this.scrollController,
    required this.onUserScroll,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(0, 0, 0, 10),
      child: NotificationListener<UserScrollNotification>(
        onNotification: (notification) {
          onUserScroll();
          return false;
        },
        child: Obx(() {
          final list = ListView.builder(
            controller: scrollController,
            // 中文注释：给出等高原型让 SliverList 用常数时间换算 offset↔index，
            // 否则跳转/视口补偿要从头逐行累加高度（实测 500 行滚到底会构建
            // 470 行、单帧冻结数百毫秒）。原型必须与真实行同构且命中高亮
            // pattern：实测 bodySmall 下命中行高 22px、未命中行与普通 Text
            // 仅 18px，取最高形态保证任何真实行不会高于原型而被裁切。
            // 原型只用于量高不参与绘制，但仍会建语义节点，故排除以免屏幕
            // 阅读器读出这条不存在的日志；selectable 必须与真实行保持一致，
            // 否则渲染路径不同会改变行高。
            prototypeItem: ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: EasyRichText(
                  'INFO: 00:00:00.000 prototype\n',
                  patternList: _buildPatterns(),
                  selectable: true,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  defaultStyle: _selectStyle(context),
                ),
              ),
            ),
            itemCount: controller.logs.length,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: EasyRichText(
                controller.logs[index],
                patternList: _buildPatterns(),
                selectable: true,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                defaultStyle: _selectStyle(context),
              ),
            ),
          ).paddingAll(10);
          // 中文注释：仅在没有任何日志可展示时显示占位；懒加载更早窗口 /
          // stale 重建时用户可能正在阅读，不遮挡已有列表。
          if (!controller.historyLoading.value || controller.logs.isNotEmpty) {
            return list;
          }
          // 中文注释：占位叠加而非替换列表——替换会让 ScrollController 失去
          // clients，吞掉 initState 的一次性滚底回调与首批历史的视口补偿。
          // 尺寸与 StatsOverviewPanel 的加载态一致（28×28 + strokeWidth 2.6）。
          // spinner 中心 28×28 会吸收指针事件，但该状态下列表必为空、无可滚动
          // 内容，且日志一到达占位即消失，不影响交互。
          return Stack(
            children: [
              list,
              const Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.6),
                ),
              ),
            ],
          );
        }),
      ),
    ).constrained(width: double.infinity, height: double.infinity);
  }

  List<EasyRichTextPattern> _buildPatterns() {
    return [
      const EasyRichTextPattern(
        targetString: 'INFO',
        style: TextStyle(
          color: Color.fromARGB(255, 55, 109, 136),
          fontFeatures: [FontFeature.tabularFigures()],
        ),
        suffixInlineSpan: TextSpan(
          style: TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
          text: '      ',
        ),
      ),
      const EasyRichTextPattern(
        targetString: 'WARNING',
        style: TextStyle(
          color: Colors.yellow,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
      const EasyRichTextPattern(
        targetString: 'ERROR',
        style: TextStyle(
          color: Colors.red,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
        suffixInlineSpan: TextSpan(
          style: TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
          text: '    ',
        ),
      ),
      const EasyRichTextPattern(
        targetString: 'CRITICAL',
        style: TextStyle(
          color: Colors.red,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
        suffixInlineSpan: TextSpan(text: '   '),
      ),
      const EasyRichTextPattern(
        targetString: r'(\d{2}:\d{2}:\d{2}\.\d{3})',
        style: TextStyle(
          color: Colors.cyan,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
      const EasyRichTextPattern(
        targetString: r'[\{\[\(\)\]\}]',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      const EasyRichTextPattern(
          targetString: 'True', style: TextStyle(color: Colors.lightGreen)),
      const EasyRichTextPattern(
          targetString: 'False', style: TextStyle(color: Colors.red)),
      const EasyRichTextPattern(
          targetString: 'None', style: TextStyle(color: Colors.purple)),
      const EasyRichTextPattern(
        targetString: r'(══*══)|(──*──)',
        style: TextStyle(color: Colors.lightGreen),
      )
    ];
  }

  TextStyle _selectStyle(BuildContext context) {
    return context.mediaQuery.orientation == Orientation.portrait
        ? Theme.of(context).textTheme.bodySmall!
        : Theme.of(context).textTheme.titleSmall!;
  }
}
