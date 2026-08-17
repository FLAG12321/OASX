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

  Widget _form() {
    return switch (model.type) {
      "boolean" => Checkbox(value: model.value, onChanged: onCheckboxChanged)
          .alignment(Alignment.centerLeft)
          .constrained(width: landscape ? 200 : null),
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
