import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:styled_widget/styled_widget.dart';

import 'package:oasx/api/update_info_model.dart';
import 'package:oasx/config/global.dart';
import 'package:oasx/config/translation/i18n_content.dart';
import 'package:oasx/controller/server/updater_controller.dart';

/// 更新器面板内容。
///
/// 全程不经过 server 的 HTTP 接口：分支信息、配置读写、执行更新都由
/// [UpdaterController] 直接 spawn OAS 安装目录下的 `python -m deploy.update`。
///
/// 为什么必须绕开 server：Windows 锁定已加载的 onnxruntime_providers_shared.dll，
/// 而 server.py 入口就 preload onnxruntime，Python 无法卸载已加载的扩展 DLL，
/// 所以 server 内发起的 OCR 换包必然 WinError 5。附带好处是 server 未启动时
/// 本面板依然完全可用——它就嵌在「服务启动配置」旁边，更新完可以直接在同页启动 server。
///
/// 标题层级（在 Material 3 默认值基础上整体 +2，见 [_sizeBump]。外层折叠面板
/// 标题「更新器」由 ServerView.panelTitleStyle 负责，是 17/w500）：
///   L2 面板内区块标题   titleSmall  14→16/w500  —— 低于自身面板标题一级
///   L3 表头            labelMedium 12→14/w500
///   正文 表格单元格/状态值 bodySmall   12→14/w400  —— 与 L3 同字号，靠粗细区分
class UpdaterPanel extends StatelessWidget {
  const UpdaterPanel({Key? key}) : super(key: key);

  /// 面板内文字整体放大量。集中在这里而不是逐处写死字号：
  /// 面板内既有走下面三个 helper 的文字，也有大量不带 style 的裸 Text，
  /// 后者靠 build() 里的 DefaultTextStyle 统一抬升同样的量。
  ///
  /// 比服务页其余面板的 ServerView.panelContentBump(=1) 更大一档：更新器内容
  /// 密度最高（版本号、仓库分支、表格、状态值），用户单独要求这一块再大一号。
  static const double _sizeBump = 2;

  /// 在主题字号基础上抬升 _sizeBump
  static TextStyle? _bump(TextStyle? base) => base?.copyWith(
      fontSize: (base.fontSize ?? 14) + _sizeBump);

  /// L2：面板内区块标题
  static TextStyle? sectionTitle(BuildContext context) =>
      _bump(Theme.of(context).textTheme.titleSmall);

  /// L3：表头
  static TextStyle? tableHead(BuildContext context) =>
      _bump(Theme.of(context).textTheme.labelMedium);

  /// 正文：表格单元格与状态值
  static TextStyle? bodyText(BuildContext context) =>
      _bump(Theme.of(context).textTheme.bodySmall);

  @override
  Widget build(BuildContext context) {
    final controller = UpdaterController.ensure();
    final root = controller.rootPath;
    // 面板内不带 style 的裸 Text（按钮标签、输入框文字等）也要同步放大；
    // 逐处补 style 必然漏改，这里用一层 DefaultTextStyle 覆盖整棵子树
    final inherited = DefaultTextStyle.of(context).style;
    return DefaultTextStyle(
      style: inherited.copyWith(
          fontSize: (inherited.fontSize ?? 14) + _sizeBump),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${I18n.current_version.tr}: ${GlobalVar.version}',
              style: sectionTitle(context)),
          const SizedBox(height: 12),
          if (root == null)
            // 路径没设或不合法时更新器无法工作，直接说清怎么办，
            // 而不是让下面每个区块各自报一遍失败
            Text(I18n.root_path_incorrect.tr,
                style: bodyText(context)
                    ?.copyWith(color: Theme.of(context).colorScheme.error))
          else ...[
            const _UpdateConfigForm(),
            const SizedBox(height: 12),
            const _UpdateLogPanel(),
            const SizedBox(height: 12),
            const _RemoteSection(),
          ],
        ],
      ),
    );
  }
}

/// Repository / Branch 填写框 + 保存按钮，读写都以 deploy.yaml 为准。
/// 初始值异步加载，加载期间保持空值可编辑，不阻塞手动更新 UI 的显示。
class _UpdateConfigForm extends StatefulWidget {
  const _UpdateConfigForm({Key? key}) : super(key: key);

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

