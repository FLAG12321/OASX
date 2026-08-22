library args;

// import 'dart:ffi';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pickers/pickers.dart';
import 'package:flutter_pickers/style/default_style.dart';
import 'package:get/get.dart';
import 'package:oasx/views/nav/view_nav.dart';
import 'package:styled_widget/styled_widget.dart';
import 'dart:convert';
import 'package:expansion_tile_group/expansion_tile_group.dart';
import 'dart:async';

import 'package:oasx/api/api_client.dart';
import 'package:oasx/component/busy_indicator.dart';

import '../../config/translation/i18n_content.dart';

part './group_view.dart';
part './date_time_picker.dart';
part '../../controller/args/args_controller.dart';

/// Checkbox 默认点击热区边长（MaterialTapTargetSize.padded）。
/// 实测值，SDK 未导出常量；下面的对齐测试会在 SDK 改动时失败。
const double _checkboxTapTarget = 48;

/// 勾选框描边方块左缘相对点击热区左缘的偏移。
/// 方块被居中放在热区里，所以偏移是两者边长差的一半。
const double _checkboxGeometryInset = (_checkboxTapTarget - Checkbox.width) / 2;

/// 视觉回收量：几何对齐后再往右让回来的像素数。
///
/// 按 [_checkboxGeometryInset] 整量左移后，测出的方块左缘与输入框左缘严格相等
/// （实测两者都在同一列 x），但看上去勾选框偏左了一点，原因是两种控件「可见的
/// 第一个像素」不在同一处：
///   * 勾选框的描边是 2px 宽、沿 18px 路径居中画的，墨迹左缘落在方块外 1px；
///   * 同列的输入框/时间选择器可见的是文字，字形自带左侧边距（Cascadia 之外的
///     正文字体约 1~2px），墨迹左缘落在盒子内。
/// 两者相差 3px 左右，几何对齐反而让勾选框看着突出去。
///
/// 单独留一个常量而不是把 3 揉进上面的算式：几何量是 SDK 推导的、有测试锁死，
/// 这个是纯视觉微调，要调只动这一个数。
const double _checkboxOpticalPullBack = 3;

/// 勾选框实际左移量。
const double _checkboxInset =
    _checkboxGeometryInset - _checkboxOpticalPullBack;

class Args extends StatelessWidget {
  const Args({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GetX<ArgsController>(builder: (controller) {
      return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: ExpansionTileGroup(
                      spaceBetweenItem: 10, children: _childrenGroup(context))
                  .constrained(maxWidth: 700, minWidth: 100))
          .alignment(Alignment.topCenter);
    });
  }

  List<ExpansionTileItem> _childrenGroup(BuildContext context) {
    ArgsController controller = Get.find();
    return controller.groupsName.value
        .map((name) => ExpansionTileItem(
              initiallyExpanded: true,
              isHasTopBorder: false,
              isHasBottomBorder: false,
              // collapsedBorderColor: Theme.of(context).colorScheme.secondaryContainer,
              // expendedBorderColor: Theme.of(context).colorScheme.outline,
              backgroundColor: Theme.of(context)
                  .colorScheme
                  .secondaryContainer
                  .withOpacity(0.24),
              borderRadius: const BorderRadius.all(Radius.circular(10)),
              title: Text(name.tr),
              children: _children(name),
            ))
        .toList();
  }

  List<Widget> _children(String groupName) {
    ArgsController controller = Get.find();
    GroupsModel groupsModel = controller.groupsData.value[groupName]!;
    List<Widget> result = [const Divider()];
    for (int i = 0; i < groupsModel.members.length; i++) {
      result.add(ArgumentView(
        setArgument: controller.setArgument,
        getGroupName: groupsModel.getGroupName,
        index: i,
      ));
    }
    return result;
  }
}

class ArgumentView extends StatefulWidget {
  // 返回真实落盘结果，UI 据此决定提示「已保存」还是「保存失败」
  final Future<bool> Function(String? config, String? task, String? group,
      String argument, String type, dynamic value) setArgument;
  final String Function() getGroupName;
  final int index;

