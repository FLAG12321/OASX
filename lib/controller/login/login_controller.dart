part of login;

class LoginController extends GetxController {
  static bool logined = false;
  var username = ''.obs;
  var password = ''.obs;
  var address = ''.obs;

  GetStorage storage = GetStorage();

  @override
  Future<void> onInit() async {
    username.value = storage.read(StorageKey.username.name) ?? "";
    password.value = storage.read(StorageKey.password.name) ?? "";
    address.value = storage.read(StorageKey.address.name) ?? "";

    // 自动流程激活时让位（server 可能未起，此时自动登录必然失败弹错；
    // 登录跳转时机由 AutoBootService 全权掌控，spec §4.2）。
    // 用静态触发条件判断而非流程状态，消除首帧前后的时序竞态
    final autoBoot = Get.isRegistered<AutoBootService>()
        ? Get.find<AutoBootService>()
        : null;
    final autoBootActive = autoBoot != null &&
        AutoBootService.shouldAutoBoot(
            hasAutostartArg: autoBoot.hasAutostartArg,
            isDesktop: PlatformUtils.isDesktop,
            entryCount: autoBoot.autoScriptEntries.length);
    if (address.value.isNotEmpty && !logined && !autoBootActive) {
      logined = true;
      await login(address.value);
    }
    super.onInit();
  }

  /// 进入主页面
  Future<void> toMain({required Map<String, dynamic> data}) async {
    storage.write(StorageKey.username.name, data['username']);
    storage.write(StorageKey.password.name, data['password']);
    storage.write(StorageKey.address.name, data['address']);
    printInfo(info: data.toString());
    await login(data['address']);
  }

  Future<void> login(String address) async {
    ApiClient().setAddress('http://$address');
    if (await ApiClient().testAddress()) {
      Get.offAllNamed('/main');
    } else {
      Get.snackbar('Error', 'Failed to connect to OAS server');
    }
  }
}
