part of overview;

// 中文注释：历史日志窗口加载函数签名，便于测试注入 fake 实现。
typedef LoadScriptLogWindow = Future<ScriptLogWindow?> Function(
  String scriptName, {
  String? cursor,
  int limitLines,
});

class OverviewController extends GetxController with LogMixin {
  String name;

  // 中文注释：以下 override 仅供测试注入；生产默认走 ApiClient 与全局 ScriptService。
  final LoadScriptLogWindow _loadLogWindow;
  final ScriptService? _scriptServiceOverride;
  final ScriptModel? _scriptModelOverride;

  late final scriptService =
      _scriptServiceOverride ?? Get.find<ScriptService>();
  late final scriptModel =
      _scriptModelOverride ?? scriptService.findScriptModel(name)!;

  // 中文注释：历史窗口游标与加载状态；reachedStart 后不再请求更早窗口。
  String? _olderCursor;
  bool _reachedStart = false;
  bool _historyLoading = false;

  // 中文注释：UI 头部被截断或清空后置 true，表示已加载历史失去连续性，
  // 下次顶部触发时丢弃旧游标、从最新窗口重建，避免出现不可恢复的日志断层。
  bool _historyStale = false;

  // 中文注释：logs 头部当前属于历史区段的行数（prepend 累加、头部截断扣减），
  // stale 重建时据此移除残留历史，防止新窗口插到旧历史上方造成时间线乱序。
  int _historyPrefixCount = 0;

  // 中文注释：已加载历史行的稳定 key 集合，用于跨窗口去重。
  final Set<String> _historyLineKeys = <String>{};

  OverviewController({
    required this.name,
    LoadScriptLogWindow? loadLogWindow,
    ScriptService? scriptServiceOverride,
    ScriptModel? scriptModelOverride,
  })  : _loadLogWindow = loadLogWindow ??
            ((scriptName, {cursor, limitLines = 500}) => ApiClient()
                .getScriptLogWindow(scriptName,
                    cursor: cursor, limitLines: limitLines)),
        _scriptServiceOverride = scriptServiceOverride,
        _scriptModelOverride = scriptModelOverride;

  @override
  void onInit() {
    super.onInit();
    // 中文注释：打开日志页后加载最新历史窗口，失败时保留现有 WebSocket 实时日志。
    unawaited(loadLatestHistoricalLogs());
  }

  // 中文注释：存在更早窗口或历史已失效待重建，且没有进行中的请求时允许加载。
  @override
  bool get canLoadOlderLogs =>
      !_historyLoading &&
      (_historyStale || (!_reachedStart && _olderCursor != null));

  @override
  Future<void> loadOlderLogs() =>
      _historyStale ? _rebuildStaleHistory() : loadOlderHistoricalLogs();

  // 中文注释：UI 头部被截断（maxLines/maxBuffer 限制）后历史连续性被破坏，
  // 标记失效，下次顶部触发时从最新窗口重建；截断优先消耗头部历史区段，
  // 同步扣减前缀计数以便重建时准确移除残留部分。
  @override
  void onUiLogsTrimmedFromHead(int removedCount) {
    _historyPrefixCount = removedCount >= _historyPrefixCount
        ? 0
        : _historyPrefixCount - removedCount;
    _historyStale = true;
  }

  // 中文注释：清空日志后旧游标与 key 集全部失效，重置以便重新加载历史。
  @override
  void clearLog() {
    super.clearLog();
    _olderCursor = null;
    _reachedStart = false;
    _historyLineKeys.clear();
    _historyPrefixCount = 0;
    _historyStale = true;
  }

  // 中文注释：丢弃失效的游标与 key 集，从最新窗口重新建立历史连续性。
  Future<void> _rebuildStaleHistory() async {
    if (_historyLoading) return;
    _historyStale = false;
    _olderCursor = null;
    _reachedStart = false;
    _historyLineKeys.clear();
    // 中文注释：先移除 UI 中残留的旧历史区段并补偿视口，否则重建的最新窗口会
    // 插到旧历史上方造成时间线乱序，且残留行会与后续 older 窗口重复。
    final residual =
        _historyPrefixCount > logs.length ? logs.length : _historyPrefixCount;
    if (residual > 0) {
      logs.removeRange(0, residual);
      preserveViewportAfterPrepend?.call(-residual);
    }
    _historyPrefixCount = 0;
    await loadLatestHistoricalLogs();
  }

  /// 加载最新历史窗口；失败时置 reachedStart 停止本轮 older 请求，不影响实时日志。
  Future<void> loadLatestHistoricalLogs() async {
    if (_historyLoading) return;
    _historyLoading = true;
    try {
      final window = await _loadLogWindow(name, limitLines: 500);
      if (window == null) {
        _olderCursor = null;
        _reachedStart = true;
        return;
      }
      // 中文注释：latest 窗口需与可见/pending 文本去重，规避 WebSocket 推送重叠。
      _applyHistoricalWindow(window, dedupeAgainstVisibleText: true);
    } catch (_) {
      _olderCursor = null;
      _reachedStart = true;
    } finally {
      _historyLoading = false;
    }
  }

  /// 按 olderCursor 加载更早窗口并 prepend；失败同样停止本轮请求。
  Future<void> loadOlderHistoricalLogs() async {
    if (!canLoadOlderLogs) return;
    final cursor = _olderCursor;
    if (cursor == null) return;
    _historyLoading = true;
    try {
      final window = await _loadLogWindow(name, cursor: cursor, limitLines: 500);
      if (window == null) {
        _olderCursor = null;
        _reachedStart = true;
        return;
      }
      // 中文注释：older 窗口只按行级 key 去重，允许重复文本（如分隔线）共存。
      _applyHistoricalWindow(window, dedupeAgainstVisibleText: false);
    } catch (_) {
      _olderCursor = null;
      _reachedStart = true;
    } finally {
      _historyLoading = false;
    }
  }

  // 中文注释：更新游标状态并把窗口内容 prepend 到 UI 日志。
  void _applyHistoricalWindow(
    ScriptLogWindow window, {
    required bool dedupeAgainstVisibleText,
  }) {
    _olderCursor = window.olderCursor;
    _reachedStart = window.reachedStart;
    _prependUniqueHistoricalLines(
      window.lines,
      dedupeAgainstVisibleText: dedupeAgainstVisibleText,
    );
  }

  // 中文注释：按行级 key 去重后 prepend，并通知视口补偿；
  // 仅 latest 窗口额外按可见/pending 文本去重，older 窗口允许重复文本。
  void _prependUniqueHistoricalLines(
    List<ScriptLogLine> lines, {
    required bool dedupeAgainstVisibleText,
  }) {
    final uniqueLines = <String>[];
    for (final line in lines) {
      if (line.text.isEmpty || _historyLineKeys.contains(line.key)) {
        continue;
      }
      if (dedupeAgainstVisibleText && containsVisibleOrPendingLog(line.text)) {
        continue;
      }
      _historyLineKeys.add(line.key);
      uniqueLines.add(line.text);
    }
    if (uniqueLines.isEmpty) return;
    logs.insertAll(0, uniqueLines);
    _historyPrefixCount += uniqueLines.length;
    preserveViewportAfterPrepend?.call(uniqueLines.length);
  }

  @override
  Future<void> onClose() async {
    // close log
    super.onClose();
  }

  Future<void> toggleScript() async {
    if (scriptModel.state.value != ScriptState.running) {
      scriptService.startScript(name);
      clearLog();
    } else {
      scriptService.stopScript(name);
    }
  }
}
