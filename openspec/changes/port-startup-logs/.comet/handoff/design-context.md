# Comet Design Handoff

- Change: port-startup-logs
- Phase: design
- Mode: compact
- Context hash: 3f73cdb22be6b890809d439b50cb4fe86d8f39235b4618b541a13403f574adf6

Generated-by: comet-handoff.sh

OpenSpec remains the canonical capability spec. This handoff is a deterministic, source-traceable context pack, not an agent-authored summary.

## openspec/changes/port-startup-logs/proposal.md

- Source: openspec/changes/port-startup-logs/proposal.md
- Lines: 1-25
- SHA256: d4752c9bb38cbc9928cd4b9575d89da2571c0c916dc4c06359754a7ef49a75b1

```md
## Why

当前项目缺少来源项目已经具备的开机自启与自动启动脚本能力，用户需要在应用启动后自动恢复常用脚本运行，减少手动操作。

本变更先移植启动相关能力，为后续日志/统计体验调整保持独立边界。

## What Changes

- 增加桌面平台开机自启能力，允许用户启用或关闭系统登录时启动 OASX。
- 增加自动启动脚本列表能力，允许用户选择应用启动后自动运行的脚本。
- 应用启动时读取已保存的自动启动脚本列表，并按来源项目行为启动脚本、展示进度与成功反馈。
- 保持后端脚本启动协议不变，仅复用现有脚本启动入口。

## Capabilities

### New Capabilities
- `startup-auto-run`: 覆盖桌面开机自启开关、自动启动脚本列表持久化，以及应用启动时执行自动脚本的用户可见行为。

### Modified Capabilities

## Impact

- 可能影响应用初始化流程、脚本服务初始化、设置/首页脚本操作入口和本地配置持久化。
- 需要参考来源项目 `AutoStartService`、`ScriptServiceAutoX` 与相关翻译/存储键实现。
- 不改动后端 API、脚本运行协议或日志/统计 UI。
```

## openspec/changes/port-startup-logs/design.md

- Source: openspec/changes/port-startup-logs/design.md
- Lines: 1-46
- SHA256: d610ef198a91d5716bbbf5501dbad5daf37e1a96bb6a34e95d04070053d3b757

```md
## Context

来源项目已经实现开机自启服务与自动启动脚本列表，当前项目需要移植这些启动能力。当前变更仅处理启动相关能力，日志/统计体验由独立 change 处理，避免把 UI 调整与启动流程耦合。

当前项目应优先复用现有脚本启动入口，不修改后端协议。开机自启需要桌面平台差异化实现，并在非桌面平台保持无副作用。

## Goals / Non-Goals

**Goals:**
- 提供桌面平台开机自启开关，并能同步系统真实启用状态。
- 提供自动启动脚本列表的持久化读写能力。
- 应用启动后自动读取列表并启动对应脚本，复用现有脚本启动流程。
- 保持用户反馈清晰：自动启动执行中显示进度，成功后提示结果。

**Non-Goals:**
- 不修改脚本后端启动 API 或 WebSocket 协议。
- 不调整日志/统计页面 UI。
- 不引入复杂的任务编排系统；自动启动脚本按保存列表顺序逐个尝试即可。

## Decisions

1. **复用来源项目服务分层，而不是把逻辑写入页面组件。**
   - 采用 `AutoStartService` 管理系统开机自启状态，采用 `ScriptService` 扩展管理自动启动脚本。
   - 理由：来源项目已验证该边界；服务层比 UI 层更适合处理启动时机和持久化。
   - 替代方案：直接在设置页或首页中写平台命令。放弃原因是会导致 UI 与系统行为耦合，难以测试。

2. **桌面开机自启按平台实现，非桌面直接 no-op。**
   - Windows 使用计划任务或来源项目等价方案；macOS 使用 LaunchAgent；Linux 使用 autostart desktop file。
   - 理由：跨平台自启没有统一系统 API，来源项目已有平台分支可复用。
   - 替代方案：只支持 Windows。放弃原因是来源项目已有跨平台能力，缩小范围会造成行为退化。

3. **自动启动脚本列表使用本地存储持久化。**
   - 保存脚本名列表，启动时读取并逐个调用现有 `startScript`。
   - 理由：无需后端新增字段，和来源项目行为一致。
   - 替代方案：把列表写入后端配置。放弃原因是本变更非目标为不改后端协议。

4. **启动成功判断以脚本运行状态为准，并设置短超时。**
   - 自动启动后轮询已有脚本状态，超时则继续处理后续脚本并记录/提示。
   - 理由：脚本启动是异步过程，调用返回不等于运行成功。

## Risks / Trade-offs

- [Risk] Windows 创建计划任务可能触发 UAC 或权限失败 → Mitigation：更新后刷新真实系统状态，失败时提示用户。
- [Risk] 应用启动时脚本列表中的脚本已不存在 → Mitigation：跳过无效脚本，不阻塞其他脚本。
- [Risk] 自动启动脚本过多导致启动阶段反馈时间较长 → Mitigation：逐个处理并显示当前脚本名与进度。
- [Risk] 平台自启命令在打包/开发模式路径不同 → Mitigation：使用运行时可执行文件路径，并在验证阶段覆盖桌面平台主路径。
```

