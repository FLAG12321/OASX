part of nav;

class TreeMenuView extends StatelessWidget {
  const TreeMenuView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GetX<NavCtrl>(builder: (controller) {
      Map<String, List<String>> data = controller.isHomeMenu.value
          ? controller.homeMenuJson
          : controller.scriptMenuJson;
      if (data.isEmpty) {
        // 菜单为空：加载/自动重试中显示加载动画，全部重试失败后才显示失败入口
        return controller.menuLoading.value
            ? _menuLoading(controller, context)
            : _menuLoadError(controller, context);
      }
      return ScreenTypeLayout.builder(
          mobile: (_) => _mobile(controller, data, context),
          tablet: (_) => _mobile(controller, data, context),
          desktop: (_) => _desktop(controller, data));
    });
  }

  // 菜单加载/自动重试中：显示加载动画，避免空态一闪而过让用户误以为失败
  Widget _menuLoading(NavCtrl controller, BuildContext context) {
    return SizedBox(
      width: 180,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(height: 10),
            Text(
              I18n.menu_loading.tr,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  // 菜单加载失败时给出可操作入口，避免用户只能通过重开 OASX 恢复
  Widget _menuLoadError(NavCtrl controller, BuildContext context) {
    return SizedBox(
      width: 180,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 28,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 6),
            Text(
              I18n.menu_load_failed.tr,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            TextButton.icon(
              onPressed: controller.reloadMenus,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(I18n.retry.tr),
            ),
          ],
        ),
      ),
    );
  }

  Widget _desktop(NavCtrl controller, Map<String, List<String>> data) {
    return TreeView(
            data: data,
            onTap: (e) {
              controller.switchContent(e);
            })
        .constrained(width: 180)
        .alignment(Alignment.topLeft)
        .card(margin: const EdgeInsets.all(0))
        .padding(bottom: 10);
  }

  Widget _mobile(NavCtrl controller, Map<String, List<String>> data,
      BuildContext context) {
    return TreeView(
            data: data,
            onTap: (e) {
              controller.switchContent(e);
            })
        .constrained(width: 180)
        .alignment(Alignment.topLeft)
        .padding(top: 30)
        .decorated(color: Theme.of(context).scaffoldBackgroundColor);
  }
}
