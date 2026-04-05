import 'package:JsxposedX/common/pages/toast.dart';
import 'package:JsxposedX/common/widgets/app_bottom_sheet.dart';
import 'package:JsxposedX/common/widgets/loading.dart';
import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/core/providers/theme_provider.dart';
import 'package:JsxposedX/core/utils/procedure_utils.dart';
import 'package:JsxposedX/features/home/presentation/widgets/notice_bottom_sheet.dart';
import 'package:JsxposedX/features/home/presentation/pages/tabs/home_tab.dart';
import 'package:JsxposedX/features/home/presentation/pages/tabs/project_tab.dart';
import 'package:JsxposedX/features/home/presentation/pages/tabs/repository_tab/repository_tab.dart';
import 'package:JsxposedX/features/home/presentation/pages/tabs/settings_tab.dart';
import 'package:JsxposedX/features/home/presentation/providers/check_query_provider.dart';
import 'package:JsxposedX/features/home/presentation/utils/update_check_helper.dart';
import 'package:JsxposedX/features/home/presentation/widgets/select_app_sheet.dart';
import 'package:JsxposedX/features/home/presentation/widgets/update_check_dialog.dart';
import 'package:JsxposedX/features/project/presentation/providers/project_action_provider.dart';
import 'package:JsxposedX/features/project/presentation/providers/project_query_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class HomePage extends HookConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 当前选中的索引
    final currentIndex = useState(0);

    final versionCode = useState(0);
    // PageView 控制器
    final pageController = usePageController(initialPage: 0);
    // 页面列表
    final pages = [
      const HomeTab(),
      const ProjectTab(),
      const RepositoryTab(),
      const SettingsTab(),
    ];

    // Tab 标题列表
    final tabTitles = [
      context.l10n.home,
      context.l10n.project,
      context.l10n.repository,
      context.l10n.settings,
    ];

    // 底部导航栏项目
    final bottomNavItems = [
      BottomNavigationBarItem(
        icon: Icon(Icons.home_outlined, size: 24.sp),
        activeIcon: Icon(Icons.home, size: 24.sp),
        label: context.l10n.home,
      ),
      BottomNavigationBarItem(
        icon: Icon(Icons.folder_outlined, size: 24.sp),
        activeIcon: Icon(Icons.folder, size: 24.sp),
        label: context.l10n.project,
      ),
      BottomNavigationBarItem(
        icon: Icon(Icons.storage_outlined, size: 24.sp),
        activeIcon: Icon(Icons.storage, size: 24.sp),
        label: context.l10n.repository,
      ),
      BottomNavigationBarItem(
        icon: Icon(Icons.settings_outlined, size: 24.sp),
        activeIcon: Icon(Icons.settings, size: 24.sp),
        label: context.l10n.settings,
      ),
    ];

    useEffect(() {
      Future.microtask(() async {
        versionCode.value = await ProcedureUtils.getBuildNumber();
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        AppBottomSheet.show(
          context: context,
          title: context.l10n.notice,
          child: const NoticeBottomSheet(),
        );

        Future.microtask(() async {
          try {
            final localBuildNumber = versionCode.value > 0
                ? versionCode.value
                : await ProcedureUtils.getBuildNumber();
            final update = await ref.read(updateInfoProvider.future);

            if (!context.mounted) return;
            if (!shouldShowUpdateDialog(
              update: update,
              localBuildNumber: localBuildNumber,
            )) {
              return;
            }

            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!context.mounted) return;
              UpdateCheckDialog.show(context, update: update);
            });
          } catch (error, stackTrace) {
            debugPrint('Failed to check update: $error');
            debugPrintStack(stackTrace: stackTrace);
          }
        });
      });

      return null;
    }, []);

    return Scaffold(
      appBar: AppBar(
        title: Text(tabTitles[currentIndex.value]),actions: [
          switch (currentIndex.value) {
            0 => IconButton(
              onPressed: () {
                ref.read(themeProvider.notifier).toggleTheme();
              },
              icon: Icon(!context.isDark ? Icons.dark_mode : Icons.light_mode),
            ),
            1 => IconButton(
              onPressed: () {
                SelectAppSheet.show(
                  context,
                  addToLSPosedScope: true, // 启用自动添加到 LSPosed scope
                  onSelected: (appInfo) async {
                    // 1. 立即关闭选择弹窗（不要在回调里写重逻辑）
                    if (Navigator.canPop(context)) {
                      Navigator.pop(context);
                    }

                    // 2. 利用 microtask 确保弹窗关闭的帧提交完成后，再执行显示加载框和业务逻辑
                    Future.microtask(() async {
                      // 确保加载框显示
                      Loading.show();

                      try {
                        // 3. 这里的异步调用因为已经脱离了弹窗回调的 UI 帧竞争，加载框会先渲染出来
                        await ref.read(
                          createProjectProvider(
                            packageName: appInfo.packageName,
                          ).future,
                        );

                        // 4. 刷新项目列表
                        ref.invalidate(projectsProvider);

                        // 5. 提示成功
                        if (!context.mounted) return;
                        ToastMessage.show(
                          context.l10n.alreadySelected(appInfo.name),
                        );
                      } catch (e) {
                        ToastMessage.show("error: $e");
                      } finally {
                        // 6. 隐藏加载中
                        Loading.hide();
                      }
                    });
                  },
                );
              },
              icon: Icon(Icons.add),
            ),
            _ => SizedBox.shrink(),
          },
        ],
        centerTitle: true,
      ),
      body: Padding(
        padding: EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        child: PageView(
          controller: pageController,
          onPageChanged: (index) {
            currentIndex.value = index;
          },
          children: pages,
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentIndex.value,
        onTap: (index) {
          currentIndex.value = index;
          pageController.animateToPage(
            index,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        },
        items: bottomNavItems,
        type: BottomNavigationBarType.fixed,
        selectedFontSize: 12.sp,
        unselectedFontSize: 11.sp,
        selectedItemColor: context.colorScheme.primary,
        unselectedItemColor: context.colorScheme.onSurface.withValues(
          alpha: 0.6,
        ),
      ),
    );
  }
}