  /// 异步读取当前 Repository / Branch（来自 deploy.yaml），
  /// 复用控制器上的共享 future 避免重复跑子进程。
  Future<void> _loadInitial() async {
    try {
      final info = await UpdaterController.ensure().infoFuture;
      // 用户已手动编辑时不覆盖输入框
      if (!mounted || _userEdited) return;
      setState(() {
        _repoController.text = info.repository ?? '';
        _branchController.text = info.branch ?? '';
      });
    } catch (_) {
      // 读取失败时保持空值可编辑，失败提示由远程信息区统一显示
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final res = await UpdaterController.ensure().saveConfig(
      branch: _branchController.text,
      repository: _repoController.text,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (res == null || res.containsKey('error')) {
      Get.snackbar('保存失败', res?['error']?.toString() ?? '未知错误');
    } else {
      Get.snackbar('保存成功', '');
    }
  }

  @override
  Widget build(BuildContext context) {
    // 标签与「当前版本」同款（都走 sectionTitle）；输入内容用正文字号，靠粗细区分
    final labelStyle = UpdaterPanel.sectionTitle(context);
    final inputStyle = UpdaterPanel.bodyText(context);
    return Row(
      // 标签在输入框上方，三者按底边对齐，保存按钮才与输入框齐平
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: _field('Repository', _repoController, labelStyle, inputStyle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _field('Branch', _branchController, labelStyle, inputStyle),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? '保存中...' : '保存'),
        ),
      ],
    );
  }

  /// 标签 + 输入框。
  ///
  /// 标签用独立 Text 而不是 InputDecoration.labelText：Material 的浮动标签在
  /// 有内容时会被 Transform 缩放到 _kFinalLabelScale(0.75)（SDK
  /// input_decorator.dart），这是几何缩放，光把 labelStyle 设成和「当前版本」
  /// 同字号也没用——渲染出来仍只有 0.75 倍。要真正同字号只能不走浮动标签。
  Widget _field(String label, TextEditingController controller,
      TextStyle? labelStyle, TextStyle? inputStyle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: labelStyle),
        TextField(
          controller: controller,
          style: inputStyle,
          onChanged: (_) => _userEdited = true,
        ),
      ],
    );
  }
}

/// 手动更新按钮 + 实时 log 框，状态与日志都取自 [UpdaterController]。
///
/// 相比此前轮询 /home/update_progress，流式读取不丢行也无 500ms 延迟，
/// 更重要的是完全不依赖 server 存活。
class _UpdateLogPanel extends StatefulWidget {
  const _UpdateLogPanel({Key? key}) : super(key: key);

  @override
  State<_UpdateLogPanel> createState() => _UpdateLogPanelState();
}

class _UpdateLogPanelState extends State<_UpdateLogPanel> {
  final ScrollController _scroll = ScrollController();
  // 已自动滚动到的行数，用于判断是否有新行到达
  int _scrolledTo = 0;

  @override
  void dispose() {
    // 只销毁视图资源：更新进程归控制器所有，切走页面不应中断在途更新
    _scroll.dispose();
    super.dispose();
  }

