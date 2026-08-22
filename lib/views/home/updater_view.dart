import 'package:flutter/material.dart';

import 'package:oasx/views/server/updater_panel.dart';

/// Home → Updater 页面。
///
/// 实际内容全在 [UpdaterPanel]，与服务页「更新器」折叠面板是同一份实现、
/// 同一个 UpdaterController，因此两处的状态与日志始终一致。
///
/// 注意本页的可达性受限：Home 的二级菜单来自 server 的 /home/home_menu，
/// server 未启动时菜单拉不到，这个入口点不进来。server 未启动时请走
/// 服务页（/server）里的「更新器」折叠面板——那里是独立路由，不依赖 server。
class UpdaterView extends StatelessWidget {
  const UpdaterView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // SizedBox.expand 撑满宿主的 Center，使内容顶部对齐而非垂直居中，
    // 避免远程区加载/失败时内容高度变化导致整个页面位置跳动
    return SizedBox.expand(
      child: const SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: UpdaterPanel(),
        ),
      ),
    );
  }
}
