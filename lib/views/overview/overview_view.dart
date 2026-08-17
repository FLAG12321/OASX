library overview;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:oasx/api/api_client.dart';
import 'package:oasx/api/script_log_models.dart';
import 'package:oasx/component/log/log_mixin.dart';
import 'package:oasx/component/log/log_widget.dart';
import 'package:oasx/component/busy_indicator.dart';
import 'package:oasx/model/script_model.dart';
import 'package:oasx/service/script_service.dart';

import 'package:styled_widget/styled_widget.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';

import 'package:oasx/views/nav/view_nav.dart';
import 'package:oasx/config/translation/i18n_content.dart';

part '../../controller/overview/overview_controller.dart';
part '../../controller/overview/taskitem_model.dart';
part './taskitem_view.dart';

class Overview extends StatelessWidget {
  const Overview({
    Key? key,
    this.logTopPanelLeading,
    this.logChild,
    this.showLogActions = true,
  }) : super(key: key);

  // 中文注释：允许外部向日志面板头部注入自定义前导控件，例如 Logs/Stats 切换。
  final Widget? logTopPanelLeading;

  // 中文注释：允许外部复用日志面板外壳，但切换主体内容区域。
  final Widget? logChild;

  // 中文注释：Stats 标签传 false，用于隐藏复制、自动滚动、清空日志操作按钮。
  final bool showLogActions;

  @override
  Widget build(BuildContext context) {
    NavCtrl navController = Get.find<NavCtrl>();
    OverviewController overviewController =
        Get.find<OverviewController>(tag: navController.selectedScript.value);
    if (context.mediaQuery.orientation == Orientation.portrait) {
      // 竖方向
      return SingleChildScrollView(
        child: <Widget>[
          _SchedulerWidget(controller: overviewController),
          _RunningWidget(controller: overviewController),
          _PendingWidget(controller: overviewController),
          _WaitingWidget(controller: overviewController)
              .constrained(maxHeight: 200),
          LogWidget(
                  key: ValueKey(overviewController.hashCode),
                  controller: overviewController,
                  title: I18n.log.tr,
                  enableCopy: showLogActions,
                  enableAutoScroll: showLogActions,
                  enableClear: showLogActions,
                  enableCollapse: false,
                  topPanelLeading: logTopPanelLeading,
                  child: logChild)
              .constrained(maxHeight: 500)
              .marginOnly(left: 10, top: 10, right: 10)
        ].toColumn(),
      );
    } else {
      //横方向
      return <Widget>[
        // 左边
        <Widget>[
          _SchedulerWidget(controller: overviewController),
          _RunningWidget(controller: overviewController),
          _PendingWidget(controller: overviewController),
          Expanded(child: _WaitingWidget(controller: overviewController)),
        ].toColumn().constrained(width: 300),
        // 右边
        LogWidget(
                key: ValueKey(overviewController.hashCode),
                controller: overviewController,
                title: I18n.log.tr,
                enableCopy: showLogActions,
                enableAutoScroll: showLogActions,
                enableClear: showLogActions,
                enableCollapse: false,
                topPanelLeading: logTopPanelLeading,
                child: logChild)
            .marginOnly(right: 10)
            .expanded()
      ].toRow();
    }
  }
}

class _WaitingWidget extends StatelessWidget {
  const _WaitingWidget({
    required this.controller,
  });

  final OverviewController controller;

  @override
  Widget build(BuildContext context) {
    return <Widget>[
      Text(I18n.waiting.tr,
          textAlign: TextAlign.left,
          style: Theme.of(context).textTheme.titleMedium),
      const Divider(),
      Expanded(child: Obx(() {
        return ListView.builder(
            itemBuilder: (context, index) =>
                TaskItemView(controller.scriptModel.waitingTaskList[index]),
            itemCount: controller.scriptModel.waitingTaskList.length);
      }))
    ]
        .toColumn(
          crossAxisAlignment: CrossAxisAlignment.start,
        )
        .paddingAll(8)
        .card(margin: const EdgeInsets.fromLTRB(10, 0, 10, 10));
  }
}

class _PendingWidget extends StatelessWidget {
  const _PendingWidget({
    required this.controller,
  });

