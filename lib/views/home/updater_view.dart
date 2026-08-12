import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:styled_widget/styled_widget.dart';

import 'package:oasx/api/update_info_model.dart';
import 'package:oasx/api/api_client.dart';
import 'package:oasx/config/global.dart';

import 'package:oasx/config/translation/i18n_content.dart';

/// 更新器页面。
///
/// 骨架（手动更新 UI）立即渲染，不依赖网络；远程分支信息由 [_RemoteSection]
/// 独立异步加载：加载中显示动画，连接失败显示「获取分支失败」，成功再渲染 commit 表格。
class UpdaterView extends StatefulWidget {
  const UpdaterView({Key? key}) : super(key: key);

  @override
  State<UpdaterView> createState() => _UpdaterViewState();
}

class _UpdaterViewState extends State<UpdaterView> {
  // 手动更新 UI 与远程信息区共享同一份 update_info，整页只发一次 /update_info，
  // 避免并发请求各自触发后端 git fetch 造成 ref 竞争
  late final Future<UpdateInfoModel> _infoFuture;

  @override
  void initState() {
    super.initState();
    _infoFuture = ApiClient().getUpdateInfo();
  }

  @override
  Widget build(BuildContext context) {
    // SizedBox.expand 撑满宿主的 Center，使内容顶部对齐而非垂直居中，
    // 避免远程区加载/失败时内容高度变化导致整个页面位置跳动
    return SizedBox.expand(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${I18n.current_version.tr}: ${GlobalVar.version}',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _UpdateConfigForm(infoFuture: _infoFuture),
            const SizedBox(height: 12),
            const _UpdateLogPanel(),
            const SizedBox(height: 12),
            _RemoteSection(infoFuture: _infoFuture),
          ],
        ).paddingAll(20),
      ),
    );
  }
}

/// Repository / Branch 填写框 + 保存按钮，读写都以 deploy.yaml 为准。
/// 初始值异步加载，加载期间保持空值可编辑，不阻塞手动更新 UI 的显示。
class _UpdateConfigForm extends StatefulWidget {
  const _UpdateConfigForm({Key? key, required this.infoFuture})
      : super(key: key);

  /// 与远程信息区共享的 update_info future，用于填充 Repository / Branch 初始值
  final Future<UpdateInfoModel> infoFuture;

  @override
  State<_UpdateConfigForm> createState() => _UpdateConfigFormState();
}

class _UpdateConfigFormState extends State<_UpdateConfigForm> {
  late final TextEditingController _repoController;
  late final TextEditingController _branchController;
  bool _saving = false;
  // 用户是否已手动编辑，避免异步填充初始值覆盖用户输入
  bool _userEdited = false;

  @override
  void initState() {
    super.initState();
    _repoController = TextEditingController();
    _branchController = TextEditingController();
    _loadInitial();
  }

  @override
  void dispose() {
    _repoController.dispose();
    _branchController.dispose();
    super.dispose();
  }

  /// 异步读取当前 Repository / Branch（来自 deploy.yaml），复用共享 future 避免重复请求。
  Future<void> _loadInitial() async {
    final info = await widget.infoFuture;
    // 用户已手动编辑时不覆盖输入框
    if (!mounted || _userEdited) return;
    setState(() {
      _repoController.text = info.repository ?? '';
      _branchController.text = info.branch ?? '';
    });
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
                onChanged: (_) => _userEdited = true,
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
                onChanged: (_) => _userEdited = true,
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

/// 远程分支信息区：独立异步加载 /update_info。
/// 加载中显示动画；fetch 失败（如连不上 GitHub / Gitee）显示「获取分支失败」；
/// 成功后渲染版本状态与本地/远程 commit 表格。
class _RemoteSection extends StatelessWidget {
  const _RemoteSection({Key? key, required this.infoFuture}) : super(key: key);

  /// 与手动更新表单共享的 update_info future，整页只发一次 /update_info
  final Future<UpdateInfoModel> infoFuture;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UpdateInfoModel>(
        future: infoFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            // 加载中：显示加载动画，不阻塞手动更新 UI
            return const Row(children: [
              SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 8),
              Text('正在获取分支信息…'),
            ]);
          }
          final data = snapshot.data;
          if (snapshot.hasError || data == null || data.fetchOk == false) {
            // 接口异常，或后端明确报告 fetch 失败（连不上远程），报错而不是假装「已是最新版本」
            return Text('获取分支失败',
                style: TextStyle(color: Theme.of(context).colorScheme.error));
          }
          // fetchOk 缺失（旧后端未返回该字段）或为 true：按数据渲染，commit 缺失时表格显示占位符
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _title(data, context),
              const SizedBox(height: 10),
              _differTable(data, context),
              const SizedBox(height: 10),
              Text(I18n.detailed_submission_history.tr,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              _submitHistory(data, context),
            ],
          );
        });
  }

  /// 顶部状态行：是否有新版本 + 当前分支
  Widget _title(UpdateInfoModel data, BuildContext context) {
    return <Widget>[
      data.isUpdate!
          ? const Icon(Icons.cloud_download)
          : const Icon(Icons.cloud_off, color: Colors.green),
      data.isUpdate!
          ? Text(I18n.find_oas_new_version.tr,
              style: Theme.of(context).textTheme.titleMedium)
          : Text(I18n.oas_latest_version.tr,
              style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(width: 20),
      Text('${I18n.current_branch.tr}: ${data.branch}',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center)
          .constrained(height: 26),
    ].toRow(
        crossAxisAlignment: CrossAxisAlignment.center,
        separator: const SizedBox(width: 10));
  }

  /// 本地 vs 远程 commit 对比表
  Table _differTable(UpdateInfoModel data, BuildContext context) {
    return Table(
      border: tableBorder,
      textBaseline: TextBaseline.alphabetic,
      columnWidths: columnWidths,
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        differHead(context),
        genTableRow(data.currentCommit, differ: true, localRepo: true),
        genTableRow(data.latestCommit, differ: true)
      ],
    );
  }

  Table _submitHistory(UpdateInfoModel data, BuildContext context) {
    return Table(
      border: tableBorder,
      columnWidths: columnWidths,
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: submitHistoryData(data, context),
    );
  }

  String sha1(String data) {
    return data.substring(0, 7);
  }

  TableRow genTableRow(List<String>? data,
      {bool differ = false, bool localRepo = false}) {
    // 远程 commit 数据可能为 null / 长度不足，渲染占位符避免整页崩溃
    final ok = data != null && data.length >= 4;
    return TableRow(children: [
      Text(ok ? sha1(data[0]) : '—').paddingAll(10),
      Text(ok ? data[1] : '—').paddingAll(10),
      Text(ok ? data[2] : '—').paddingAll(10),
      Text(ok ? data[3] : '—').paddingAll(10),
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

  List<TableRow> submitHistoryData(UpdateInfoModel data, BuildContext context) {
    List<TableRow> result = (data.commit ?? [])
        .map((e) => genTableRow(e))
        .toList()
        .cast<TableRow>();
    result.insert(0, historyHead(context));
    return result;
  }
}
