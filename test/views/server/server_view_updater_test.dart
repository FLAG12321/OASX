// test/views/server/server_view_updater_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// 中文注释：锁住服务页「更新器」面板与两个 FAB 的结构约束。
//
// ServerView 的 build 需要 ServerController / SettingsController / GetStorage /
// AutoStartService 一整套依赖，真正 pumpWidget 起来成本极高且脆弱，
// 所以按源码做静态门禁 —— 这里防的每一条都会造成真实故障：
//
// 1. 两个 FAB 缺 heroTag：Hero 抛「multiple heroes share the same tag」直接崩页。
// 2. GlobalKey 建在 build() 里：每次 rebuild 换新 key，FAB 触发的程序化展开静默失效。
// 3. 用回 ExpansionTileGroup：它的 copyWith 会把 ExpansionTileCard 降级成基类，
//    Card 外壳永不渲染，面板只剩页面底色（实测截图采样：面板 (255,251,255)
//    等于 scaffoldBackgroundColor，而日志 Card 是 (248,242,250)）。
// 4. 面板标题不是 titleMedium：与同组其它面板层级不一致。
void main() {
  late String source;
  late String panelSource;

  setUpAll(() {
    source = File('lib/views/server/server_view.dart').readAsStringSync();
    panelSource = File('lib/views/server/updater_panel.dart').readAsStringSync();
  });

  group('FAB 结构', () {
    test('两个 FAB 都必须显式设 heroTag', () {
      // 同屏多个 FloatingActionButton 共用默认 tag 会让 Hero 抛异常崩页
      expect(source.contains("heroTag: 'UPDATE'"), isTrue,
          reason: '更新 FAB 缺 heroTag 会与启动 server FAB 冲突崩溃');
      expect(source.contains("heroTag: 'START_SERVER'"), isTrue,
          reason: '启动 server FAB 缺 heroTag 会与更新 FAB 冲突崩溃');
    });

    test('heroTag 必须互不相同', () {
      final tags = RegExp(r"heroTag: '([A-Z_]+)'")
          .allMatches(source)
          .map((m) => m.group(1))
          .toList();
      expect(tags.length, greaterThanOrEqualTo(2), reason: '应有两个 FAB');
      expect(tags.toSet().length, tags.length, reason: 'heroTag 重复会触发 Hero 冲突');
    });

    test('更新 FAB 在更新中必须禁用', () {
      // 并发跑 git 会互相踩 .git/*.lock
      expect(source.contains('onPressed: running'), isTrue,
          reason: '更新中必须 onPressed: null，否则可并发触发 git');
    });

    test('两个 FAB 必须同为 FloatingActionButton，样式才一致', () {
      final count = RegExp(r'FloatingActionButton\(').allMatches(source).length;
      expect(count, 2, reason: '更新与启动 server 都应是 FAB，样式保持一致');
    });

    test('手动更新 FAB 在启动服务 FAB 左边（横排而非竖排）', () {
      // 用户要求：手动更新放到启动服务左边，而不是原来的上下排列。
      // 竖排时更新在上、启动在下，视觉上把主操作（启动）压在下面。
      // 锁定 _actionButtons 里更新与启动同在一个 Row、且更新在前。
      final actionStart = source.indexOf('Widget _actionButtons()');
      expect(actionStart, greaterThanOrEqualTo(0));
      final rowStart = source.indexOf('return Row(', actionStart);
      expect(rowStart, greaterThanOrEqualTo(0),
          reason: '_actionButtons 应为横向排列（Row），不是竖排的 Column');
      // 限定在 Row 的 children 里比较顺序，避免溢出到后面两个 FAB 的定义
      final rowBody = source.substring(rowStart, rowStart + 300);
      final updateIdx = rowBody.indexOf('updateButton()');
      final startIdx = rowBody.indexOf('startServerButton()');
      expect(updateIdx, greaterThanOrEqualTo(0));
      expect(startIdx, greaterThan(updateIdx),
          reason: '手动更新应出现在启动服务左边');
    });
  });

  group('折叠面板程序化展开', () {
    test('GlobalKey 必须是 State 字段而非 build 内局部变量', () {
      // 建在 build() 里每次重建都换新 key，group 的 didUpdateWidget 会重建
      // 内部 key 列表，FAB 触发的 expand() 拿到的 currentState 为 null
      expect(
          source.contains(
              'final _deployKey = GlobalKey<ExpansionTileCoreState>()'),
          isTrue,
          reason: 'key 必须跨 rebuild 稳定');
      expect(
          source.contains(
              'final _updaterKey = GlobalKey<ExpansionTileCoreState>()'),
          isTrue,
          reason: 'key 必须跨 rebuild 稳定');
    });

    test('ServerView 必须是 StatefulWidget 才能持有稳定的 key', () {
      expect(source.contains('class ServerView extends StatefulWidget'), isTrue,
          reason: 'StatelessWidget 无法持有跨 rebuild 稳定的 GlobalKey');
    });

    test('两个面板都必须把 key 传给 expansionKey', () {
      // ExpansionTileGroup 用 children[index].expansionKey ?? GlobalKey()，
      // 不传就拿不到外部可控的 currentState
      expect(source.contains('expansionKey: _deployKey'), isTrue);
      expect(source.contains('expansionKey: _updaterKey'), isTrue);
    });

    test('更新 FAB 展开更新器面板；启动 server FAB 展开服务启动日志', () {
      expect(source.contains('_expandOnly(_updaterKey)'), isTrue,
          reason: '点更新要展开更新器面板，否则用户看不到更新在跑什么');

      // 启动 server 后用户要看的是跑起来的输出，不是 deploy.yaml，
      // 所以这里展开的是「服务启动日志」而非「服务启动配置」。
      // 日志不是折叠面板，它由 LogWidget 自己的 collapseLog 控制。
      final start = source.indexOf('Widget startServerButton()');
      expect(start, greaterThanOrEqualTo(0));
      final body = source.substring(start, start + 900);
      expect(body.contains('collapseLog.value = false'), isTrue,
          reason: '启动 server 必须展开服务启动日志（LogWidget 的 collapseLog）');
      expect(body.contains('_expandOnly(_deployKey)'), isFalse,
          reason: '启动 server 不该展开服务启动配置，用户要看的是日志输出');
      // 配置面板全部收起，否则展开着会把 maxHeight-200 的日志挤出视口
      expect(body.contains('key.currentState?.collapse()'), isTrue,
          reason: '需收起配置面板给日志腾出视口');
    });

    test('互斥收起必须自己实现，不能依赖 ExpansionTileGroup', () {
      // ExpansionTileGroup.initState 会对每个 child 调 copyWith() 注入自己的
      // onExpansionChanged，而 ExpansionTileItem.copyWith 硬编码
      // `return ExpansionTileItem(...)`（非虚函数，子类无法覆写），
      // 会把 ExpansionTileCard 降级成基类 —— Card 外壳永不渲染。
      // 所以这里必须不用 group，改由 _collapseOthers 手动互斥。
      // 只查实际使用（构造调用），不查注释——注释里正解释着为什么不用它
      expect(source.contains('ExpansionTileGroup('), isFalse,
          reason: 'group 的 copyWith 会把 .card 降级成基类，Card 外壳会失效');
      expect(source.contains('void _collapseOthers('), isTrue,
          reason: '不用 group 就必须自己实现互斥收起');
      // 每个面板都要在展开时收起其余项，否则手风琴只对部分面板生效
      for (final key in ['_pathKey', '_deployKey', '_autoStartKey', '_updaterKey']) {
        expect(source.contains('_collapseOthers($key)'), isTrue,
            reason: '$key 展开时必须收起其余面板');
      }
    });

    test('_expandOnly 必须显式收起其余项', () {
      // 目标项已展开时 _setExpanded 提前 return、不触发 onExpansionChanged，
      // 只靠回调链收不起其余面板
      final start = source.indexOf('void _expandOnly(');
      expect(start, greaterThanOrEqualTo(0));
      final body = source.substring(start, start + 200);
      expect(body.contains('_collapseOthers(key)'), isTrue,
          reason: '目标项已展开时回调不触发，必须显式收起其余项');
    });
  });

  group('面板样式与服务启动日志一致', () {
    test('四个面板必须直接构造 ExpansionTileCard，而非 .card 工厂', () {
      // ExpansionTileItem.card 工厂的静态返回类型是基类 ExpansionTileItem，
      // 一旦被 copyWith 之类的代码路径处理就会丢掉子类的 Card 外壳；
      // 直接构造子类可让类型系统守住这一点
      final count = RegExp(r'ExpansionTileCard\(').allMatches(source).length;
      expect(count, 4, reason: '识别目录/服务启动配置/自启动/更新器四个面板都要是真 Card');
      expect(source.contains('ExpansionTileItem.card('), isFalse,
          reason: '工厂返回基类类型，用直接构造才能被类型系统守住');
    });

    test('四个面板方法的返回类型必须是 ExpansionTileCard', () {
      // 标成基类会让「Card 外壳被降级」这类问题绕过类型检查
      for (final m in ['path', 'deploy', 'updater', 'autoStart']) {
        expect(source.contains('ExpansionTileCard $m('), isTrue,
            reason: '$m 返回类型标成基类会让 Card 降级问题无法被发现');
      }
    });
  });

  group('面板位置与标题层级', () {
    test('更新器必须与其它配置面板同级且在服务启动日志之前', () {
      final pathIdx = source.indexOf('path(context),');
      final logIdx = source.indexOf('LogWidget(');
      final updaterIdx = source.indexOf('updater(context),');
      expect(pathIdx, greaterThanOrEqualTo(0));
      expect(updaterIdx, greaterThan(pathIdx),
          reason: '更新器应排在其它配置面板之后');
      expect(updaterIdx, lessThan(logIdx),
          reason: '更新器应与其它配置面板同级，位于服务启动日志之前');
    });

    test('更新器面板标题与同组其它面板同款', () {
      // 取 updater 方法体，确认标题样式与 path/deploy/autoStart 一致
      final start = source.indexOf('ExpansionTileCard updater(');
      expect(start, greaterThanOrEqualTo(0));
      final body = source.substring(start, start + 900);
      expect(body.contains('I18n.updater.tr'), isTrue);
      expect(body.contains('panelTitleStyle(context)'), isTrue,
          reason: '面板标题必须走 panelTitleStyle，与同组其它折叠项同级');
    });

    test('四个面板标题都走 panelTitleStyle，且比 titleMedium 大一号', () {
      // 五个框（四面板 + 日志）标题必须同款，散着写必然漂移
      final count =
          RegExp(r'style: panelTitleStyle\(context\)').allMatches(source).length;
      expect(count, 4,
          reason: '识别目录/服务启动配置/自启动/更新器四个面板标题都要用 panelTitleStyle');
      // 大一号 = 只改字号保留 w500；titleLarge 是 22/w400，字重反而变轻
      expect(source.contains('titleMedium?.copyWith(fontSize: 17)'), isTrue,
          reason: '标题应比 titleMedium 默认 16 大一号且保持 w500');
    });

    test('服务启动日志标题与四个面板同字号', () {
      // LogWidget 是共享组件，但两处 overview 用法都传 topPanelLeading
      // 取代了标题，所以这里的 title 样式只在服务页生效。
      // 真实渲染字号由 log_widget_render_test 的对齐/字号用例把关，
      // 这里只锁住「日志标题没有退回主题默认值」。
      final logSource =
          File('lib/component/log/log_widget.dart').readAsStringSync();
      expect(logSource.contains('copyWith(fontSize: 17)'), isTrue,
          reason: '日志标题需与四个面板标题同字号，五个框才一致');
    });

    test('面板内区块标题必须低于面板标题一级', () {
      // 面板标题是 titleMedium(16/w500)，内部区块若也用 titleMedium 层级会塌掉
      expect(panelSource.contains('textTheme.titleSmall'), isTrue,
          reason: 'L2 区块标题应为 titleSmall');
      expect(panelSource.contains('textTheme.labelMedium'), isTrue,
          reason: 'L3 表头应为 labelMedium');
      expect(panelSource.contains('textTheme.bodySmall'), isTrue,
          reason: '正文应为 bodySmall');
      // 面板内部不得再出现 titleMedium，否则与外层面板标题同级
      expect(panelSource.contains('textTheme.titleMedium'), isFalse,
          reason: '面板内用 titleMedium 会与折叠面板标题同字号，层级塌陷');
    });
  });

  group('字号一致性（用户逐项验收过的三处）', () {
    test('Repository / Branch 标签与「当前版本」同一个样式来源', () {
      // 两处都必须走 sectionTitle，散着写字号必然漂移
      expect(panelSource.contains("Text('\${I18n.current_version.tr}"), isTrue);
      final formStart = panelSource.indexOf('Widget _field(');
      expect(formStart, greaterThanOrEqualTo(0),
          reason: '标签应抽成 _field，与输入框成对出现');
      expect(panelSource.contains('Text(label, style: labelStyle)'), isTrue,
          reason: '标签用独立 Text 承载，样式来自 sectionTitle');
      expect(
          panelSource
              .contains('final labelStyle = UpdaterPanel.sectionTitle(context)'),
          isTrue,
          reason: '标签必须与「当前版本」同用 sectionTitle 才能真的同字号');
    });

    test('Repository / Branch 不得走 InputDecoration 浮动标签', () {
      // Material 的浮动标签在有内容时被 Transform 缩放到 _kFinalLabelScale(0.75)
      // （SDK input_decorator.dart），这是几何缩放：光把 labelStyle 设成和
      // 「当前版本」同字号也没用，渲染出来仍只有 0.75 倍。
      expect(panelSource.contains("labelText: 'Repository'"), isFalse,
          reason: '浮动标签会被缩放到 0.75 倍，无法与「当前版本」同字号');
      expect(panelSource.contains("labelText: 'Branch'"), isFalse,
          reason: '浮动标签会被缩放到 0.75 倍，无法与「当前版本」同字号');
    });

    test('更新器面板内容比其余面板再大一号', () {
      // 用户单独要求更新器内部再大一号：这里比 ServerView.panelContentBump(=1) 大
      expect(panelSource.contains('static const double _sizeBump = 2'), isTrue,
          reason: '更新器内部放大量应为 2，比其余面板的 1 再大一号');
      expect(source.contains('static const double panelContentBump = 1'), isTrue,
          reason: '其余面板保持 1，用户此前明确要求把框缩回来');
    });

    test('「开启自启」与「自启动脚本配置」共用同一份标题样式', () {
      final autoStartSource =
          File('lib/views/server/auto_start_settings.dart').readAsStringSync();
      // 共用一个局部变量而不是各写一遍，避免以后改一处漏一处又漂移开。
      // 折行位置随格式化会变，所以把空白压平再比对，别锁死换行
      final flat = autoStartSource.replaceAll(RegExp(r'\s+'), ' ');
      expect(
          flat.contains(
              'final sectionTitleStyle = Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 15)'),
          isTrue,
          reason: '两处标题应共用同一份样式定义');
      final switchCount = RegExp(r'style: sectionTitleStyle')
          .allMatches(autoStartSource)
          .length;
      expect(switchCount, 2,
          reason: '开关标题与区块标题各用一次，共两处');
      // SwitchListTile 的 title 默认走 bodyLarge，不显式给样式就会比区块标题小
      expect(
          autoStartSource.contains(
              'Text(I18n.launchAtStartup.tr, style: sectionTitleStyle)'),
          isTrue,
          reason: '开关标题必须显式给样式，否则回落到 bodyLarge 比区块标题小一号');
    });
  });

  group('可复制性', () {
    test('OAS 根目录必须可选中复制', () {
      // 排查路径问题时要把它贴给别人或粘到资源管理器，普通 Text 一个字都取不出来
      expect(
          source.contains(
              'Expanded(child: SelectableText(controller.rootPathServer.value))'),
          isTrue,
          reason: '根目录应为 SelectableText；外层 Expanded 防长路径在 Row 里溢出');
    });
  });

  group('复用与解耦', () {
    test('Home→Updater 页与服务页共用同一个 UpdaterPanel', () {
      final viewSource =
          File('lib/views/home/updater_view.dart').readAsStringSync();
      expect(viewSource.contains('UpdaterPanel()'), isTrue,
          reason: '两处必须同一份实现，否则状态与日志会不一致');
      expect(source.contains('UpdaterPanel()'), isTrue);
    });

    test('面板不得直连 ApiClient，必须走本地 spawn', () {
      // 走 HTTP 就回到了「server 进程持有 ORT DLL 锁」的死局
      expect(panelSource.contains('ApiClient'), isFalse,
          reason: '更新器必须完全脱离 server 的 HTTP 接口');
      expect(panelSource.contains('UpdaterController'), isTrue);
    });
  });
}
