import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:oasx/config/translation/i18n_content.dart';
import 'package:oasx/service/auto_start_service.dart';
import 'package:oasx/service/script_service.dart';

// 「OASX自启动设置」内容区：开机自启开关 + 自动启动脚本多选。
// 从设置页迁移而来，服务层逻辑零改动，仅 UI 绑定层。
// 独立成公开 widget 便于脱离 ServerController 单独做 widget 测试。
class AutoStartSettingsContent extends StatelessWidget {
  const AutoStartSettingsContent({super.key});

  @override
  Widget build(BuildContext context) {
    final autoStartService = Get.find<AutoStartService>();
    // 注册状态在页面停留期间不会变化（登录/killServer 均伴随路由跳转，
    // 重进 /server 必然重新 build），build 时一次性判断即可，无需响应式
    final scriptRegistered = Get.isRegistered<ScriptService>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 开机自启开关；isApplying 时禁用切换，避免并发写系统注册项
        Obx(() {
          final applying = autoStartService.isApplying.value;
          return SwitchListTile(
            title: Text(I18n.launchAtStartup.tr),
            value: autoStartService.enableLaunchAtStartup.value,
            dense: true,
            onChanged: applying
                ? null
                : (v) => autoStartService.updateLaunchAtStartupEnable(v),
          );
        }),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.only(left: 16, top: 8, bottom: 4),
          child: Text(I18n.autoRunScriptConfig.tr,
              style: Theme.of(context).textTheme.titleSmall),
        ),
        // ScriptService 未注册（登录前 / killServer 后）只显示登录提示，
        // 该分支为纯静态文案，不包 Obx（Obx 内无 Rx 读取会抛异常）
        if (scriptRegistered)
          _buildScriptList()
        else
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 8),
            child: Text(I18n.autoRunScriptLoginHint.tr),
          ),
      ],
    );
  }

  // 自动启动脚本多选列表，逻辑与原设置页一致：
  // 数据源 scriptModelMap.keys（仅真实脚本），勾选绑定 autoScriptList
  Widget _buildScriptList() {
    final scriptService = Get.find<ScriptService>();
    return Obx(() {
      final scriptNames = scriptService.scriptModelMap.keys.toList();
      final selected = scriptService.autoScriptList;
      return Column(
        children: scriptNames
            .map((name) => CheckboxListTile(
                  value: selected.contains(name),
                  onChanged: (v) =>
                      scriptService.updateAutoScript(name, v ?? false),
                  title: Text(name),
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                ))
            .toList(),
      );
    });
  }
}
