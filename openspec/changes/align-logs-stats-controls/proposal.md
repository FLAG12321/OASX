## Why

当前项目新增 Stats 标签后，日志页的历史日志加载与操作按钮显示需要与来源项目体验对齐。用户希望 Logs 能显示之前日志，Stats 不再暴露手动刷新或日志操作控件，避免跨标签操作造成误导。

## What Changes

- Logs 页面加载历史/既有日志，而不是只显示当前会话新增内容。
- 移除 Stats 页面手动刷新按钮，统计数据由现有自动流或快照加载机制维护。
- 调整 Logs/Stats 标签容器：复制、自动滚动、删除等日志操作仅在 Logs 标签显示，Stats 标签隐藏。
- 保持开机自启与自动启动脚本能力不在本 change 内实现。

## Capabilities

### New Capabilities
- `logs-stats-experience`: 覆盖日志历史加载、Stats 手动刷新按钮移除，以及日志操作按钮按标签显示的用户可见行为。

### Modified Capabilities

## Impact

- 影响日志组件、Overview Logs/Stats 容器、Stats 面板和相关 Widget/contract 测试。
- 需要参考来源项目日志加载和 `LogWidget` 顶部操作栏可配置能力。
- 不改动后端日志 API 或统计数据协议。
