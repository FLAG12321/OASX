import 'package:flutter_nb_net/flutter_net.dart';
import 'package:get/get.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:dio_cache_interceptor_file_store/dio_cache_interceptor_file_store.dart';
import 'package:oasx/api/api_interceptor.dart';

import 'package:oasx/component/dio_http_cache/dio_http_cache.dart';
import 'package:oasx/config/translation/i18n.dart';
import 'package:oasx/config/translation/i18n_content.dart';
import 'package:oasx/utils/check_version.dart';
import 'package:oasx/config/constants.dart';
import 'package:oasx/controller/settings.dart';
import './home_model.dart';
import './script_log_models.dart';

/// common result
class ApiResult<T> {
  final T? data;
  final String? error;
  final int? code;

  bool get isSuccess => data != null;

  ApiResult.success(this.data)
      : error = null,
        code = null;

  ApiResult.failure(this.error, [this.code]) : data = null;
}

/// 脚本启停结果：是否成功 + 已本地化的失败原因。
/// 启停接口成功时无响应体，`ApiResult.isSuccess`（data != null）会把 200 误判为失败，
/// 因此单独用这个类型表达结果，调用方据此决定中间态是落定还是回落。
class ScriptActionResult {
  final bool ok;
  final String? reason;

  const ScriptActionResult(this.ok, [this.reason]);
}

class ApiClient {
  // 单例
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;
  ApiClient._internal() {
    NetOptions.instance
        .setConnectTimeout(const Duration(seconds: 3))
        .enableLogger(false)
        .addInterceptor(DioCacheInterceptor(
            options: CacheOptions(
          store:
              FileCacheStore(Get.find<SettingsController>().temporaryDirectory),
          policy: CachePolicy.request,
          hitCacheOnErrorExcept: [401, 403],
          maxStale: const Duration(days: 7),
          priority: CachePriority.normal,
          cipher: null,
          keyBuilder: CacheOptions.defaultCacheKeyBuilder,
          allowPostMethod: false,
        )))
        .addInterceptor(ApiInterceptor())
        .create();
  }

  // http://$address 地址的前缀开头
  String address = '127.0.0.1:22288';

  void setAddress(String address) {
    this.address = address;
    NetOptions.instance.dio.options.baseUrl = address;
  }

  /// common request method
  Future<ApiResult<T>> request<T>(Future<Result<T>> Function() apiFn) async {
    try {
      final res = await apiFn();
      return res.when(
        success: (data) => ApiResult.success(data),
        failure: (msg, code) {
          printError(info: '${I18n.network_error_code}: $msg | $code'.tr);
          switch (code) {
            case 403:
              break;
            case 404:
              showNetErrCodeSnackBar(I18n.network_not_found.tr, code);
              break;
            default:
              showNetErrCodeSnackBar(msg, code);
              break;
          }
          return ApiResult.failure(msg, code);
        },
      );
    } catch (e) {
      printError(info: '${I18n.network_error.tr}: $e');
      showNetErrSnackBar();
      return ApiResult.failure(e.toString());
    }
  }

// ----------------------------------   服务端地址测试   ----------------------------------
  Future<bool> testAddress() async {
    final res = await request(() => get('/test'));
    return res.isSuccess && res.data == 'success';
  }

  // 静默探测：不弹网络错误 snackbar，供开机自启轮询与自启配置面板使用
  // （spec §5：轮询期间与面板探测失败均不得刷屏错误提示）
  Future<bool> testAddressSilent() async {
    try {
      final res = await get('/test');
      return res.when(
        success: (data) => data == 'success',
        failure: (msg, code) => false,
      );
    } catch (_) {
      return false;
    }
  }

  Future<bool> killServer() async {
    final res = await request(() => get('/home/kill_server'));
    return res.isSuccess && res.data == 'success';
  }

// ----------------------------------   杂接口  --------------------------------------------
  Future<bool> notifyTest(String setting, String title, String content) async {
    final res = await request(() => post(
          '/home/notify_test',
          queryParameters: {
            'setting': setting,
            'title': title,
            'content': content
          },
        ));
    if (res.isSuccess && res.data == true) {
      Get.snackbar(I18n.notify_test_success.tr, '');
      return true;
    }
    Get.snackbar(I18n.notify_test_failed.tr, res.data.toString());
    return false;
  }

  Future<GithubVersionModel> getGithubVersion() async {
    final res = await request(() => get(
          updateUrlGithub,
          options: buildCacheOptions(const Duration(days: 7)),
          decodeType: GithubVersionModel(),
        ));
    return res.isSuccess ? res.data : GithubVersionModel();
  }

  Future<ReadmeGithubModel> getGithubReadme() async {
    final res = await request(() => get(
          readmeUrlGithub,
          options: buildCacheOptions(const Duration(days: 7),
              options: Options(extra: {"cache": true})),
          decodeType: ReadmeGithubModel(),
        ));
    return res.isSuccess ? res.data : ReadmeGithubModel();
  }

