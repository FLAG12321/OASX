import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/config/translation/i18n.dart';
import 'package:oasx/service/locale_service.dart';

/// 仅混入 DynamicMessages，绕开 LocaleService 对 GetStorage 的依赖
class _FakeService with DynamicMessages {}

void main() {
  test('applyAdditionalTranslate 立即合入内存翻译表', () {
    final service = _FakeService();
    service.applyAdditionalTranslate({
      'zh-CN': {'new_task_key': '新任务'},
      'en-US': {'new_task_key': 'New Task'},
    });
    expect(service.messages.all_cn_translate['new_task_key'], '新任务');
    expect(service.messages.all_us_translate['new_task_key'], 'New Task');
  });

  test('translateUpdate 忽略空字符串值（旧后端/旧缓存兼容）', () {
    final service = _FakeService();
    service.applyAdditionalTranslate({
      'zh-CN': {'empty_key': ''},
      'en-US': {},
    });
    // 空值不进入翻译表，.tr 回退显示 key 原文而非空白
    expect(service.messages.all_cn_translate.containsKey('empty_key'), false);
  });

  test('镜像纯净性契约：运行时合入不影响 Messages() 新实例', () {
    final service = _FakeService();
    service.applyAdditionalTranslate({
      'zh-CN': {'runtime_only_key': '运行时翻译'},
      'en-US': {},
    });
    // putChineseTranslate 上传镜像用的是 Messages() 新实例（编译期内置翻译），
    // 后端靠「镜像不含运行时合入条目」区分前端内置与真缺失，此契约破坏会
    // 静默导致缺失 key 不再被发现
    expect(Messages().all_cn_translate.containsKey('runtime_only_key'), false);
  });
}
