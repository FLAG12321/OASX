import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:get/get.dart';
import 'package:styled_widget/styled_widget.dart';
import 'package:flutter_markdown/flutter_markdown.dart' hide MarkdownWidget;
import 'package:markdown_widget/markdown_widget.dart'
    show
        H1Config,
        H2Config,
        H3Config,
        H4Config,
        H5Config,
        H6Config,
        MarkdownConfig,
        MarkdownWidget,
        PConfig;
import 'package:url_launcher/url_launcher.dart';

import 'package:oasx/utils/logger.dart';
import 'package:oasx/utils/platform_utils.dart';
import 'package:oasx/api/api_client.dart';
import 'package:oasx/utils/check_version.dart';
import 'package:oasx/config/translation/i18n_content.dart';
import 'package:oasx/api/home_model.dart';
import 'package:oasx/config/github_readme.dart' show githubReadme;
import 'package:oasx/config/constants.dart';

class HomeView extends StatelessWidget {
  const HomeView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Future.delayed(const Duration(milliseconds: 300), () {
      //延时执行的代码
      checkUpdate().then((value) => null);
    });

    return FutureBuilder<ReadmeGithubModel>(
        future: ApiClient().getGithubReadme(),
        builder:
            (BuildContext context, AsyncSnapshot<ReadmeGithubModel> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            // 当Future还未完成时，显示加载中的UI
            return const CircularProgressIndicator();
          } else if (snapshot.hasError) {
            // 当Future发生错误时，显示错误提示的UI
            return Text('Error: ${snapshot.error}');
          } else {
            // 当Future成功完成时，显示数据
            String content = snapshot.data?.content ?? githubReadme;
            return MarkdownWidget(
              data: content,
              config: _homeMarkdownConfig(context),
            ).paddingAll(10);
          }
        });
  }

  /// v0.3.3 的首页直接继承全局 LatoLato；当前全局主题改为 CascadiaCode 后，
  /// MarkdownWidget 的默认字号、标题 divider 与段落间距虽未改变，文字观感却
  /// 变成等宽代码风。仅在首页恢复 LatoLato，并保留包默认的全部度量与深浅色。
  MarkdownConfig _homeMarkdownConfig(BuildContext context) {
    final base = Theme.of(context).brightness == Brightness.dark
        ? MarkdownConfig.darkConfig
        : MarkdownConfig.defaultConfig;
    const fontFamily = 'LatoLato';
    return base.copy(configs: [
      H1Config(style: base.h1.style.copyWith(fontFamily: fontFamily)),
      H2Config(style: base.h2.style.copyWith(fontFamily: fontFamily)),
      H3Config(style: base.h3.style.copyWith(fontFamily: fontFamily)),
      H4Config(style: base.h4.style.copyWith(fontFamily: fontFamily)),
      H5Config(style: base.h5.style.copyWith(fontFamily: fontFamily)),
      H6Config(style: base.h6.style.copyWith(fontFamily: fontFamily)),
      PConfig(textStyle: base.p.textStyle.copyWith(fontFamily: fontFamily)),
    ]);
  }

  Future<void> checkUpdate() async {
    if (!kReleaseMode) {
      return;
    }
    if (PlatformUtils.isWeb) {
      return;
    }
    // 获取版本信息
    GithubVersionModel githubVersionModel =
        await ApiClient().getGithubVersion();
    String currentVersion = await getCurrentVersion();
    String githubVersion = githubVersionModel.version ?? 'v0.0.0';
    printInfo(info: 'Github Version: $githubVersion');
    String githubUpdateInfo = githubVersionModel.body ?? 'Something wrong';

    // 对比
    Widget goOasxRelease = TextButton(
        onPressed: () async => {await launchUrl(Uri.parse(oasxRelease))},
        child: Text(I18n.go_oasx_release.tr));
    if (!compareVersion(currentVersion, githubVersion)) {
      return;
    }
    // 判断是否是微软商店，现在的时间大于发布的时间三天代表有新的版本
    if (await PlatformUtils().isInstalledFromMicrosoftStore()) {
      logger.i('You are installed from Microsoft Store');
      try {
        DateTime currentTime = DateTime.now();
        DateTime? dateTimeUpdate =
            DateTime.tryParse(githubVersionModel.updatedAt ?? '');
        Duration difference = currentTime.difference(dateTimeUpdate!);
        if (difference.inDays > 3) {
          // 日志打印： 当前时间和发布时间过去了多少天
          logger.i('Difference in days: ${difference.inDays}');
        } else {
          return;
        }
      } catch (e) {
        logger.e('Check Update Error: $e');
        return;
      }
    }

    //
    Widget dialog = SingleChildScrollView(
            child: <Widget>[
      Text('${I18n.latest_version.tr}: $githubVersion'),
      Text('${I18n.current_version.tr}: $currentVersion'),
      goOasxRelease,
      MarkdownBody(data: githubUpdateInfo),
    ].toColumn(crossAxisAlignment: CrossAxisAlignment.start))
        .constrained(height: 300, width: 300);
    Get.defaultDialog(title: I18n.find_new_version.tr, content: dialog);
  }
}