  // 更新器相关的四个 HTTP 端点（/home/update_info、/home/execute_update、
  // /home/update_progress、/home/update_config）已移除：更新器改为由
  // UpdaterLauncher 直接 spawn `python -m deploy.update`。
  // 原因是 server 进程自己 preload 了 onnxruntime、锁着
  // onnxruntime_providers_shared.dll，走 HTTP 让它换 ORT 包必然 WinError 5。
  // 详见 lib/service/updater_launcher.dart 的说明。

  Future<bool> putChineseTranslate() async {
    final res = await request(() => put(
          '/home/chinese_translate',
          data: Messages().all_cn_translate,
        ));
    return res.isSuccess && res.data == true;
  }

  /// 只保留合法的字符串条目；后端异常或手工误填时字段可能缺失/含非字符串值，
  /// 这里兜底防止 cast 异常中断 NavCtrl.onInit 导致导航空白
  Map<String, String> _stringEntries(dynamic raw) {
    if (raw is! Map) return <String, String>{};
    final result = <String, String>{};
    raw.forEach((key, value) {
      if (value is String) {
        result[key.toString()] = value;
      }
    });
    return result;
  }

  Future<Map<String, Map<String, String>>> getAdditionalTranslate() async {
    final res = await request(() => get('/home/additional_translate'));
    Map<String, Map<String, String>> result = {};
    if (res.isSuccess && res.data is Map) {
      final zh = _stringEntries(res.data["zh-CN"]);
      final en = _stringEntries(res.data["en-US"]);
      // 两语言均为空（后端无补充翻译或异常兜底响应）时返回空 map，
      // 让调用方跳过应用与写缓存，避免覆盖掉本地已有的缓存翻译
      if (zh.isNotEmpty || en.isNotEmpty) {
        result["zh-CN"] = zh;
        result["en-US"] = en;
      }
    }
    return result;
  }

// ----------------------------------   菜单项管理   ----------------------------------
  Future<Map<String, List<String>>> getScriptMenu() async {
    final res = await request(() => get('/script_menu'));
    return ((res.data ?? {}) as Map).map((k, v) =>
        MapEntry(k.toString(), (v as List).map((e) => e.toString()).toList()));
  }

  Future<Map<String, List<String>>> getHomeMenu() async {
    final res = await request(() => get('/home/home_menu'));
    return ((res.data ?? {}) as Map).map((k, v) =>
        MapEntry(k.toString(), (v as List).map((e) => e.toString()).toList()));
  }

// ----------------------------------   配置文件管理   ----------------------------------
  Future<List<String>> getConfigList() async {
    final res = await request(() => get('/config_list'));
    return ['Home', ...(res.data?.cast<String>() ?? [])];
  }

  Future<List<String>> getScriptList() async {
    final res = await request(() => get('/config_list'));
    return [...(res.data?.cast<String>() ?? [])];
  }

  Future<String> getNewConfigName() async {
    final res = await request(() => get('/config_new_name'));
    return res.isSuccess ? res.data : '';
  }

  Future<List<String>> configCopy(String newName, String template) async {
    final res = await request(() => post(
          '/config_copy',
          queryParameters: {'file': newName, 'template': template},
        ));
    return ['Home', ...(res.data?.cast<String>() ?? [])];
  }

  Future<List<String>> getConfigAll() async {
    final res = await request(() => get('/config_all'));
    return res.data?.cast<String>() ?? ['template'];
  }

  Future<bool> deleteConfig(String name) async {
    final res = await request(() => delete(
          '/config',
          queryParameters: {'name': name},
        ));
    return res.isSuccess && res.data;
  }

  Future<bool> renameConfig(String oldName, String newName) async {
    final res = await request(() => put(
          '/config',
          queryParameters: {'old_name': oldName, 'new_name': newName},
        ));
    return res.isSuccess && res.data;
  }

// ---------------------------------   脚本实例管理   ----------------------------------

  Future<Map<String, dynamic>> getScriptTask(
      String scriptName, String taskName) async {
    final res = await request(() => get('/$scriptName/$taskName/args'));
    return res.data ?? {};
  }

  Future<bool> putScriptArg(
    String scriptName,
    String taskName,
    String groupName,
    String argumentName,
    String type,
    dynamic value,
  ) async {
    final res = await request(() => put(
          '/$scriptName/$taskName/$groupName/$argumentName/value',
          queryParameters: {'types': type, 'value': value},
        ));
    return res.isSuccess && res.data == true;
  }

  // 中文注释：首期严格采用 snapshot-first，这里只暴露日期列表与某日快照接口，
  // 不提前引入 today SSE，避免实现边界漂移。
  Future<List<String>> getScriptStatisticsDates(String scriptName) async {
    final path = '/stats/${Uri.encodeComponent(scriptName)}/dates';
    final res = await request(() => get(path));
    final rawDates = res.data is Map ? res.data['dates'] : null;
    return rawDates is List
        ? rawDates
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toList()
        : <String>[];
  }

