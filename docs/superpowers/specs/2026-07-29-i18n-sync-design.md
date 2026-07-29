# 后端 I18N 同步 OASX 翻译显示 — 设计文档

- 日期：2026-07-29
- 状态：待用户审查
- 涉及仓库：后端 `OnmyojiAutoScript-easy-install` + 前端 OASX（本次一次性改动）
- 长期目标：本方案落地后，后端新增 task / config 字段只需在后端补翻译条目，**前端无需再改代码或重新编译**即可正常显示翻译。

## 1. 问题

后端新增 task 或 config 字段后，OASX 界面显示英文原 key（如 `GuildActivityMonitor`、`boss_limit_time`），而不是中文。原因：

1. 前端翻译主体硬编码在 `lib/config/translation/i18n_cn.dart`，新 key 不存在时 GetX `.tr` 回退显示 key 原文，需要改前端代码并重新编译才能补翻译。
2. 两端已存在一条同步通道，但后端侧的翻译源 `assets/i18n/zh-CN.json` 纯手工维护，新增 task/字段时无人补条目、无校验，极易遗漏；`en-US.json` 为空。
3. 即使补了条目，前端拉取后只写缓存文件，要再重启一次 OASX 才加载生效。

## 2. 现状机制（探索结论）

### 前端（OASX）

| 环节 | 位置 | 行为 |
| --- | --- | --- |
| 翻译查找 | GetX `.tr` | 找不到 key 显示 key 原文 |
| 内置翻译 | `lib/config/translation/i18n_cn.dart` | 硬编码中文 map；英文由 key 自动生成 |
| 拉取补充翻译 | `lib/controller/ctrl_nav.dart:21` | 启动时 GET `/home/additional_translate`，结果只写入本地缓存 `<appcache>/i18n/<lang>.json` |
| 加载缓存 | `lib/service/locale_service.dart:53-73` | 启动早期读缓存文件，merge 进翻译表（现状：下次启动才生效） |
| 上传内置翻译 | `lib/api/api_client.dart:157` | 启动时 PUT `/home/chinese_translate`，后端存为 `module/config/i18n/zh-CN.json` 镜像 |

前端翻译 key 的实际来源（`lib/controller/args/args_controller.dart:97-107`、`lib/views/args/args_view.dart`、`lib/views/nav/view_nav.dart`）：

- 任务名/菜单分组名：`/script_menu` 返回的 CamelCase 名（如 `Guild`、`GuildActivityMonitor`）
- 分组名：`/{script}/{task}/args` 返回 dict 的 key（如 `scheduler`）
- 字段名：每个字段 item 的 **`name`**（前端 `ArgumentModel.title` 取的是 `json['name']`，不是后端的 `title` 字段）
- 帮助文本：字段的 `description`（约定为 `xxx_help` 形式的 key）
- 枚举值：`enumEnum` 的每个值

### 后端

| 环节 | 位置 | 行为 |
| --- | --- | --- |
| 补充翻译源 | `assets/i18n/zh-CN.json`（手工维护）、`en-US.json`（空） | GET `/home/additional_translate` 时实时读取下发（`module/server/i18n.py` `Addition.load_additions`） |
| 前端翻译镜像 | `module/config/i18n/zh-CN.json` | 前端每次启动上传；后端用 `I18n.trans_zh_cn` 翻译通知标题 |
| 任务 args | `module/config/config_model.py:308` `script_task()` | 从 pydantic json schema 提取分组/字段/enum 返回给前端 |
| 任务菜单 | `module/config/config_menu.py` `gui_menu_list` | 返回菜单分组与 CamelCase 任务名 |
| Qt 翻译 | `module/config/i18n/zh_CN.xml/.qm` | 仅旧 QML GUI 使用，与 OASX 无关，本方案不涉及 |

## 3. 目标与决策

- **目标**：后端修改 I18N 后，OASX 无需改代码、无需重新编译、无需硬编码即可显示翻译。
- 事实来源：保持 `assets/i18n/zh-CN.json` 手工填写中文，配套自动补齐工具（用户决策）。
- 工具运行方式：后端服务启动时自动扫描补齐缺失 key（用户决策）。
- 生效时机：OASX 启动时拉取后**当次立即生效**，无需重启（用户决策）。
- en-US：不维护英文翻译（用户决策）。实际回退行为：GetX `.tr` 在当前语言查不到 key 时回退到 fallbackLocale（zh-CN），因此英文界面下这些新 key 显示中文，而非原 key（plan-reviewer 依据 GetX 4.7.3 源码核实）。
- 前端改动范围：仅本次一次性改动「拉取后立即应用」逻辑；落地后新增翻译不再需要前端改动（用户澄清：「前端不改代码」指后续工作流，非本次实现）。

## 4. 方案设计

### 4.1 后端：启动时自动补齐缺失 key

位置：扩展 `module/server/i18n.py`，新增 `I18n.sync_missing_keys()`；在 `module/server/app.py` 的 `on_startup()` 中调用。

key 收集（与前端渲染完全同源）：

