# smooth-log-loading 技术设计

## 背景与问题

`align-logs-stats-controls` 变更上线历史日志加载后，选中脚本 / 打开 Logs 标签时应用出现明显卡顿。

### 归因实测（2026-07-29）

初版设计把成因归为「`insertAll(0, 500行)` 单帧插入 + 每行 `EasyRichText` 构建成本高」，并据此设计了分批插入方案。用探针测试（500 行日志、400px 视口、widget 测试环境 debug JIT，绝对值仅作相对比较）实测后，该归因**被证伪**：

| 场景 | itemBuilder 调用次数 | 总耗时 | 超 16ms 的帧数 |
| --- | --- | --- | --- |
| `animateTo` 滚到底（现状） | 470 / 500 | 1164ms | 37 |
| `jumpTo` 直达（现状，无固定行高） | 470 / 500 | 768ms | 1（单帧 764ms） |
| `animateTo` + `prototypeItem` | 475 / 500 | 951ms | 25 |
| **`jumpTo` + `prototypeItem`** | **25 / 500** | **43ms** | 1（单帧 38ms） |
| `animateTo` + 缓存 pattern 列表 | 470 / 500 | 876ms | 23 |
| `animateTo` 200 行 | 170 / 200 | 377ms | 3 |

结论：

1. **`insertAll` 不是瓶颈。** `ListView.builder` 惰性构建，插入 500 个 String 指针是微秒级操作，不会构建 500 个 `EasyRichText`。**分批插入方案的前提不成立。**
2. **真正的成本是「日志区从顶部移动到底部」这一次滚动。** 两条路径都很贵：
   - `animateTo`（`_scrollLogs` 默认路径，时长 `sqrt(distance)*10` 上限 1000ms）：动画途经每一行，`SliverList` 逐行构建，470 次构建摊在 37 个掉帧的帧上，用户感知为持续约 1 秒的卡顿。
   - `jumpTo`（`_preserveViewportAfterPrepend` 的补偿路径）：`SliverList` 没有固定行高时，必须从头逐行累加高度才能定位目标 offset，470 次构建压在单帧内 → 764ms 冻结。
3. **`prototypeItem` / `itemExtent` 消除定位扫描。** 给定行高后 `SliverList` 可直接算出目标 offset 对应的行，`jumpTo` 只构建视口内约 25 行。两者效果等价，`prototypeItem` 不需要硬编码行高（行高随主题/orientation 变化），因此选它。
4. **单独加 `prototypeItem` 不够。** 动画途经的行仍会被逐行构建（951ms / 25 帧掉帧），必须同时避免超长距离动画。
5. 缓存 `_buildPatterns()` 只带来约 25% 改善，是次要因素，本次不做。

## 目标与范围

1. 消除「日志区滚到底」造成的持续掉帧：给日志列表提供固定行高，并让超长距离滚动直接跳转。
2. 首次加载历史日志期间显示加载占位动画，消除"白屏卡住"的感知。

非目标：

- 不改动后端协议与 `ApiClient` 接口。
- 不改动实时日志 WebSocket 通道与 pending buffer 机制。
- 不改动历史连续性状态机（游标、去重、stale 重建、视口补偿）的语义与插入方式。
- 不引入虚拟化行高缓存等重量级渲染优化，不缓存 pattern 列表。
- **不做分批插入**（归因证伪，见上）。
- **不调整历史窗口行数**（`limitLines` 保持 500，理由见下）。

## 已放弃的初版方案

| 初版方案 | 放弃理由 |
| --- | --- |
| 历史日志每批 100 行分批 `insertAll` | 归因证伪：`insertAll` 非瓶颈。且批间 `await Future<void>.delayed(Duration.zero)` 让出的是事件循环轮次而非 vsync 帧边界（零时长 timer 微秒级触发，vsync 间隔 16.7ms），全部批次几乎必然落在同一帧，`Obx` 合并为一次重建 —— 即便前提成立也无收益。 |
| 首窗口 `limitLines` 500 → 200 | 实测确有改善（37 帧掉帧 → 3 帧），但属治标：加 `prototypeItem` + `jumpTo` 后 500 行的滚动成本已降到 43ms，无需牺牲可回看范围。且 200 恰好等于 `LogMixin.maxLines`，运行中脚本任意一条实时日志到达即触发头部截断 → 置 `_historyStale` → 上滚重建 → 再次截断，形成抖动环。 |

## 架构设计

### 1. 列表固定行高（`lib/component/log/log_widget.dart` 的 `LogContent`）