  // 中文注释：首期只读取选中日期的 snapshot 原始数据，后续由 stats 模型层负责解析。
  Future<Map<String, dynamic>> getScriptStatisticsDayRaw(
    String scriptName,
    String dateKey,
  ) async {
    final path = '/stats/${Uri.encodeComponent(scriptName)}';
    final res = await request(
      () => get(path, queryParameters: {'date': dateKey}),
    );
    return res.data is Map
        ? Map<String, dynamic>.from(res.data as Map)
        : <String, dynamic>{};
  }

  /// 构造脚本日志窗口路径；单测只覆盖此纯 helper，避免触发真实网络。
  static String buildScriptLogWindowPath(String scriptName) {
    return '/logs/${Uri.encodeComponent(scriptName)}';
  }

  /// 构造脚本日志窗口 query；cursor 为空表示打开最新窗口。
  static Map<String, dynamic> buildScriptLogWindowQuery({
    String? cursor,
    int limitLines = 500,
  }) {
    final query = <String, dynamic>{'limit_lines': limitLines};
    if (cursor != null && cursor.isNotEmpty) {
      query['cursor'] = cursor;
    }
    return query;
  }

  // 中文注释：拉取脚本历史日志窗口；失败返回 null，由上层保留 WebSocket 实时日志。
  Future<ScriptLogWindow?> getScriptLogWindow(
    String scriptName, {
    String? cursor,
    int limitLines = 500,
  }) async {
    final res = await request(
      () => get(
        buildScriptLogWindowPath(scriptName),
        queryParameters: buildScriptLogWindowQuery(
          cursor: cursor,
          limitLines: limitLines,
        ),
      ),
    );
    if (!res.isSuccess || res.data is! Map) {
      // 中文注释：协议异常（成功但非 Map body）打印便于排查，仍 fallback 到 null 不阻塞。
      if (res.isSuccess && res.data is! Map) {
        printError(info: 'script log window payload is not a map: ${res.data.runtimeType}');
      }
      return null;
    }
    return ScriptLogWindow.fromWindowJson(
      Map<String, dynamic>.from(res.data as Map),
    );
  }

// ---------------------------------   脚本启停   ----------------------------------

  /// 启动脚本实例。后端 `GET /{name}/start` 在子进程 generation 握手完成后才返回
  /// （最长约 5s），所以这里 await 落地即代表启动结果已确定，前端可据此结束
  /// 「启动中」中间态；原实现走 WS 单向 'start'，既没有结束信号也拿不到失败原因。
  Future<ScriptActionResult> startScript(String name) {
    return _scriptAction(
        '/${Uri.encodeComponent(name)}/start', I18n.script_start_failed);
  }

  /// 停止脚本实例。后端在 `script_process.stop()` 完成后才返回，语义同上。
  Future<ScriptActionResult> stopScript(String name) {
    return _scriptAction(
        '/${Uri.encodeComponent(name)}/stop', I18n.script_stop_failed);
  }

  /// 启停接口共用通路。这里不复用 [request]：
  /// 1. 成功时后端无响应体，`ApiResult.isSuccess` 会把 200 误判为失败；
  /// 2. 需要按 404/409/500/503 给出针对性文案，而不是通用「网络错误 + 码」。
  Future<ScriptActionResult> _scriptAction(String path, String failedTitle) async {
    try {
      final res = await get(path);
      return res.when(
        success: (_) => const ScriptActionResult(true),
        failure: (msg, code) {
          final reason = _scriptActionReason(code, msg);
          printError(info: '${failedTitle.tr}: $msg | $code');
          Get.snackbar(failedTitle.tr, reason,
              duration: const Duration(seconds: 3));
          return ScriptActionResult(false, reason);
        },
      );
    } catch (e) {
      // 连接不上（server 已退出）等场景：dio 抛异常而非返回 failure
      printError(info: '${failedTitle.tr}: $e');
      final reason = I18n.network_connect_timeout.tr;
      Get.snackbar(failedTitle.tr, reason,
          duration: const Duration(seconds: 3));
      return ScriptActionResult(false, reason);
    }
  }

  /// 把后端状态码映射成用户能看懂的原因；未登记的码回落为「错误代码 + 原始信息」。
  /// 码的含义见 script_router.script_start：404 配置不存在、409 拒绝启动/身份冲突、
  /// 500 握手超时或配置损坏、503 配置锁超时。
  String _scriptActionReason(int code, String msg) {
    return switch (code) {
      404 => I18n.script_action_not_found.tr,
      409 => I18n.script_action_conflict.tr,
      500 => I18n.script_action_server_error.tr,
      503 => I18n.script_action_lock_timeout.tr,
      _ => '${I18n.network_error_code.tr}: $code | $msg',
    };
  }

// ---------------------------------   Snackbar --------------------------------
  void showDialog(String title, String content) {
    Get.snackbar(title, content);
  }

  void showNetErrSnackBar() {
    Get.snackbar(I18n.network_error.tr, I18n.network_connect_timeout.tr,
        duration: const Duration(seconds: 2));
  }

  void showNetErrCodeSnackBar(String msg, int code) {
    Get.snackbar(
        I18n.network_error.tr, '${I18n.network_error_code.tr}: $code | $msg',
        duration: const Duration(seconds: 2));
  }
}
