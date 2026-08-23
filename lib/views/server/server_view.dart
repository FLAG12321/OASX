library server;

import 'package:expansion_tile_group/expansion_tile_group.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:oasx/component/log/log_mixin.dart';
import 'package:oasx/component/log/log_widget.dart';
import 'dart:io';
import 'package:styled_widget/styled_widget.dart';
// code_editor 已移除，使用原生 TextField 替代

import 'package:oasx/config/translation/i18n_content.dart';
import 'package:oasx/controller/server/updater_controller.dart';
import 'package:oasx/service/server_launcher.dart';
import 'package:oasx/utils/platform_utils.dart';
import 'package:oasx/views/layout/appbar.dart';
import 'package:oasx/views/server/auto_start_settings.dart';
import 'package:oasx/views/server/updater_panel.dart';
import 'package:oasx/controller/settings.dart';

part './deploy_view.dart';
part '../../controller/server/server_controller.dart';

/// 服务页。折叠面板组 + 服务启动日志，右下角两个 FAB（启动更新 / 启动 server）。
///
/// 为什么是 StatefulWidget：折叠面板的程序化展开依赖 [GlobalKey] 跨 rebuild 稳定。
/// 若 key 建在 build() 里，每次重建都会换新 key，ExpansionTileGroup 的
/// didUpdateWidget 会重新生成内部 key 列表，FAB 触发的展开就会失效。
class ServerView extends StatefulWidget {
  const ServerView({Key? key}) : super(key: key);

  @override
  State<ServerView> createState() => _ServerViewState();
}

class _ServerViewState extends State<ServerView> {
  // 四个面板各自的 expansionKey：既供 FAB 程序化展开，也供手风琴互斥收起。
  // ExpansionTileCard 把它透传给内部 ExpansionTileCore 作 key，故可直接调
  // currentState.expand()/collapse()。key 必须是 State 字段而非 build() 内
  // 局部变量，否则每次重建换新 key，FAB 触发的展开会失效。
  final _pathKey = GlobalKey<ExpansionTileCoreState>();
  final _deployKey = GlobalKey<ExpansionTileCoreState>();
  final _autoStartKey = GlobalKey<ExpansionTileCoreState>();
  final _updaterKey = GlobalKey<ExpansionTileCoreState>();

  /// 当前实际渲染的面板 key，顺序与 _body() 中的排列一致。
  /// 自启动面板仅桌面渲染，未渲染的 key 其 currentState 为 null，调用无副作用。
  List<GlobalKey<ExpansionTileCoreState>> get _panelKeys => [
        _pathKey,
        _deployKey,
        if (PlatformUtils.isDesktop) _autoStartKey,
        _updaterKey,
      ];

  /// 手风琴互斥：展开某项时收起其余项。
  ///
  /// 为什么不用 ExpansionTileGroup 的 ToggleType.expandOnlyCurrent：该组件
  /// initState 会对每个 child 调 copyWith() 注入自己的 onExpansionChanged，而
  /// ExpansionTileItem.copyWith 硬编码 `return ExpansionTileItem(...)`
  /// （包内 expansion_tile_item.dart:560，非虚函数、子类无法覆写），
  /// 会把 .card 子类降级成基类 —— ExpansionTileCard.build() 里的 Card 外壳
  /// 因此永不渲染，面板只剩页面底色，与服务启动日志的 Card 不一致。
  /// 互斥自己管只需下面几行，换来四个面板用上与日志完全同款的真 Card。
  ///
  /// 无需防递归：collapse() 会以 expanded=false 回调，调用方已用 if 过滤。
  void _collapseOthers(GlobalKey<ExpansionTileCoreState> expanded) {
    for (final key in _panelKeys) {
      if (key != expanded) key.currentState?.collapse();
    }
  }

  /// 展开指定折叠项并收起其余项。
  ///
  /// 显式补一次 _collapseOthers：目标项已展开时 _setExpanded 会提前 return
  /// 而不触发 onExpansionChanged，光靠回调链收不起其余项。
  void _expandOnly(GlobalKey<ExpansionTileCoreState> key) {
    key.currentState?.expand();
    _collapseOthers(key);
  }

