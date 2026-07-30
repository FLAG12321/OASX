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
import 'package:oasx/service/server_launcher.dart';
import 'package:oasx/utils/platform_utils.dart';
import 'package:oasx/views/layout/appbar.dart';
import 'package:oasx/views/server/auto_start_settings.dart';
import 'package:oasx/controller/settings.dart';

part './deploy_view.dart';
part '../../controller/server/server_controller.dart';

class ServerView extends StatelessWidget {
  const ServerView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildPlatformAppBar(context, isCollapsed: false),
      floatingActionButton: startServerButton(),
      body: _body(),
    );
  }

  Widget _body() {
    return LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
      ServerController serverController = Get.find<ServerController>();
      return SingleChildScrollView(
          child: Column(
        spacing: 6,
        children: [
          ExpansionTileGroup(
            toggleType: ToggleType.expandOnlyCurrent,
            children: [
              path(context),
              deploy(constraints.maxHeight - 200, context),
              // OASX自启动设置：位于「服务启动配置」与「服务启动日志」之间。
              // 仅桌面渲染（AutoStartService 只在桌面注册）；
              // 条件必须是构建期稳定值，组内部按 children 长度生成 key 列表
              if (PlatformUtils.isDesktop) autoStart(context),
            ],
          ),
          LogWidget(
                  key: ValueKey(serverController.hashCode),
                  controller: serverController,
                  title: I18n.setup_log.tr)
              .constrained(height: constraints.maxHeight - 200)
        ],
      ).padding(right: 10, left: 10));
    });
  }

  ExpansionTileItem path(BuildContext context) {
    Widget path = GetX<ServerController>(builder: (controller) {
      return <Widget>[
        Text(I18n.root_path_server.tr,
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(
          width: 10,
        ),
        Text(controller.rootPathServer.value),
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
          // style: Theme.of(context).textTheme.titleMedium
        ),
      ].toRow();
    });

    return ExpansionTileItem(
      initiallyExpanded: false,
      isHasTopBorder: false,
      isHasBottomBorder: false,
      collapsedBackgroundColor:
          Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.24),
      borderRadius: const BorderRadius.all(Radius.circular(10)),
      title: pass,
      children: [
        path,
        Text(I18n.root_path_server_help.tr),
      ],
    );
  }

  ExpansionTileItem deploy(double maxHeight, BuildContext context) {
    return ExpansionTileItem(
      initiallyExpanded: false,
      isHasTopBorder: false,
      isHasBottomBorder: false,
      collapsedBackgroundColor:
          Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.24),
      borderRadius: const BorderRadius.all(Radius.circular(10)),
      title: Text(I18n.setup_deploy.tr,
          style: Theme.of(context).textTheme.titleMedium),
      children: [
        SingleChildScrollView(
          child: code(maxHeight - 50),
        ).constrained(height: maxHeight)
      ],
    );
  }

  // 「OASX自启动设置」折叠面板，样式与 path/deploy 一致；
  // 内容区抽在 auto_start_settings.dart，便于独立 widget 测试
  ExpansionTileItem autoStart(BuildContext context) {
    return ExpansionTileItem(
      initiallyExpanded: false,
      isHasTopBorder: false,
      isHasBottomBorder: false,
      collapsedBackgroundColor:
          Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.24),
      borderRadius: const BorderRadius.all(Radius.circular(10)),
      // 默认 children 居中会让裸 Text 水平居中，显式左对齐
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      childrenPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      title: Text(I18n.oasxAutoStartSettings.tr,
          style: Theme.of(context).textTheme.titleMedium),
      children: const [
        AutoStartSettingsContent(),
      ],
    );
  }

  Widget startServerButton() {
    return GetX<ServerController>(builder: (controller) {
      if (controller.rootPathAuthenticated.value) {
        return FloatingActionButton(
            child: const Icon(Icons.auto_mode_rounded),
            onPressed: () {
              controller.run();
            });
      } else {
        return const SizedBox(
          width: 100,
          height: 100,
        );
      }
    });
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
                  fontFamily: 'monospace',
                  fontSize: 14,
                ),
                decoration: const InputDecoration(
                  contentPadding: EdgeInsets.all(12),
                  border: InputBorder.none,
                  hintText: '在此编辑 deploy.yaml...',
                  hintStyle: TextStyle(color: Color(0xff6b6b6b)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.save),
            label: const Text('保存'),
            onPressed: () {
              controller.writeDeploy(textController.text);
            },
          ),
        ],
      );
    });
  }
}
