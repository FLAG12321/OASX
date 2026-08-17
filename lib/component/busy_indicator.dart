import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:oasx/config/translation/i18n_content.dart';

/// 「等待后端响应」中间态的通用表现层。
///
/// 前端多处动作点一下就要等后端往返（脚本启停、配置增删改、参数落盘），
/// 原实现全部没有中间反馈：用户看不出按键是否生效，会重复点击。
/// 这里集中承载两种形态，避免在每个调用点各写一遍动画：
///
/// - [BusyTransition]：把某块内容在「常态」与「转圈」之间淡入淡出切换，
///   用于按钮图标（脚本启停）与字段旁的小指示（参数落盘）；
/// - [runWithBusyOverlay]：动作在对话框确认后才发起、没有控件能承载 busy 态时，
///   用不可关闭的进度遮罩表达「正在处理」（配置新建/复制/重命名/删除）。

/// busy 与常态之间的淡入淡出切换；busy 时显示与原内容同尺寸的转圈。
class BusyTransition extends StatelessWidget {
  const BusyTransition({
    super.key,
    required this.busy,
    required this.child,
    this.size = 20,
    this.duration = const Duration(milliseconds: 250),
  });

  final bool busy;
  final Widget child;

  /// 转圈的边长，需与被替换内容的视觉尺寸对齐，避免切换时布局跳动
  final double size;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      // busy 与常态可能渲染出同类型 widget，必须显式给 key，
      // 否则 AnimatedSwitcher 认为没换 child 而不触发过渡
      child: busy
          ? SizedBox(
              key: const ValueKey('busy'),
              width: size,
              height: size,
              child: const CircularProgressIndicator(strokeWidth: 2),
            )
          : KeyedSubtree(key: const ValueKey('idle'), child: child),
    );
  }
}

/// 在等待 [action] 期间盖一层不可关闭的进度遮罩，结束后自动移除。
///
/// 适用于对话框确认后才发起请求的动作：此时对话框已关闭，没有按钮能承载 busy 态。
/// 无论成功还是抛错都会关闭遮罩，异常继续向上抛给调用方。
Future<T> runWithBusyOverlay<T>(
  Future<T> Function() action, {
  String? label,
}) async {
  Get.dialog(
    BusyOverlay(label: label ?? I18n.config_processing.tr),
    barrierDismissible: false,
    // 遮罩自带淡入，避免瞬时完成的请求闪一下硬切
    transitionDuration: const Duration(milliseconds: 150),
  );
  try {
    return await action();
  } finally {
    // isDialogOpen 判空：action 内部若已关闭路由，这里不能再多退一层
    if (Get.isDialogOpen ?? false) Get.back();
  }
}

/// [runWithBusyOverlay] 使用的进度遮罩内容，单独导出便于 widget 测试直接构造。
class BusyOverlay extends StatelessWidget {
  const BusyOverlay({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              if (label != null && label!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    label!,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