  const ArgumentView(
      {required this.setArgument,
      required this.getGroupName,
      required this.index,
      Key? key})
      : super(key: key);

  @override
  // ignore: library_private_types_in_public_api
  _ArgumentViewState createState() => _ArgumentViewState();
}

class _ArgumentViewState extends State<ArgumentView> {
  Timer? timer;
  bool landscape = true;

  // 落盘中标记：从发起 PUT 到拿到结果为止为 true，标题右侧显示转圈
  bool _saving = false;

  ArgumentModel get model {
    ArgsController controller = Get.find();
    GroupsModel? groupsModel =
        controller.groupsData.value[widget.getGroupName()];
    return groupsModel!.members[widget.index];
  }

  @override
  Widget build(BuildContext context) {
    landscape = MediaQuery.of(context).orientation == Orientation.landscape;
    if (landscape) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _title(),
          ),
          _form(),
        ],
      ).padding(bottom: 8);
    } else {
      return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [_title(), _form()]).padding(bottom: 8);
    }
    // return LayoutBuilder(builder: (context, constraints) {
    //   if (constraints.maxWidth >= 350) {
    //     return Row(
    //       crossAxisAlignment: CrossAxisAlignment.start,
    //       children: [
    //         Expanded(
    //           child: _title(),
    //         ),

    //         // const Spacer(),
    //         _form(),
    //       ],
    //     );
    //   } else {
    //     return Column(
    //         crossAxisAlignment: CrossAxisAlignment.start,
    //         children: [_title(), _form()]);
    //   }
    // });
  }

  Widget _title() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Flexible(
          child: SelectableText(
            model.title.tr,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        _savingIndicator(),
      ]),
      if (model.description != null && model.description!.isNotEmpty)
        SelectableText(
          model.description!.tr,
          style: Theme.of(context).textTheme.bodySmall,
        ),
    ]);
  }

  /// 落盘中的过渡指示：与标题同行，固定 12px 占位避免出现/消失时文字跳动。
  /// 复用 BusyTransition 承载淡入淡出，与脚本启停按钮同一套观感。
  Widget _savingIndicator() {
    return BusyTransition(
      busy: _saving,
      size: 12,
      child: const SizedBox(width: 12, height: 12),
    ).paddingOnly(left: 6);
  }

  /// bool 参数的勾选框。
  ///
  /// 为什么要额外左移：Checkbox 画出来的描边方块只有 [Checkbox.width]（18px），
  /// 却被居中摆在 48px 的点击热区中央（SDK checkbox.dart 里
  /// `origin = size / 2 - Size.square(_kEdgeSize) / 2`），于是方块左缘比同列
  /// 其他控件（输入框 / 下拉 / 时间选择器都从列左缘 0 开始）右移了
  /// (48 - 18) / 2 = 15px，看起来就是「勾选框没和别人对齐」。
  ///
  /// 左移量 [_checkboxInset] = 几何量 15 减去视觉回收量 3：整量左移会让描边看着
  /// 比邻列文字突出去一点（描边墨迹在盒外、文字墨迹在盒内，详见那两个常量）。
  ///
  /// 用 Transform.translate 而不是缩小热区：把 materialTapTargetSize 调成
  /// shrinkWrap 也只降到 40px（实测），配合最紧的 visualDensity 仍是 24px，
  /// 永远大于 18px、永远对不齐，而且会把点击热区压到无障碍建议的 40px 以下。
  /// translate 只移动绘制与命中测试、不改布局尺寸，热区完整保留。
  Widget _checkbox() {
    // 用显式 Align 而不是 styled_widget 的 .alignment()：Transform 自带一个
    // 可空的 alignment 字段，而实例成员优先于扩展方法，.alignment(...) 会解析
    // 成「调用那个 null 字段」而不是扩展方法，直接编译不过。
    return Align(
      alignment: Alignment.centerLeft,
      child: Transform.translate(
        offset: const Offset(-_checkboxInset, 0),
        child: Checkbox(value: model.value, onChanged: onCheckboxChanged),
      ),
    ).constrained(width: landscape ? 200 : null);
  }

  Widget _form() {
    return switch (model.type) {
      "boolean" => _checkbox(),
      "string" => TextFormField(
          initialValue: model.value.toString(),
          onChanged: (value) {
            timer?.cancel();
            timer = Timer(const Duration(milliseconds: 1000),
                () => onStringChanged(value));
          }).constrained(width: landscape ? 200 : null),
      "multi_line" => TextFormField(
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          maxLines: null,
          initialValue: model.value.toString(),
          onChanged: (value) {
            timer?.cancel();
            timer = Timer(const Duration(milliseconds: 1000),
                () => onStringChanged(value));
          }).constrained(width: landscape ? 200 : null),
      "number" => TextFormField(
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp('[-0-9.]')),
          ],
          initialValue: model.value.toString(),
          onChanged: (value) {
            timer?.cancel();
            timer = Timer(const Duration(milliseconds: 1000),
                () => onNumberChanged(value));
          }).constrained(width: landscape ? 200 : null),
      "integer" => TextFormField(
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp('[-0-9]')),
          ],
          initialValue: model.value.toString(),
          onChanged: (value) {
            timer?.cancel();
            timer = Timer(const Duration(milliseconds: 1000),
                () => onIntegerChanged(value));
          }).constrained(width: landscape ? 200 : null),
      "enum" => DropdownButton<String>(
          isExpanded: !landscape,
          value: model.value.toString(),
          items: model.enumEnum!
              .map<DropdownMenuItem<String>>((e) => DropdownMenuItem(
                  value: e.toString(),
                  child: Text(
                    e.toString().tr,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ).constrained(width: landscape ? 177 : null)))
              .toList(),
          onChanged: onEnumChanged,
        ),
      "date_time" => DateTimePicker(
          value: model.value,
          onChange: onDateTimeChanged,
        ).constrained(width: landscape ? 200 : null),
      "time_delta" => TimeDeltaPicker(
          value: ensureTimeDeltaString(model.value),
          onChange: onTimeDeltaChanged,
        ).constrained(width: landscape ? 200 : null),
      "time" => TimePicker(
          value: model.value,
          onChange: onTimeChanged,
        ).constrained(width: landscape ? 200 : null),
      _ =>
        Text(model.value.toString()).constrained(width: landscape ? 200 : null)
    };
  }

  void onCheckboxChanged(bool? value) {
    setState(() {
      model.value = value;
    });
    unawaited(_save('boolean', value));
  }

  void onStringChanged(String? value) {
    unawaited(_save('string', value));
  }

  void onNumberChanged(String? value) {
    unawaited(_save('number', value));
  }

  void onIntegerChanged(String? value) {
    unawaited(_save('integer', value));
  }

  void onEnumChanged(String? value) {
    setState(() {
      model.value = value;
    });
    unawaited(_save('enum', value));
  }

  void onDateTimeChanged(String? value) {
    setState(() {
      model.value = value;
    });
    unawaited(_save('date_time', value));
  }

  void onTimeDeltaChanged(String? value) {
    setState(() {
      model.value = value;
    });
    unawaited(_save('time_delta', value));
  }

  void onTimeChanged(String? value) {
    setState(() {
      model.value = value;
    });
    unawaited(_save('time', value));
  }

// -----------------------------------------------------------------------------
  /// 统一落盘通路：置落盘中 → 等 PUT 结果 → 按真实结果提示。
  /// 原实现不等结果就弹「设置已保存」，PUT 失败时 UI 也照样说成功。
  Future<void> _save(String type, dynamic value) async {
    if (mounted) setState(() => _saving = true);
    bool ok = false;
    try {
      ok = await widget.setArgument(
          "", "", widget.getGroupName(), model.title, type, value);
    } finally {
      // 抛错也必须退出落盘中，否则转圈永久停留
      if (mounted) setState(() => _saving = false);
    }
    showSnakbar(ok, value);
  }

  void showSnakbar(bool ok, dynamic value) {
    Get.snackbar(
        ok ? I18n.setting_saved.tr : I18n.setting_save_failed.tr, "$value",
        duration: const Duration(seconds: 1));
  }
}