  final OverviewController controller;

  @override
  Widget build(BuildContext context) {
    return <Widget>[
      Text(I18n.pending.tr,
          textAlign: TextAlign.left,
          style: Theme.of(context).textTheme.titleMedium),
      const Divider(),
      SizedBox(
          height: 140,
          child: Obx(() {
            return ListView.builder(
                itemBuilder: (context, index) =>
                    TaskItemView(controller.scriptModel.pendingTaskList[index]),
                itemCount: controller.scriptModel.pendingTaskList.length);
          }))
    ]
        .toColumn(crossAxisAlignment: CrossAxisAlignment.start)
        .padding(top: 8, bottom: 0, left: 8, right: 8)
        .card(margin: const EdgeInsets.fromLTRB(10, 0, 10, 10));
  }
}

class _RunningWidget extends StatelessWidget {
  const _RunningWidget({
    required this.controller,
  });

  final OverviewController controller;

  @override
  Widget build(BuildContext context) {
    return <Widget>[
      Text(I18n.running.tr,
          textAlign: TextAlign.left,
          style: Theme.of(context).textTheme.titleMedium),
      const Divider(),
      Obx(() {
        return TaskItemView(controller.scriptModel.runningTask.value);
      })
    ]
        .toColumn(crossAxisAlignment: CrossAxisAlignment.start)
        .padding(top: 8, bottom: 0, left: 8, right: 8)
        .card(margin: const EdgeInsets.fromLTRB(10, 0, 10, 10));
  }
}

class _SchedulerWidget extends StatelessWidget {
  const _SchedulerWidget({
    required this.controller,
  });

  final OverviewController controller;

  @override
  Widget build(BuildContext context) {
    return <Widget>[
      Text(I18n.scheduler.tr,
          textAlign: TextAlign.left,
          style: Theme.of(context).textTheme.titleMedium),
      <Widget>[
        Obx(() {
          final state = controller.scriptModel.state.value;
          // 状态图标切换加淡入淡出：中间态与终态之间若硬跳变，
          // 用户会怀疑「按键到底有没有生效」
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            // 不同状态可能渲染同类型 widget（starting/stopping 都是 SpinKitPulse），
            // 必须按状态显式给 key，否则不触发过渡
            child: KeyedSubtree(
              key: ValueKey(state),
              child: switch (state) {
                ScriptState.running => const SpinKitChasingDots(
                    color: Colors.green,
                    size: 22,
                  ),
                ScriptState.inactive =>
                  const Icon(Icons.donut_large, size: 26, color: Colors.grey),
                ScriptState.warning =>
                  const SpinKitDoubleBounce(color: Colors.orange, size: 26),
                ScriptState.updating => const Icon(
                    Icons.browser_updated_rounded,
                    size: 26,
                    color: Colors.blue),
                // 前端伪状态：正在等后端启停响应（启动含最长约 5s 的子进程握手）。
                // 用与 stopping 一致的中性灰脉冲，避免绿色被误读为「已运行成功」
                ScriptState.starting =>
                  const SpinKitPulse(color: Colors.grey, size: 26),
                ScriptState.stopping =>
                  const SpinKitPulse(color: Colors.grey, size: 26),
              },
            ),
          );
        }),
        Obx(() {
          final state = controller.scriptModel.state.value;
          final busy = state.isBusy;
          return IconButton(
            // 中间态禁用，直接消除「看似没生效 → 重复点击」的根因
            onPressed: busy ? null : () => controller.toggleScript(),
            tooltip: busy
                ? (state == ScriptState.starting
                        ? I18n.script_starting
                        : I18n.script_stopping)
                    .tr
                : null,
            icon: BusyTransition(
              busy: busy,
              child: const Icon(Icons.power_settings_new_rounded),
            ),
            isSelected: state == ScriptState.running,
          );
        }),
      ].toRow(mainAxisAlignment: MainAxisAlignment.center)
    ]
        .toRow(mainAxisAlignment: MainAxisAlignment.spaceBetween)
        .constrained(height: 48)
        .paddingOnly(left: 8, right: 8)
        .card(margin: const EdgeInsets.fromLTRB(10, 0, 10, 10));
  }
}