  void _autoScroll(int lineCount) {
    if (lineCount == _scrolledTo) return;
    _scrolledTo = lineCount;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
    });
  }

  String _statusText(String status) {
    switch (status) {
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

  Color _statusColor(String status) {
    switch (status) {
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
    return GetX<UpdaterController>(
      init: UpdaterController.ensure(),
      builder: (controller) {
        final status = controller.status.value;
        final logs = controller.logs;
        _autoScroll(logs.length);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                TextButton.icon(
                  // 更新中禁用：并发跑 git 会互相踩 .git/*.lock
                  onPressed:
                      controller.isRunning ? null : controller.startUpdate,
                  icon: const Icon(Icons.system_update, size: 18),
                  label: Text(I18n.execute_update.tr),
                ),
                Text('状态: ', style: UpdaterPanel.sectionTitle(context)),
                Text(_statusText(status),
                    style: UpdaterPanel.bodyText(context)
                        ?.copyWith(color: _statusColor(status))),
                const SizedBox(width: 12),
                if (controller.step.value.isNotEmpty)
                  Expanded(
                    child: Text(controller.step.value,
                        style: UpdaterPanel.bodyText(context),
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
                itemCount: logs.length,
                itemBuilder: (context, index) => Text(
                  logs[index],
                  // 每行日志按内容自动着色；字体跟随全局主题（等宽），
                  // 使阶段前缀与 pip/git 输出的列自然对齐。
                  // 字号刻意不跟随面板内容放大：日志保持小字号，一屏看更多行
                  style: TextStyle(
                      color: _logColor(logs[index]), fontSize: 12),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 远程分支信息区：读取控制器上共享的 `--info` 结果。
/// 加载中显示动画；fetch 失败（如连不上 GitHub / Gitee）显示「获取分支失败」；
/// 成功后渲染版本状态与本地/远程 commit 表格。
class _RemoteSection extends StatelessWidget {
  const _RemoteSection({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UpdateInfoModel>(
        future: UpdaterController.ensure().infoFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            // 加载中：显示加载动画，不阻塞手动更新 UI
            return Row(children: [
              const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 8),
              Text('正在获取分支信息…', style: UpdaterPanel.bodyText(context)),
            ]);
          }
          final data = snapshot.data;
          if (snapshot.hasError || data == null || data.fetchOk == false) {
            // 接口异常，或后端明确报告 fetch 失败（连不上远程），
            // 报错而不是假装「已是最新版本」
            return Text('获取分支失败',
                style: UpdaterPanel.bodyText(context)
                    ?.copyWith(color: Theme.of(context).colorScheme.error));
          }
          // fetchOk 缺失（旧后端未返回该字段）或为 true：按数据渲染，
          // commit 缺失时表格显示占位符
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _title(data, context),
              const SizedBox(height: 10),
              _differTable(data, context),
              const SizedBox(height: 10),
              Text(I18n.detailed_submission_history.tr,
                  style: UpdaterPanel.sectionTitle(context)),
              const SizedBox(height: 10),
              _submitHistory(data, context),
            ],
          );
        });
  }

  /// 顶部状态行：是否有新版本 + 当前分支
  Widget _title(UpdateInfoModel data, BuildContext context) {
    final isUpdate = data.isUpdate ?? false;
    return <Widget>[
      isUpdate
          ? const Icon(Icons.cloud_download, size: 18)
          : const Icon(Icons.cloud_off, color: Colors.green, size: 18),
      Text(
          isUpdate
              ? I18n.find_oas_new_version.tr
              : I18n.oas_latest_version.tr,
          style: UpdaterPanel.sectionTitle(context)),
      const SizedBox(width: 20),
      Text('${I18n.current_branch.tr}: ${data.branch}',
              style: UpdaterPanel.sectionTitle(context),
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
        genTableRow(context, data.currentCommit, differ: true, localRepo: true),
        genTableRow(context, data.latestCommit, differ: true)
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

  TableRow genTableRow(BuildContext context, List<String>? data,
      {bool differ = false, bool localRepo = false}) {
    // 远程 commit 数据可能为 null / 长度不足，渲染占位符避免整页崩溃
    final ok = data != null && data.length >= 4;
    final style = UpdaterPanel.bodyText(context);
    return TableRow(children: [
      Text(ok ? sha1(data[0]) : '—', style: style).paddingAll(8),
      Text(ok ? data[1] : '—', style: style).paddingAll(8),
      Text(ok ? data[2] : '—', style: style).paddingAll(8),
      Text(ok ? data[3] : '—', style: style).paddingAll(8),
      if (differ)
        Text(localRepo ? I18n.local_repo.tr : I18n.remote_repo.tr, style: style)
            .paddingAll(8)
    ]);
  }

  TableBorder get tableBorder =>
      TableBorder.all(color: Colors.grey, width: 1, style: BorderStyle.solid);

  Map<int, TableColumnWidth> get columnWidths => const {
        0: FixedColumnWidth(80.0),
        1: FixedColumnWidth(140.0),
        2: FixedColumnWidth(200.0),
      };

  TableRow differHead(BuildContext context) {
    final style = UpdaterPanel.tableHead(context);
    return TableRow(children: [
      Text('SHA1', style: style).paddingAll(8),
      Text(I18n.author.tr, style: style).paddingAll(8),
      Text(I18n.submit_time.tr, style: style).paddingAll(8),
      Text(I18n.submit_info.tr, style: style).paddingAll(8),
      Text('Repo', style: style).paddingAll(8),
    ]);
  }

  TableRow historyHead(BuildContext context) {
    final style = UpdaterPanel.tableHead(context);
    return TableRow(children: [
      Text('SHA1', style: style).paddingAll(8),
      Text(I18n.author.tr, style: style).paddingAll(8),
      Text(I18n.submit_time.tr, style: style).paddingAll(8),
      Text(I18n.submit_info.tr, style: style).paddingAll(8),
    ]);
  }

  List<TableRow> submitHistoryData(UpdateInfoModel data, BuildContext context) {
    List<TableRow> result = (data.commit ?? [])
        .map((e) => genTableRow(context, e))
        .toList()
        .cast<TableRow>();
    result.insert(0, historyHead(context));
    return result;
  }
}
