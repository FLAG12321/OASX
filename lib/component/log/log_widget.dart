import 'dart:async';
import 'dart:math';

import 'package:easy_rich_text/easy_rich_text.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:oasx/service/log_font_service.dart';
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
    widget.controller.preserveViewportAfterPrepend =
        _preserveViewportAfterPrepend;
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
                      // 比 titleMedium 默认的 16 大一号（17），与服务页四个折叠面板
                      // 标题保持同款（见 ServerView.panelTitleStyle）。
                      // 不用 titleLarge：那档是 22/w400，字号跳 6px 且字重反而
                      // 变轻，标题会又大又淡、层级反转。
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontSize: 17)),
                ),
              if (enableAutoScroll ?? true) _autoScrollButton(),
              if (enableCopy ?? true) _copyButton(),
              if (enableClear ?? true) _deleteButton(),
              if (enableCollapse ?? true) _collapseButton(),
            ],
            // 左内边距 16 对齐折叠面板标题：面板标题走 ListTile 默认
            // contentPadding(horizontal:16)，实测文字落在 Card 左边缘 +16
            // （必须拿真实 ExpansionTileCard 量——裸 ListTile 没有 leading 图标，
            // 几何不同会量出 20，据此设值反而错开 4px）。
            // 日志标题原来只有 paddingAll(8)，比面板浅 8px。
            // 右侧保持 8：那侧是图标按钮，IconButton 自带 8px 内边距，
            // 补到 16 会让按钮离边缘过远。
          )
              .padding(left: 16, right: 8, top: 8, bottom: 8)
              .constrained(height: 48),
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
    // 正常应用启动时服务已在 initService 注册；保留组件独立渲染能力，
    // 未注册的测试/嵌入场景仍按默认 LatoLato 显示。
    final logFontService =
        Get.isRegistered<LogFontService>() ? Get.find<LogFontService>() : null;

    return Card(
      margin: const EdgeInsets.fromLTRB(0, 0, 0, 10),
      child: NotificationListener<UserScrollNotification>(
        onNotification: (notification) {
          onUserScroll();
          return false;
        },
        child: Obx(() {
          final fontFamily =
              logFontService?.fontFamily ?? LogFontPreset.latoLato.fontFamily;
          final fontSize =
              logFontService?.fontSize ?? LogFontService.defaultFontSize;
          final listView = ListView.builder(
            controller: scrollController,
            // 日志保持虚拟化且由 SliverVariedExtentList 预知每行高度，避免跳转
            // 到长列表末尾时从头构建所有行。普通行与分隔行的高度分别固定：后者
            // 多出的 8px 正好对应上下各 4px 的呼吸空间，不会拉大普通日志行距。
            //
            // 长行不靠这里折行，而是在入库侧就切好：LogMixin.addLog 用
            // normalizeLogLines 把载荷按分隔线宽度（80 列）归一成多个元素，
            // 一个元素恰好一行（见 log_line_width.dart）。后端普通日志为保护
            // CJK 行首已改成整行推出，子进程 stdout 同样无宽度约束；两者都在
            // 入库时折好，所以 maxLines:1 不会吃掉内容，
            // 「一元素一行」不变式保持，视口补偿与 offset↔index 换算仍可按
            // itemExtentBuilder 的确定高度执行。
            itemCount: controller.logs.length,
            itemExtentBuilder: (index, _) =>
                _itemExtent(controller.logs[index], fontSize),
            itemBuilder: (context, index) {
              final line = controller.logs[index];
              return Padding(
                padding: EdgeInsets.symmetric(
                  vertical: _isDividerLine(line)
                      ? _dividerLineVerticalPadding
                      : _normalLineVerticalPadding,
                ),
                child: EasyRichText(
                  _trimMillis(line),
                  patternList: _buildPatterns(),
                  selectable: true,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  defaultStyle: _selectStyle(context, fontFamily, fontSize),
                ),
              );
            },
          );
          // 左内边距 16 与上方标题、以及折叠面板的正文缩进对齐；
          // 其余三边保持 10，不改动纵向节奏与右侧滚动条留白
          final list = Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
            child: listView,
          );
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

  /// 只把行首毫秒三位截成一位：`12:34:56.789` → `12:34:56.7`。
  ///
  /// 正则锁定「8 列级别 + |时间戳|」前缀，正文里的 `08:10:20.999` 必须原样保留；
  /// 只在渲染层截断，不动 controller.logs，所以复制日志与历史加载仍保留原始精度。
  static final RegExp _millisPattern =
      RegExp(r'^(.{8}\|\d{2}:\d{2}:\d{2}\.\d)\d{2}\|');
  static final RegExp _dividerPattern = RegExp(r'(══*══)|(──*──)');

  static const _normalLineVerticalPadding = 1.0;
  static const _dividerLineVerticalPadding = 5.0;

  /// 与现有 12px 日志的实测 22px 行高保持一致；更大的字号按相同文本比例
  /// 增长。分隔行只额外增加其本身的上下 padding，不影响普通行。
  static double _itemExtent(String line, int fontSize) {
    const textHeightFactor = 1.5;
    const safetyExtent = 4.0;
    final normalExtent = fontSize * textHeightFactor + safetyExtent;
    return _isDividerLine(line)
        ? normalExtent +
            2 * (_dividerLineVerticalPadding - _normalLineVerticalPadding)
        : normalExtent;
  }

  static bool _isDividerLine(String line) => _dividerPattern.hasMatch(line);

  /// 必须用 replaceFirstMapped：Dart 的 replaceFirst 第二参是字面量字符串，
  /// 不解析 `$1` 反向引用（与 JS 不同），会把 `$1` 原样写进日志。
  static String _trimMillis(String line) => line.replaceFirstMapped(
        _millisPattern,
        (m) => '${m[1]}|',
      );

  List<EasyRichTextPattern> _buildPatterns() {
    return [
      // 级别一律不补空格：后端 flutter_formatter 已用 %(levelname)-8s 把级别
      // 补成定宽 8 列（见 OAS module/logger.py），前端再补就变成「8 + 补数」的
      // 二次补位，让 INFO(12) > ERROR(11) > WARNING(9) > CRITICAL(8) 列宽反而不等。
      // 选择等宽预设时，-8s 自身即可成列（Cascadia 所有字形同宽 0.5859em），
      // 与 GuiRule 按 GUI_RULE_WIDTH 渲染的 RESTART 分隔线也逐列对齐。
      const EasyRichTextPattern(
        targetString: 'INFO',
        style: TextStyle(
          color: Color.fromARGB(255, 55, 109, 136),
          fontFeatures: [FontFeature.tabularFigures()],
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
      ),
      const EasyRichTextPattern(
        targetString: 'CRITICAL',
        style: TextStyle(
          color: Colors.red,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
      const EasyRichTextPattern(
        // 毫秒已被 _trimMillis 截成一位，正则同步改 \d{1}，
        // 否则匹配不上、时间戳会丢掉青色高亮
        targetString: r'(\d{2}:\d{2}:\d{2}\.\d)',
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

  /// 日志正文样式。字体仅在此局部覆盖全局主题，
  /// 行高由 ListView 的 itemExtentBuilder 与字号同步计算。
  ///
  /// 字号与字体都只来自 LogFontService：默认 14 对齐 OASX 0.3.3 desktop 的
  /// titleSmall；不跟随全局 ThemeData，服务页标题也不受影响。
  TextStyle _selectStyle(
    BuildContext context,
    String fontFamily,
    int fontSize,
  ) {
    // 从主题取色与兜底链，只覆写日志局部的字号与字族，
    // 保证深浅色主题下前景色与中文 fallback 仍然正确。
    final base = context.mediaQuery.orientation == Orientation.portrait
        ? Theme.of(context).textTheme.bodySmall!
        : Theme.of(context).textTheme.titleSmall!;
    return base.copyWith(fontSize: fontSize.toDouble(), fontFamily: fontFamily);
  }
}
