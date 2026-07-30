part of server;

class ServerController extends GetxController with LogMixin {
  final rootPathServer = ''.obs;
  final rootPathAuthenticated = true.obs;
  final showDeploy = true.obs;

  final log = ''.obs;
  final deployContent = ''.obs;
  // server 拉起器实例：重复启动前先 kill 旧实例，避免旧命令进程残留
  ServerLauncher? _launcher;

  @override
  void onInit() {
    rootPathServer.value =
        Get.find<SettingsController>().storage.read('rootPathServer') ??
            'Please set OAS root path';
    rootPathAuthenticated.value = authenticatePath(rootPathServer.value);
    if (rootPathAuthenticated.value) {
      readDeploy();
    }
    super.onInit();
  }

  void updateRootPathServer(String value) {
    if (authenticatePath(value)) {
      rootPathAuthenticated.value = true;
    } else {
      rootPathAuthenticated.value = false;
    }
    // value = value.replaceAll('\\', '\\\\');
    rootPathServer.value = value;
    Get.find<SettingsController>()
        .storage
        .write('rootPathServer', rootPathServer.value);
    if (rootPathAuthenticated.value) {
      readDeploy();
    }
  }

  // 目录结构校验逻辑已抽至 ServerLauncher（与开机自启自动流程共用）
  bool authenticatePath(String root) {
    return ServerLauncher.validatePath(root);
  }

  void run() {
    clearLog();
    // 拉起逻辑抽至 ServerLauncher，与开机自启自动流程共用；日志仍回本页。
    // 替换前 dispose 旧实例，避免其 shell 命令与日志流监听残留
    _launcher?.dispose();
    _launcher = ServerLauncher(rootPath: rootPathServer.value, onLog: addLog);
    _launcher!.launch();
  }

  @override
  void onClose() {
    // 控制器销毁时释放拉起器资源（在途命令 + 日志流）
    _launcher?.dispose();
    _launcher = null;
    super.onClose();
  }

  void readDeploy() {
    String filePath = '${rootPathServer.value}\\config\\deploy.yaml';
    try {
      File file = File(filePath);
      if (file.existsSync()) {
        deployContent.value = file.readAsStringSync();
        return;
      } else {
        deployContent.value = 'File not found';
        return;
      }
    } catch (e) {
      deployContent.value = 'Error reading file: $e';
      return;
    }
  }

  void writeDeploy(String value) {
    String filePath = '${rootPathServer.value}\\config\\deploy.yaml';
    deployContent.value = value;
    try {
      File file = File(filePath);
      if (file.existsSync()) {
        file.writeAsStringSync(deployContent.value);
        return;
      } else {
        deployContent.value = 'File not found';
        return;
      }
    } catch (e) {
      deployContent.value = 'Error writing file: $e';
      return;
    }
  }
}
