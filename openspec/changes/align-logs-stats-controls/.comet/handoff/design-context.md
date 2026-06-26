# Comet Design Handoff

- Change: align-logs-stats-controls
- Phase: design
- Mode: compact
- Context hash: f1dd80fa7f85b111309a0ad5e16c34145600fbff465e17feeda673338d8abaee

Generated-by: comet-handoff.sh

OpenSpec remains the canonical capability spec. This handoff is a deterministic, source-traceable context pack, not an agent-authored summary.

## openspec/changes/align-logs-stats-controls/proposal.md

- Source: openspec/changes/align-logs-stats-controls/proposal.md
- Lines: 1-23
- SHA256: ad2646ae21b2b1d16ac6a0176e46c84554af154d6fe38896ba90771c337d9245

```md
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
```

## openspec/changes/align-logs-stats-controls/design.md

- Source: openspec/changes/align-logs-stats-controls/design.md
- Lines: 1-40
- SHA256: ecc935bc926dbffb4740fc43f2183e939266d138ced023102df536d40cbd0ccd

```md
## Context

来源项目日志页使用可配置的 `LogWidget` 顶部操作栏，能加载历史日志；当前项目新增了 Logs/Stats 标签容器，需要让日志页对齐来源项目体验，并清理 Stats 标签下不该出现的日志操作控件和手动刷新按钮。

本变更聚焦日志/统计 UI 行为，不改后端日志或统计协议，也不涉及开机自启（由 `port-startup-logs` 处理）。

## Goals / Non-Goals

**Goals:**
- Logs 页面显示历史/既有日志，与来源项目一致，而非仅显示当前会话新增内容。
- Stats 页面不再显示手动刷新按钮，统计由现有自动流/快照机制维护。
- 复制、自动滚动、删除等日志操作只在 Logs 标签显示，Stats 标签隐藏。

**Non-Goals:**
- 不修改后端日志 API 或统计快照协议。
- 不实现开机自启或自动启动脚本。
- 不重写日志组件核心渲染，只调整加载与操作可见性。

## Decisions

1. **通过标签状态驱动日志操作按钮可见性。**
   - 在 Logs/Stats 容器中把当前标签传给日志顶部操作栏，Stats 标签时隐藏日志操作。
   - 理由：来源项目 `LogWidget` 已有 `enableCopy/enableAutoScroll/enableClear` 等可配置开关，可复用。
   - 替代方案：在 Stats 标签时整体卸载日志操作栏。放弃原因是会破坏面板头部布局。

2. **历史日志加载复用现有日志加载路径。**
   - 让 Logs 页面初始化时加载既有日志（来源项目通过 `savedScrollOffset` 和历史日志列表加载）。
   - 理由：避免新增协议，只补齐加载触发点和初始滚动位置恢复。
   - 替代方案：新增独立历史日志接口。放弃原因是非目标为不改后端协议。

3. **移除 Stats 手动刷新按钮，保留自动加载。**
   - 删除 Stats 面板的手动刷新入口，统计继续由现有自动流/SSE 维护。
   - 理由：手动刷新与自动流并存容易误导用户认为数据滞后。
   - 替代方案：保留但弱化按钮。放弃原因是用户明确要求移除。

## Risks / Trade-offs

- [Risk] 隐藏日志操作按钮可能影响用户在 Stats 切回 Logs 的可见性预期 → Mitigation：仅在 Stats 标签隐藏，切回 Logs 自动恢复，并在测试中覆盖。
- [Risk] 历史日志加载量较大导致首屏延迟 → Mitigation：复用来源项目分页/惰性加载逻辑，避免一次性加载全部日志。
- [Risk] 移除刷新按钮后某些自动流不稳定场景用户无法手动触发 → Mitigation：依赖现有连接重试机制，并在验证阶段确认统计仍可自动刷新。
```

## openspec/changes/align-logs-stats-controls/tasks.md