给 `ListView.builder` 传 `prototypeItem`。**原型必须与真实行同构且命中高亮 pattern**——行高实测矩阵（widget 测试，含上下 padding 各 1px）：

| 行形态 | `titleSmall`（landscape） | `bodySmall`（portrait） |
| --- | --- | --- |
| 普通 `Text` | 22.0 | 18.0 |
| `EasyRichText(selectable)` 未命中 pattern | 22.0 | 18.0 |
| `EasyRichText(selectable)` **命中 pattern**（真实日志行） | 22.0 | **22.0** |

`SliverPrototypeExtentList` 用紧约束把每个子项压到原型高度：原型若用普通 `Text` 或未命中 pattern 的文本，portrait 下会比命中行矮 4px，导致真实行被压扁裁切。因此原型取最高行形态：

```dart
prototypeItem: Padding(
  padding: const EdgeInsets.symmetric(vertical: 1),
  child: EasyRichText(
    'INFO: 00:00:00.000 prototype\n',
    patternList: _buildPatterns(),
    selectable: true,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    defaultStyle: _selectStyle(context),
  ),
),
```

`SliverList` 据此把 offset ↔ index 变成常数时间换算，`jumpTo` 与视口补偿不再触发全量行构建。

附带的行为变化：portrait 下现状行高本就是混合的（命中 22 / 未命中 18），统一到原型高度后，未命中 pattern 的行多出 4px 空隙——只加空隙不裁切，且视口补偿的「行高一致」假设由近似变为精确。

### 2. 超长距离滚动直接跳转（`_scrollLogs`）

`_scrollLogs` 现有逻辑：`isJump` 为 true 时 `jumpTo`，否则按 `sqrt(distance)*10`（clamp 100~1000ms）`animateTo`。新增一条：距离超过 3 个视口高度时改为 `jumpTo`。

```dart
// 中文注释：超长距离动画会让 SliverList 把途经的每一行都构建一遍
// （实测 500 行滚到底构建 470 行、37 帧掉帧），直接跳转规避。
if (distance > _scrollController!.position.viewportDimension * 3) {
  _scrollController!.jumpTo(targetPos);
  return;
}
```

- 阈值用视口相对量而非固定像素，自适应窗口尺寸。
- 3 个视口以内保留平滑动画，实时日志追加的"跟随尾部"体验不变。
- 历史日志落地、切标签恢复位置等大跨度场景走跳转。

### 3. 加载占位动画

**状态（`lib/component/log/log_mixin.dart`）**：

```dart
/// 历史日志加载中；由支持历史加载的子类（OverviewController）维护。
final historyLoading = false.obs;
```

`OverviewController` 现有私有 `bool _historyLoading` 改为直接读写该 RxBool，`canLoadOlderLogs` 等守卫语义不变。

**渲染（`LogContent`）**：占位用 `Stack` **叠加**在列表之上，而非替换列表：

```dart
Obx(() {
  final list = ListView.builder(...).paddingAll(10);
  if (!controller.historyLoading.value || controller.logs.isNotEmpty) {
    return list;
  }
  return Stack(children: [
    list,
    const Center(
      child: SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(strokeWidth: 2.6),
      ),
    ),
  ]);
})
```

- **关键：`ListView` 必须常驻。** 若占位期间不构建 `ListView`，`ScrollController` 就没有 clients，而 `_scrollLogs` 与 `_preserveViewportAfterPrepend` 的第一行都是 `hasClients` 守卫 —— `initState` 那次**一次性**的 postFrameCallback 滚底会空转且不重试，首批历史落地时也拿不到视口补偿。结果是用户停在 500 行历史的最顶端（最老的行），对未运行的脚本无任何后续机制纠正。叠加方案从构造上排除该问题。
- `logs` 为空时列表本身是空白，叠加与替换的视觉效果一致。
- spinner 与 `StatsOverviewPanel` 加载态完全一致（`SizedBox(28×28)` + `CircularProgressIndicator(strokeWidth: 2.6)`，见 `stats_overview_panel.dart:277-281`），不附加文案，不新增 i18n key。spinner 中心 28×28 会吸收指针事件（实测命中测试落在 spinner 而非下层 viewport），但该状态下列表必为空、无可滚动内容，日志一到达占位即消失，因此不影响交互。
- 仅 `logs` 为空时显示：向上懒加载 older、stale 重建、清空后重载等场景用户可能正在阅读，不遮挡。注意 `clearLog()` 会清空 `logs`，因此"清空后重载"实际会显示占位 —— 空列表上转圈是合理表现，不为此加特例。

### 4. 错误处理