1. `mm.config_cache('template').gui_menu_list` 的 keys（菜单分组名）与 values（任务名）。
2. 对每个任务调用 `model.script_task(task)`，收集：分组名（返回 dict 的 key）、每个字段 item 的 `name`、`description`（存在时）、`enumEnum` 的每个枚举值。

判定缺失：key 不在 `assets/i18n/zh-CN.json` 且不在 `module/config/i18n/zh-CN.json`（前端内置翻译镜像）。缺失 key 以 **key 原文为占位值**追加写回 `assets/i18n/zh-CN.json`（保留既有条目顺序，追加尾部），日志报告补齐数量。占位值与 key 相同，显示效果与未翻译时一致；开发者随后只需把值改成中文。

守护条件：若镜像文件不存在（OASX 从未连接过本后端），跳过本次补齐并 warning，避免把数百个前端内置已翻译 key 误判为缺失灌入文件。

### 4.2 后端：下发时过滤空值（防御性保留）

`Addition.load_additions()` 过滤掉 value 为空字符串或非字符串的条目后再返回，防御历史空值占位条目与手工误填。占位条目（值 = key 原文）非空，会正常下发，前端显示效果与 `.tr` 回退一致。`load_additions` 每次请求实时读文件，因此**填写翻译后无需重启后端**。

### 4.3 前端：拉取后立即生效（本次一次性改动）

- `lib/service/locale_service.dart`：`DynamicMessages` mixin 新增 `applyAdditionalTranslate(Map<String, Map<String, String>> data)`，把 zh-CN / en-US 两组条目逐条 `translateUpdate` 合入内存翻译表（复用现有方法）。
- `lib/controller/ctrl_nav.dart` 的 `onInit`：拿到 additional_translate 数据后，先 `applyAdditionalTranslate` 合入内存，再 `saveAdditionalTranslate` 写缓存（离线兜底保留），最后 `Get.updateLocale(Get.locale!)` 触发全局重建，让已渲染的菜单/界面立刻换上新翻译。
- `lib/config/translation/i18n.dart` 的 `translateUpdate` 入口增加空字符串守护：空值直接忽略。兼容两类场景——旧后端未部署空值过滤时直接下发的空值、历史缓存文件中残留的空值条目（`loadMessage` 加载路径同样经过该入口），避免 `.tr` 返回空串导致界面空白。
- 启动时读缓存的 `loadMessage()` 逻辑不动：断网时仍能用上次拉到的翻译。

## 5. 错误处理

- 后端扫描中单个任务 `script_task()` 抛异常：跳过该任务继续，warning 日志。
- `assets/i18n/zh-CN.json` JSON 损坏：不写回（保护人工翻译成果），error 日志，服务照常启动。
- 整个 `sync_missing_keys()` 外层 try/except：任何失败只记日志，不阻塞服务启动。
- 前端 `Get.locale` 为 null（理论不会，GetMaterialApp 已设 locale）：跳过刷新，不崩溃。
- 路径约定：`assets_i18n_dir` 与既有 `file_zh_cn` 一致，在模块 import 时基于 `Path.cwd()` 固化，要求后端进程以仓库根为工作目录启动（现有部署方式即如此）。
- 已知限制：若后端先于新版 OASX 启动（镜像文件陈旧），前端新内置的 key 会被误判缺失、以 key 原文为值追加进 assets 文件；值与 key 相同不影响显示，无功能影响，仅产生少量待清理的噪音条目。

## 6. 验收标准

1. 后端新增带新字段的 task → 重启后端 → `assets/i18n/zh-CN.json` 自动出现该任务名、分组名、字段名、description key、enum 值的占位条目（值 = key 原文）；已有条目与顺序不变。
2. 在该文件填入中文（不重启后端）→ 启动 OASX → **当次启动内**新任务菜单名、字段名、枚举值即显示中文，无需重启 OASX。
3. 未填写的占位条目（值 = key 原文）在 OASX 显示原 key，不显示空白；空值条目（历史数据）被过滤不下发。
4. 已翻译内容无回归：前端内置翻译覆盖的 key 不会被追加为缺失条目，也不受下发数据影响。
5. 镜像文件缺失时后端启动不报错，仅 warning 且不修改 `assets/i18n/zh-CN.json`。
6. 此后再新增 task/字段，重复步骤 1-2 即可，前端无需任何代码改动或重新编译。

## 7. 测试

后端 `tests/` 目录下新增 pytest：

- `sync_missing_keys` 对给定 schema 收集 key 的正确性（任务名/分组/字段 name/description/enum）。
- 差集判定：assets 与镜像均命中/仅一方命中/均缺失三种情况。
- 空值过滤（防御性）：`load_additions` 不返回空字符串条目。
- 损坏 JSON、镜像缺失两个守护分支。

前端：`applyAdditionalTranslate` 合入翻译表的单元测试（含空字符串值被忽略的用例，Flutter test）；端到端行为按第 6 节验收标准手动验证。

## 8. 实施流程约束

实施计划须经 plan-reviewer 审查、代码须经 code-reviewer 审查后方可正式落地（用户要求）。
