# Brainstorm Summary

- Change: align-logs-stats-controls
- Date: 2026-06-26

## 确认的技术方案

采用 **脚本日志窗口 API + fallback** 方案。

1. **日志操作按钮按 tab 显示**
   - 在 `Overview` 增加 `showLogActions` 参数。
   - `OverviewLogsStatsView` 根据当前 tab 传入：Logs 为 `true`，Stats 为 `false`。
   - `Overview` 转发到 `LogWidget.enableCopy / enableAutoScroll / enableClear`。
   - Stats tab 隐藏 copy、auto-scroll、clear；切回 Logs 自动恢复。

2. **移除 Stats 手动刷新按钮**
   - `StatsOverviewPanel` 不再传入 `onRefresh`。
   - `_HeaderSection` 删除 `onRefresh` 字段和 `IconButton(Icons.refresh_rounded)`。
   - `StatsPageController.startAutoRefresh()` 与 timer 自动刷新保留。

3. **脚本历史日志懒加载**
   - 历史日志指脚本运行日志，不是 OASX GUI 自身日志文件。
   - 在当前 `ApiClient` 补来源项目已有日志窗口/SSE 封装：`getScriptLogWindow`、`buildScriptLogStreamUri`（不新增后端协议，只补前端调用）。
   - 新增轻量日志历史窗口状态（可命名为 `ScriptLogHistoryController` / `ScriptLogHistoryLoader`，或扩展 `OverviewController`，实现时按最小侵入选择）：
     - 初始进入 Logs tab 时拉最近 N 行。
     - 维护 `olderCursor` / `liveCursor` / `reachedStart` / `loadingOlder` / `_lineKeys`。
     - 用户向上滚动接近顶部时调用 `loadOlderLogs()`，按 cursor prepend 更早 N 行，并保持视口不跳。
     - WebSocket 实时日志继续 append，不覆盖历史窗口。
   - 如果窗口 API 不可用或请求失败，fallback 到现有 WebSocket 实时日志行为：页面不崩，记录 error/保持已有日志。

## 关键取舍与风险

- **不读 OASX app 本地日志文件**：`lib/utils/logger.dart` 写的是 GUI 自身日志，不是当前 Logs 面板要展示的脚本运行日志。
- **不新增后端协议**：只补前端调用封装；若后端版本没有来源项目日志窗口端点，则降级为现有实时日志。
- **视口保持是关键边界**：prepend 更早日志后需要保留用户当前看到的第一行锚点/scroll offset，避免向上加载时跳动。
- **窗口去重**：历史窗口、实时 WebSocket、新旧分页之间需按 line key 或文本+cursor 去重，避免重复行。
- **日志量限制**：需要保留窗口上限（例如来源项目 live 100 / manual 300），避免一次性把全部历史塞进 UI。

## 测试策略

- `LogWidget` / `OverviewLogsStatsView` widget 测试：
  - Logs tab 初始显示 copy、auto-scroll、clear。
  - 切到 Stats tab 隐藏这些按钮。
  - 切回 Logs tab 恢复按钮。
- `StatsOverviewPanel` widget 测试：
  - 不显示 refresh icon。
  - 自动刷新 controller 测试继续通过。
- 历史日志窗口单元测试：
  - 初始加载最近 N 行。
  - 向上触发加载更早日志并 prepend。
  - `reachedStart` 时不再请求。
  - fallback：窗口 API 失败时不崩、保留已有实时日志。
  - 新 WebSocket 行 append 后不与历史重复。

## Spec Patch

需要回写 delta spec：
1. 打开 Logs 时加载最近一段脚本历史日志。
2. 用户向上滚动接近顶部时继续加载更早脚本日志。
3. 无更多历史时停止加载且保留当前日志。
4. 历史日志接口不可用或失败时，系统降级为现有实时日志显示，不阻塞 Logs 页面。

## 用户确认状态

- 历史日志类型：脚本运行日志（已确认）
- 数据来源：窗口 API + fallback（已确认）
- 是否新增后端接口：不新增（已确认）