## openspec/changes/port-startup-logs/tasks.md

- Source: openspec/changes/port-startup-logs/tasks.md
- Lines: 1-17
- SHA256: 3c33bdb05c23ca0e554cdc2c52ef312e9642811924bcbfbae7b62e07a0eb5960

```md
## 1. 启动服务移植

- [ ] 1.1 对比来源项目 `AutoStartService` 与当前项目初始化结构，确定服务注册位置和平台工具复用点
- [ ] 1.2 移植开机自启服务、存储键和必要翻译，确保桌面平台可刷新/更新系统自启状态
- [ ] 1.3 在设置或现有合适入口接入开机自启开关，并展示更新失败反馈

## 2. 自动启动脚本移植

- [ ] 2.1 对比来源项目 `ScriptServiceAutoX` 与当前脚本服务，移植自动启动脚本列表的读取、写入和排序逻辑
- [ ] 2.2 在脚本选择/操作入口接入自动启动脚本勾选状态，确保本地持久化生效
- [ ] 2.3 在应用启动流程中触发自动启动脚本，并复用现有脚本启动入口、运行状态判断和进度提示

## 3. 验证

- [ ] 3.1 增加或更新单元/Widget 测试，覆盖自动启动脚本列表持久化和 UI 勾选行为
- [ ] 3.2 运行格式化、静态分析和相关测试，确认不影响现有脚本启动流程
- [ ] 3.3 手动验证桌面平台开机自启启用/关闭后的状态同步与失败提示
```

## openspec/changes/port-startup-logs/specs/startup-auto-run/spec.md

- Source: openspec/changes/port-startup-logs/specs/startup-auto-run/spec.md
- Lines: 1-46
- SHA256: b546df4755c82a5b20bd5719fe8a5fc1182e8fa86420f7cce83c261a4355f2a8

```md
## ADDED Requirements

### Requirement: Desktop launch at startup
The system SHALL allow desktop users to enable or disable launching OASX when the operating system user signs in.

#### Scenario: Enable launch at startup
- **WHEN** a desktop user enables launch at startup
- **THEN** the system persists the preference and configures the operating system to launch OASX on user sign-in

#### Scenario: Disable launch at startup
- **WHEN** a desktop user disables launch at startup
- **THEN** the system removes the operating system launch entry and persists the disabled state

#### Scenario: Refresh launch state
- **WHEN** the app starts on a desktop platform
- **THEN** the system reads the operating system launch entry and updates the visible launch-at-startup state

### Requirement: Automatic script run list
The system SHALL allow users to maintain a persisted list of scripts that run automatically after the app starts.

#### Scenario: Add script to automatic run list
- **WHEN** a user marks a script for automatic run
- **THEN** the system stores that script name in the automatic run list

#### Scenario: Remove script from automatic run list
- **WHEN** a user unmarks a script for automatic run
- **THEN** the system removes that script name from the automatic run list

#### Scenario: Restore automatic run list
- **WHEN** the app initializes the script service
- **THEN** the system restores the automatic run list from local storage

### Requirement: Run automatic scripts on app startup
The system SHALL start scripts from the automatic run list after the script service has initialized.

#### Scenario: Start configured scripts
- **WHEN** the app starts and the automatic run list contains valid scripts
- **THEN** the system starts each listed script through the existing script start flow and shows progress feedback

#### Scenario: Skip already running script
- **WHEN** an automatic-run script is already running
- **THEN** the system treats it as successful and continues with the remaining scripts

#### Scenario: Continue after failed script start
- **WHEN** an automatic-run script cannot be started within the expected timeout
- **THEN** the system continues processing the remaining automatic-run scripts without changing the backend protocol
```