- 加载失败 / 异常路径不变：保留已有实时日志、`_olderCursor=null; _reachedStart=true` 停止本轮。
- `historyLoading` 在 `finally` 复位，占位不会因失败卡死。

## 测试策略

### widget 测试（`test/component/log/log_widget_scroll_test.dart` 新建）

- `prototypeItem` 非 null（结构断言，锁定固定行高不被回退）。
- **原型与真实行等高**：从挂载的 `ListView` 取出 `prototypeItem` 与 `childrenDelegate` 构建的第 0 行，并排渲染比较高度；landscape 与 portrait（`tester.view.physicalSize` 切换）各测一次——portrait 下命中 pattern 的行比普通 `Text` 高 4px，最容易暴露失配。
- 大距离 `scrollLogs(force: true, scrollOffset: -1)` 在一帧内到底（现状会在 1000ms 动画中途）。
- 小距离仍走动画（一帧后 offset 严格介于起点与目标之间；用例先断言 `maxScrollExtent > 0`，避免行数不足时静默空转）。
- 占位三态：`historyLoading && logs 为空` → 有 spinner 且 `ListView` **仍在树上**；`historyLoading && logs 非空` → 无 spinner；加载完成 → 无 spinner。
- 占位期间 `ScrollController.hasClients` 为 true（锁定 A3 回归）。

### controller 测试（`test/controller/overview/overview_log_history_test.dart`）

- 现有 9 个用例断言保持不变。
- 新增 `historyLoading` 时序：用 Completer gate 观察加载前 false → 进行中 true → 完成后 false；失败路径同样用 gate 形式验证 `finally` 复位（避免写成在任何实现下都通过的空转测试）。

### 手动验证

- 选中有历史日志的脚本 / 打开 Logs：先出现 spinner，日志落地后**直接定位到底部最新日志**，无持续掉帧、无停在最老行。
- 上滚加载更早日志：无占位遮挡，阅读位置稳定。
- 运行中脚本实时日志持续追加，跟随尾部仍是平滑动画。
- 窗口拉成竖长（portrait）：文字不被裁切或行间重叠，未命中高亮 pattern 的行允许略松。

## 风险与缓解

| 风险 | 缓解 |
| --- | --- |
| `prototypeItem` 行高与实际行不一致导致行被压扁裁切 | 原型与真实行**同构**（同 `patternList` / `selectable` / `defaultStyle`）且文本命中高亮 pattern，取实测最高行形态（见 §1 行高矩阵）；widget 测试在双 orientation 下断言原型与真实行等高 |
| portrait 下未命中 pattern 的行被原型高度撑高 4px | 只加空隙不裁切；现状 portrait 行高本就混合（22/18），统一后视口补偿反而由近似变精确 |
| 大跨度跳转失去动画过渡，观感突兀 | 该场景本来就因掉帧而无平滑感；跳转后立即呈现最新日志，比 1 秒卡顿的动画体验更好 |
| 3 倍视口阈值误伤正常追尾 | 追尾距离通常远小于一个视口；阈值可按手动验证结果调整 |
| 占位叠加后 `logs` 为空时列表仍在树上 | 空 `ListView` 无子项、无视觉输出；换来 `ScrollController` 常驻 attach |
| 首窗 500 行对运行中脚本很快被 `maxLines=200` 截断 | 既有行为（本次未改窗口行数）；截断后走 stale 重建路径，语义不变。若后续要优化需连带调整 `maxLines` |

## 附：探针复现方法

归因数据来自临时 widget 测试探针（已删除，不入库），复现方式：

1. **滚动成本**：桩 `LogMixin` controller 灌入 N 行日志，复刻 `LogContent` 的行渲染并在 `itemBuilder` 里计数；`jumpTo(0)` 归零后分别以 `animateTo`（复刻 `_scrollLogs` 的 `sqrt(distance)*10` 时长公式）与 `jumpTo` 滚到 `maxScrollExtent`，`for` 循环 `tester.pump(16ms)` 推进并用 `Stopwatch` 记每帧真实耗时；对照组给 `ListView.builder` 加 `prototypeItem` / `itemExtent` / 缓存 pattern。
2. **行高矩阵**：在 `Column` 中并排渲染普通 `Text`、未命中 pattern 的 `EasyRichText(selectable)`、命中 pattern 的真实行形态（均含 `Padding(vertical: 1)`），分别以 `titleSmall` / `bodySmall` 样式 `tester.getSize` 测高。

注意：数据为 debug JIT 环境，绝对值只作相对比较；结构性结论（构建行数、行高差）与构建模式无关。