- Source: openspec/changes/align-logs-stats-controls/tasks.md
- Lines: 1-21
- SHA256: 4f59dd4cb7f71852e8d678bea31029357203d7b652a6719f1c9a618e8766d4ab

```md
## 1. 历史日志加载

- [ ] 1.1 对比来源项目日志加载与 `LogWidget` 初始滚动恢复逻辑，定位当前项目日志加载触发点
- [ ] 1.2 让 Logs 页面打开时加载既有/历史日志，并恢复与来源项目一致的滚动位置行为

## 2. Stats 刷新按钮移除

- [ ] 2.1 定位 Stats 面板手动刷新按钮，移除该入口并清理相关测试断言
- [ ] 2.2 确认统计仍通过现有自动流/SSE 正常更新，不引入新的刷新机制

## 3. 日志操作按钮显示条件

- [ ] 3.1 将当前 Logs/Stats 标签状态传入日志顶部操作栏
- [ ] 3.2 在 Stats 标签隐藏复制、自动滚动、删除等日志操作控件，Logs 标签保持显示
- [ ] 3.3 切回 Logs 标签时自动恢复日志操作控件可见性

## 4. 验证

- [ ] 4.1 更新现有 logs/stats contract 与 widget 测试，覆盖按钮可见性与历史日志加载
- [ ] 4.2 运行格式化、静态分析和相关测试，确认不影响日志渲染与统计自动更新
- [ ] 4.3 手动验证 Logs/Stats 切换时操作按钮显示与隐藏，以及 Logs 历史日志加载
```

## openspec/changes/align-logs-stats-controls/specs/logs-stats-experience/spec.md

- Source: openspec/changes/align-logs-stats-controls/specs/logs-stats-experience/spec.md
- Lines: 1-46
- SHA256: 5aa3a352cbe8bc5f93cc244aa54f070432365c2963a1c8b6344f7f5b29c4f4c2

```md
## ADDED Requirements

### Requirement: Load historical logs
The system SHALL display previously existing script run logs when the Logs view is opened, not only logs generated in the current session.

#### Scenario: Open Logs view with existing logs
- **WHEN** the user opens the Logs view and previous script logs exist
- **THEN** the system loads and displays the latest historical log window together with any new live logs

#### Scenario: Lazy-load older logs
- **WHEN** the user scrolls upward near the top of the currently loaded Logs view and older script logs exist
- **THEN** the system loads an older log window and prepends it without losing the user's current viewport position

#### Scenario: Reach beginning of log history
- **WHEN** the user scrolls upward after all older script logs have already been loaded
- **THEN** the system stops requesting older logs and keeps the currently displayed logs visible

#### Scenario: Restore scroll position
- **WHEN** the Logs view is reopened after scrolling
- **THEN** the system restores the saved scroll offset behavior consistent with the source project

#### Scenario: Historical log source unavailable
- **WHEN** the historical script log window cannot be loaded
- **THEN** the system continues showing the existing live log stream without blocking the Logs view

### Requirement: Remove manual stats refresh
The system SHALL NOT present a manual refresh control on the Stats view.

#### Scenario: Stats view controls
- **WHEN** the user opens the Stats view
- **THEN** the system shows no manual refresh button while statistics continue to update through the existing automatic flow

### Requirement: Log actions visible only on Logs tab
The system SHALL show log action controls (copy, auto-scroll, clear) only while the Logs tab is active.

#### Scenario: Log actions on Logs tab
- **WHEN** the Logs tab is active
- **THEN** the system shows the copy, auto-scroll, and clear log controls

#### Scenario: Log actions hidden on Stats tab
- **WHEN** the Stats tab is active
- **THEN** the system hides the copy, auto-scroll, and clear log controls

#### Scenario: Switch back to Logs restores actions
- **WHEN** the user switches from the Stats tab back to the Logs tab
- **THEN** the system shows the log action controls again
```

