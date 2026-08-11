import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:styled_widget/styled_widget.dart';

import 'package:oasx/api/update_info_model.dart';
import 'package:oasx/api/update_progress_model.dart';
import 'package:oasx/api/api_client.dart';
import 'package:oasx/config/global.dart';

import 'package:oasx/config/translation/i18n_content.dart';

class UpdaterView extends StatelessWidget {
  const UpdaterView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UpdateInfoModel>(
        future: ApiClient().getUpdateInfo(),
        builder:
            (BuildContext context, AsyncSnapshot<UpdateInfoModel> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            // 当Future还未完成时，显示加载中的UI
            return const CircularProgressIndicator();
          } else if (snapshot.hasError) {
            // 当Future发生错误时，显示错误提示的UI
            return Text('Error: ${snapshot.error}');
          } else {
            // 当Future成功完成时，显示数据
            UpdateInfoModel data = snapshot.data!;
            return SingleChildScrollView(
              child: content(data, context).paddingAll(20),
            );
          }
        });
  }

  Widget content(UpdateInfoModel data, BuildContext context) {
    // String currentVersion = Get.find<SettingsController>().version.value;
    Widget version = Text('${I18n.current_version.tr}: ${GlobalVar.version}',
        style: Theme.of(context).textTheme.titleMedium);
    Widget title = <Widget>[
      data.isUpdate!
          ? const Icon(Icons.cloud_download)
          : const Icon(
              Icons.cloud_off,
              color: Colors.green,
            ),
      data.isUpdate!
          ? Text(I18n.find_oas_new_version.tr,
              style: Theme.of(context).textTheme.titleMedium)
          : Text(I18n.oas_latest_version.tr,
              style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(
        width: 20,
      ),
      Text('${I18n.current_branch.tr}: ${data.branch}',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center)
          .constrained(height: 26),
    ].toRow(
        crossAxisAlignment: CrossAxisAlignment.center,
        separator: const SizedBox(width: 10));
    Table differTable = Table(
      border: tableBorder,
      textBaseline: TextBaseline.alphabetic,
      columnWidths: columnWidths,
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        differHead(context),
        genTableRow(data.currentCommit!, differ: true, localRepo: true),
        genTableRow(data.latestCommit!, differ: true)
      ],
    );
    Table submitHistory = Table(
      border: tableBorder,
      columnWidths: columnWidths,
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: submitHistoryData(data, context),
    );
    return <Widget>[
      version,
      title,
      _UpdateConfigForm(data: data),
      // 手动更新 + log 框紧跟输入框下方
      const _UpdateLogPanel(),
      // 「当前版本」标题置于 log 框下方，与「详细提交历史」同一字体字号
      Text(I18n.current_version.tr,
          style: Theme.of(context).textTheme.titleMedium),
      differTable,
      Text(I18n.detailed_submission_history.tr,
          style: Theme.of(context).textTheme.titleMedium),
      submitHistory,
    ].toColumn(
        crossAxisAlignment: CrossAxisAlignment.start,
        separator: const SizedBox(
          height: 10,
        ));
  }

  String sha1(String data) {
    return data.substring(0, 7);
  }

  TableRow genTableRow(List<String> data,
      {bool differ = false, bool localRepo = false}) {
    return TableRow(children: [
      Text(sha1(data[0])).paddingAll(10),
      Text(data[1]).paddingAll(10),
      Text(data[2]).paddingAll(10),
      Text(data[3]).paddingAll(10),
      if (differ)
        localRepo
            ? Text(I18n.local_repo.tr).paddingAll(10)
            : Text(I18n.remote_repo.tr).paddingAll(10)
    ]);
  }

  TableBorder get tableBorder =>
      TableBorder.all(color: Colors.grey, width: 1, style: BorderStyle.solid);

  Map<int, TableColumnWidth> get columnWidths => const {
        0: FixedColumnWidth(80.0),
        1: FixedColumnWidth(140.0),
        2: FixedColumnWidth(200.0),
        // 3: FixedColumnWidth(80.0),
      };

  TableRow differHead(BuildContext context) => TableRow(children: [
        Text('SHA1', style: Theme.of(context).textTheme.titleMedium)
            .paddingAll(10),
        Text(I18n.author.tr, style: Theme.of(context).textTheme.titleMedium)
            .paddingAll(10),
        Text(I18n.submit_time.tr,
                style: Theme.of(context).textTheme.titleMedium)
            .paddingAll(10),
        Text(I18n.submit_info.tr,
                style: Theme.of(context).textTheme.titleMedium)
            .paddingAll(10),
        Text('Repo', style: Theme.of(context).textTheme.titleMedium)
            .paddingAll(10),
      ]);

  TableRow historyHead(BuildContext context) => TableRow(children: [
        Text('SHA1', style: Theme.of(context).textTheme.titleMedium)
            .paddingAll(10),
        Text(I18n.author.tr, style: Theme.of(context).textTheme.titleMedium)
            .paddingAll(10),
        Text(I18n.submit_time.tr,
                style: Theme.of(context).textTheme.titleMedium)
            .paddingAll(10),
        Text(I18n.submit_info.tr,
                style: Theme.of(context).textTheme.titleMedium)
            .paddingAll(10),
      ]);

  List<TableRow> submitHistoryData(data, BuildContext context) {
    List<TableRow> result =
        data.commit!.map((e) => genTableRow(e)).toList().cast<TableRow>();
    result.insert(0, historyHead(context));
    return result;
  }
}

