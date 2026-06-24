import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:oasx/views/args/args_view.dart';
import 'package:oasx/views/home/home_view.dart';
import 'package:oasx/views/home/tool_view.dart';
import 'package:oasx/views/home/updater_view.dart';
import 'package:oasx/views/nav/view_nav.dart';
import 'package:oasx/views/overview/overview_logs_stats_view.dart';

Widget content() {
  return GetX<NavCtrl>(builder: (controller) {
    return switch ([
      controller.selectedScript.value,
      controller.selectedMenu.value
    ]) {
      ['Home', 'Home'] => const HomeView(),
      ['Home', 'Updater'] => const UpdaterView(),
      ['Home', 'Tool'] => const ToolView(),
      // 日志菜单入口位置保留：脚本配置切换后默认二级菜单仍是 Overview，
      // 当前改由 Logs / Stats 容器页承接，但不新增 Stats 顶级菜单。
      [String name, 'Overview'] => OverviewLogsStatsView(
          controller: Get.find(tag: name),
        ),
      _ => const Args(),
    };
  });
}