  /// 服务页五个框（四个折叠面板 + 服务启动日志）的统一标题样式。
  ///
  /// 比 titleMedium 默认的 16 大一号（17）。不用 titleLarge：那档是 22/w400，
  /// 字号跳 6px 且字重反而变轻，标题会又大又淡、层级反转；这里只动字号、
  /// 保留 w500。日志那一框在 LogWidget.TopLogPanel 里用同样的值。
  ///
  /// 注意折叠态面板高度由 ListTile 的 56px 最小高度决定，与本字号无关
  /// （实测 16/17/18 折叠高度都是 56.0）——想压缩折叠高度只能动
  /// isDefaultVerticalPadding，但那会掉到 24px 且把标题缩进从 16 改成 8，
  /// 会破坏刚对齐好的五框缩进，故不采用。
  static TextStyle? panelTitleStyle(BuildContext context) =>
      Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 17);

  /// 面板内文字整体放大量，与标题「大一号」同步。
  /// 与 UpdaterPanel._sizeBump 保持一致。
  static const double panelContentBump = 1;

  /// 给面板内容套一层 DefaultTextStyle 统一抬升字号。
  ///
  /// 面板内大量控件是不带 style 的裸 Text（状态文字、帮助说明、按钮标签），
  /// 逐处补 style 必然漏改，用一处接线覆盖整棵子树。
  static Widget bumpContent(BuildContext context, Widget child) {
    final inherited = DefaultTextStyle.of(context).style;
    return DefaultTextStyle(
      style: inherited.copyWith(
          fontSize: (inherited.fontSize ?? 14) + panelContentBump),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildPlatformAppBar(context, isCollapsed: false),
      floatingActionButton: _actionButtons(),
      body: _body(),
    );
  }

  Widget _body() {
    return LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
      ServerController serverController = Get.find<ServerController>();
      return SingleChildScrollView(
          child: Column(
        // 面板与日志 Card 的底部 margin 10 一致，纵向节奏统一
        spacing: 10,
        children: [
          // 直接排列 ExpansionTileCard 而不套 ExpansionTileGroup：
          // 后者的 copyWith 会把 .card 降级成基类、Card 外壳失效（详见 _collapseOthers）
          path(context),
          deploy(constraints.maxHeight - 200, context),
          // OASX自启动设置：位于「服务启动配置」与「服务启动日志」之间。
          // 仅桌面渲染（AutoStartService 只在桌面注册）
          if (PlatformUtils.isDesktop) autoStart(context),
          // 更新器：与其它配置面板同级。放在服务页而非 Home→Updater 的原因是
          // 那个二级菜单来自 server 的 /home/home_menu，server 没起就点不到；
          // 而本页是独立路由，server 未启动也能进，更新完可直接在同页启动 server。
          updater(context),
          LogWidget(
                  key: ValueKey(serverController.hashCode),
                  controller: serverController,
                  title: I18n.setup_log.tr)
              .constrained(height: constraints.maxHeight - 200)
        ],
      ).padding(right: 10, left: 10));
    });
  }

  // 返回类型是 ExpansionTileCard（而非基类 ExpansionTileItem）：只有子类
  // build() 才带 Card 外壳，静态类型标成基类会让降级问题无法被类型系统发现
  ExpansionTileCard path(BuildContext context) {
    Widget path = GetX<ServerController>(builder: (controller) {
      return <Widget>[
        // 这是面板内部的字段标签，不是面板标题：保持 titleMedium 比
        // panelTitleStyle 低一级，否则会与外层折叠标题同字号、层级塌陷
        Text(I18n.root_path_server.tr,
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(
          width: 10,
        ),
        // 用 SelectableText 让根目录可以选中复制：排查路径问题时要把它贴给
        // 别人，或粘到资源管理器里打开，普通 Text 一个字都取不出来。
        // 外面套 Expanded：SelectableText 不像 Text 那样能被 Row 直接压缩，
        // 长路径会直接溢出（Row 给的是无界宽度约束）。
        Expanded(child: SelectableText(controller.rootPathServer.value)),
        TextButton(
            onPressed: () async {
              String? selectedDirectory =
                  await FilePicker.platform.getDirectoryPath();
              if (selectedDirectory == null) {
                // User canceled the picker
                return;
              }
              controller.updateRootPathServer(selectedDirectory);
            },
            child: Text(I18n.select_root_path_server.tr))
      ].toRow();
    });
    Widget pass = GetX<ServerController>(builder: (controller) {
      return <Widget>[
        controller.rootPathAuthenticated.value
            ? const Icon(Icons.check_circle, color: Colors.green)
            : const Icon(Icons.error, color: Colors.red),
        Text(
          controller.rootPathAuthenticated.value
              ? I18n.root_path_correct.tr
              : I18n.root_path_incorrect.tr,
          // 这行就是本面板的标题（图标 + 状态文字），与其余四框标题同款
          style: panelTitleStyle(context),
        ),
      ].toRow();
    });

    return ExpansionTileCard(
      expansionKey: _pathKey,
      initiallyExpanded: false,
      // 展开时收起其余面板，替代 ExpansionTileGroup 的 expandOnlyCurrent
      onExpansionChanged: (expanded) {
        if (expanded) _collapseOthers(_pathKey);
      },
      title: pass,
      children: [
        bumpContent(context, path),
        bumpContent(context, Text(I18n.root_path_server_help.tr)),
      ],
    );
  }

  ExpansionTileCard deploy(double maxHeight, BuildContext context) {
    return ExpansionTileCard(
      expansionKey: _deployKey,
      initiallyExpanded: false,
      onExpansionChanged: (expanded) {
        if (expanded) _collapseOthers(_deployKey);
      },
      title: Text(I18n.setup_deploy.tr, style: panelTitleStyle(context)),
      children: [
        SingleChildScrollView(
          child: code(maxHeight - 50),
        ).constrained(height: maxHeight)
      ],
    );
  }

  // 「更新器」折叠面板，样式与同组其它面板及服务启动日志一致；
  // 标题用 panelTitleStyle 与同组其它面板同级，面板内部区块降一级（见 UpdaterPanel）
  ExpansionTileCard updater(BuildContext context) {
    return ExpansionTileCard(
      expansionKey: _updaterKey,
      initiallyExpanded: false,
      onExpansionChanged: (expanded) {
        if (expanded) _collapseOthers(_updaterKey);
      },
      // 默认 children 居中会让内容水平居中，显式左对齐
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      childrenPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      title: Text(I18n.updater.tr, style: panelTitleStyle(context)),
      children: const [
        UpdaterPanel(),
      ],
    );
  }

  // 「OASX自启动设置」折叠面板，样式与同组其它面板一致；
  // 内容区抽在 auto_start_settings.dart，便于独立 widget 测试
  ExpansionTileCard autoStart(BuildContext context) {
    return ExpansionTileCard(
      expansionKey: _autoStartKey,
      initiallyExpanded: false,
      onExpansionChanged: (expanded) {
        if (expanded) _collapseOthers(_autoStartKey);
      },
      // 默认 children 居中会让裸 Text 水平居中，显式左对齐
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      childrenPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      title:
          Text(I18n.oasxAutoStartSettings.tr, style: panelTitleStyle(context)),
      children: const [
        AutoStartSettingsContent(),
      ],
    );
  }

  /// 右下角操作区：启动更新 + 启动 server，纵向排列、样式一致。
  ///
  /// 两个 FAB 都必须显式设 heroTag：同屏多个 FloatingActionButton 若共用默认
  /// tag，Hero 会因「multiple heroes share the same tag」直接抛异常崩溃。
  Widget _actionButtons() {
    return GetX<ServerController>(builder: (controller) {
      // 根目录不合法时更新器与 server 都跑不了，整个操作区隐藏，
      // 与此前「路径没过校验就不给启动按钮」的行为保持一致
      if (!controller.rootPathAuthenticated.value) {
        return const SizedBox(width: 100, height: 100);
      }
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 手动更新在左、启动服务在右：更新是低频操作放外侧，启动是主操作
          updateButton(),
          const SizedBox(width: 12),
          startServerButton(),
        ],
      );
    });
  }

  /// 启动更新按钮：展开更新器面板（同组其余自动收起）并立即开始更新。
  ///
  /// 先展开再启动，否则面板收着时用户看不到自己触发的更新在跑什么。
  Widget updateButton() {
    return GetX<UpdaterController>(
        init: UpdaterController.ensure(),
        builder: (updaterController) {
          final running = updaterController.isRunning;
          final busy = updaterController.isBusy;
          return FloatingActionButton(
            heroTag: 'UPDATE',
            tooltip: I18n.execute_update.tr,
            // 更新中禁用（onPressed: null）：并发跑 git 会互相踩 .git/*.lock
            onPressed: (running || busy)
                ? null
                : () {
                    _expandOnly(_updaterKey);
                    updaterController.startUpdate();
                  },
            child: running
                // 进行中显示转圈，让用户在面板收起时也能看出更新还在跑
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : const Icon(Icons.system_update_rounded),
          );
        });
  }

  /// 启动 server 按钮：展开服务启动日志并启动。
  ///
  /// 展开的是「服务启动日志」而不是「服务启动配置」——用户点启动后要看的是
  /// 跑起来的输出，不是 deploy.yaml。日志不是折叠面板，它是 LogWidget 自己的
  /// collapseLog 开关，所以走 controller 而不是 _expandOnly。
  ///
  /// 同时收起全部配置面板：日志高度是 maxHeight-200，配置面板展开着会把它挤到
  /// 视口外，用户看不见自己刚启动的输出。
  Widget startServerButton() {
    return GetX<UpdaterController>(
      init: UpdaterController.ensure(),
      builder: (updaterController) => FloatingActionButton(
        heroTag: 'START_SERVER',
        tooltip: I18n.setup_log.tr,
        // 更新/info/保存操作期间禁止启动 Server，避免相互杀进程或修改 Git。
        onPressed: updaterController.isBusy
            ? null
            : () {
                final controller = Get.find<ServerController>();
                // 收起所有配置面板，给日志腾出视口
                for (final key in _panelKeys) {
                  key.currentState?.collapse();
                }
                // 日志可能被用户手动收起过，启动前确保它是展开的
                controller.collapseLog.value = false;
                controller.run();
              },
        child: const Icon(Icons.auto_mode_rounded),
      ),
    );
  }

  Widget code(double maxHeight) {
    return GetX<ServerController>(builder: (controller) {
      final TextEditingController textController = TextEditingController(
        text: controller.deployContent.value,
      );
      return Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xff1e1e1e),
                borderRadius: BorderRadius.circular(8),
              ),
              child: TextField(
                controller: textController,
                maxLines: null,
                expands: true,
                style: const TextStyle(
                  color: Color(0xffd4d4d4),
                  // 显式声明而非跟随主题：这是 yaml 代码编辑框，等宽是它自身的
                  // 语义要求，不能依赖全局主题恰好是等宽。
                  // （原值 'monospace' 在 Windows 上不是有效字体名，Flutter 会
                  // 静默回退到默认字体，等宽效果其实从未生效）
                  fontFamily: 'CascadiaCode',
                  // 与面板其余内容同步放大一号（14 + panelContentBump）
                  fontSize: 14 + panelContentBump,
                ),
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.all(12),
                  border: InputBorder.none,
                  hintText: I18n.deployEditHint.tr,
                  hintStyle: const TextStyle(color: Color(0xff6b6b6b)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.save),
            label: Text(I18n.save.tr),
            onPressed: () {
              controller.writeDeploy(textController.text);
            },
          ),
        ],
      );
    });
  }
}