/// Repository / Branch 填写框 + 保存按钮，读写都以 deploy.yaml 为准。
class _UpdateConfigForm extends StatefulWidget {
  const _UpdateConfigForm({Key? key, required this.data}) : super(key: key);

  final UpdateInfoModel data;

  @override
  State<_UpdateConfigForm> createState() => _UpdateConfigFormState();
}

class _UpdateConfigFormState extends State<_UpdateConfigForm> {
  late final TextEditingController _repoController;
  late final TextEditingController _branchController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _repoController = TextEditingController(text: widget.data.repository ?? '');
    _branchController = TextEditingController(text: widget.data.branch ?? '');
  }

  @override
  void dispose() {
    _repoController.dispose();
    _branchController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final res = await ApiClient().setUpdateConfig(
          branch: _branchController.text,
          repository: _repoController.text,
        );
    if (!mounted) return;
    setState(() => _saving = false);
    if (res != null && res.containsKey('error')) {
      Get.snackbar('保存失败', res['error'].toString());
    } else {
      Get.snackbar('保存成功', '');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _repoController,
                decoration: const InputDecoration(
                  labelText: 'Repository',
                  // 标签字号与「OAS已是最新版本」一致
                  labelStyle: TextStyle(fontSize: 16),
                ),
                // 输入框文字调细调小
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w300),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _branchController,
                decoration: const InputDecoration(
                  labelText: 'Branch',
                  // 标签字号与「OAS已是最新版本」一致
                  labelStyle: TextStyle(fontSize: 16),
                ),
                // 输入框文字调细调小
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w300),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? '保存中...' : '保存'),
            ),
          ],
        ),
      ],
    );
  }
}

/// 手动更新按钮 + 实时 log 框：点击后轮询后端进度接口逐行显示。
class _UpdateLogPanel extends StatefulWidget {
  const _UpdateLogPanel({Key? key}) : super(key: key);

  @override
  State<_UpdateLogPanel> createState() => _UpdateLogPanelState();
}

class _UpdateLogPanelState extends State<_UpdateLogPanel> {
  final ScrollController _scroll = ScrollController();
  Timer? _timer;
  List<String> _logs = [];
  String _status = 'idle';
  String _step = '';

  @override
  void dispose() {
    _timer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _startUpdate() async {
    await ApiClient().getExecuteUpdate();
    _timer?.cancel();
    setState(() {
      _status = 'running';
      _step = '';
      _logs = [];
    });
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      final prog = await ApiClient().getUpdateProgress();
      if (prog == null || !mounted) {
        return;
      }
      setState(() {
        _status = prog.status ?? _status;
        _step = prog.step ?? _step;
        _logs = prog.logs ?? [];
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
          );
        }
      });
      if (prog.finished == true) {
        _timer?.cancel();
      }
    });
  }

  String _statusText() {
    switch (_status) {
      case 'running':
        return '进行中';
      case 'done':
        return '完成';
      case 'failed':
        return '失败';
      case 'rejected':
        return '已拒绝';
      default:
        return '空闲';
    }
  }

  Color _statusColor() {
    switch (_status) {
      case 'running':
        return Colors.orange;
      case 'done':
        return Colors.green;
      case 'failed':
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  /// 按日志内容关键词着色：错误红、成功绿、警告橙、普通白
  Color _logColor(String line) {
    if (line.contains('error') ||
        line.contains('failed') ||
        line.contains('失败') ||
        line.contains('错误')) {
      return Colors.red;
    }
    if (line.contains('success') ||
        line.contains('done') ||
        line.contains('完成') ||
        line.contains('成功')) {
      return Colors.green;
    }
    if (line.contains('warning') ||
        line.contains('warn') ||
        line.contains('警告')) {
      return Colors.orange;
    }
    return Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            TextButton.icon(
              onPressed: _startUpdate,
              icon: const Icon(Icons.system_update),
              label: Text(I18n.execute_update.tr),
            ),
            Text('状态: ', style: Theme.of(context).textTheme.titleMedium),
            Text(_statusText(), style: TextStyle(color: _statusColor())),
            const SizedBox(width: 12),
            if (_step.isNotEmpty)
              Expanded(
                child: Text(_step,
                    style: Theme.of(context).textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          height: 200,
          decoration: BoxDecoration(
            color: Colors.black,
            border: Border.all(color: Colors.grey),
            borderRadius: BorderRadius.circular(4),
          ),
          padding: const EdgeInsets.all(8),
          child: ListView.builder(
            controller: _scroll,
            itemCount: _logs.length,
            itemBuilder: (context, index) => Text(
              _logs[index],
              // 每行日志按内容自动着色
              style: TextStyle(
                  color: _logColor(_logs[index]),
                  fontSize: 12,
                  fontFamily: 'monospace'),
            ),
          ),
        ),
      ],
    );
  }
}
