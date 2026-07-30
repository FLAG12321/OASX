import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import 'package:oasx/api/api_client.dart';
import 'package:oasx/config/translation/i18n_content.dart';
import 'package:oasx/service/auto_boot_service.dart';
import 'package:oasx/service/auto_start_service.dart';

// 「OASX自启动设置」内容区：开机自启开关 + 自动启动脚本多选与延时配置。
// 脚本列表不再依赖登录（ScriptService），改为探测 server 可达后经
// getScriptList 拉取（spec §4.4）；probeBackend/fetchScripts 可注入以便测试。
class AutoStartSettingsContent extends StatefulWidget {
  const AutoStartSettingsContent(
      {super.key, this.probeBackend, this.fetchScripts});

  // server 可达探测与脚本列表拉取，默认走 ApiClient（探测前按地址规则 set）
  final Future<bool> Function()? probeBackend;
  final Future<List<String>> Function()? fetchScripts;

  @override
  State<AutoStartSettingsContent> createState() =>
      _AutoStartSettingsContentState();
}

class _AutoStartSettingsContentState extends State<AutoStartSettingsContent> {
  // null=探测中；true/false=可达/不可达
  bool? _reachable;
  List<String> _scriptNames = const [];

  @override
  void initState() {
    super.initState();
    _probe();
  }

  // 默认探测实现：按地址取值规则（spec §3）设置全局地址后调 /test。
  // 与登录行为一致；手动登录时会用用户输入值重新覆盖，无负面影响。
  // 用静默探测：server 未启动是常态，不应弹网络错误 snackbar（spec §5）
  Future<bool> _defaultProbe() {
    ApiClient()
        .setAddress('http://${Get.find<AutoBootService>().resolveAddress()}');
    return ApiClient().testAddressSilent();
  }

  Future<void> _probe() async {
    setState(() => _reachable = null);
    final ok = await (widget.probeBackend?.call() ?? _defaultProbe());
    if (!mounted) return;
    if (!ok) {
      setState(() => _reachable = false);
      return;
    }
    final names =
        await (widget.fetchScripts?.call() ?? ApiClient().getScriptList());
    if (!mounted) return;
    setState(() {
      _reachable = true;
      _scriptNames = names;
    });
  }

  @override
  Widget build(BuildContext context) {
    final autoStartService = Get.find<AutoStartService>();

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
        Row(children: [
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 8, bottom: 4),
            child: Text(I18n.autoRunScriptConfig.tr,
                style: Theme.of(context).textTheme.titleSmall),
          ),
          // 手动刷新：重新探测 + 拉取列表
          IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: I18n.autoRunScriptRefresh.tr,
            onPressed: _probe,
          ),
        ]),
        switch (_reachable) {
          // 探测中：占位进度条
          null => const Padding(
              padding: EdgeInsets.all(16),
              child: LinearProgressIndicator(),
            ),
          // 不可达：提示启动 server（spec §4.4，不提供缓存列表）
          false => Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 8),
              child: Text(I18n.autoRunScriptServerHint.tr),
            ),
          true => _buildScriptList(),
        },
      ],
    );
  }

  // 脚本多选 + 每脚本延时输入：勾选绑定 AutoBootService 条目，
  // 延时仅勾选时可编辑，输入即持久化（0–86400，越界由模型钳制）
  Widget _buildScriptList() {
    final autoBoot = Get.find<AutoBootService>();
    return Obx(() {
      // 读取 autoScriptEntries 建立响应式依赖（勾选/延时变化即重建）
      final entries = {
        for (final e in autoBoot.autoScriptEntries) e.name: e.delaySeconds
      };
      return Column(
        children: _scriptNames.map((name) {
          final selected = entries.containsKey(name);
          return Row(children: [
            Expanded(
              child: CheckboxListTile(
                value: selected,
                onChanged: (v) => autoBoot.setSelected(name, v ?? false),
                title: Text(name),
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ),
            // 延时输入：仅数字，非法输入由过滤器与模型 clamp 双重防护。
            // key 掺入勾选态：取消勾选再勾选时条目延时归零，需强制重建输入框，
            // 否则 FormField state 保留旧显示值，与实际调度值不一致。
            // 不掺入延时值，否则每次击键都会重建、丢失输入焦点
            SizedBox(
              width: 90,
              child: TextFormField(
                key: ValueKey('delay_${name}_$selected'),
                enabled: selected,
                initialValue: '${entries[name] ?? 0}',
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: I18n.autoRunScriptDelayLabel.tr,
                  isDense: true,
                ),
                onChanged: (v) =>
                    autoBoot.setDelay(name, int.tryParse(v) ?? 0),
              ),
            ),
            const SizedBox(width: 8),
          ]);
        }).toList(),
      );
    });
  }
}
