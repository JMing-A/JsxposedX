import 'dart:math' as math;

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
    final colorScheme = context.colorScheme;
    final fabOffsetY = 9.h;
    final fabSize = 58.w;
    final bottomBarHeight = 60.h;
    final bottomBarShape = _HalfCircleNotchedShape(
      cornerRadius: 28.r,
      notchMargin: 1.w,
    );

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

    final navItems = [
      (
        label: context.l10n.home,
        outlinedIcon: Icons.home_outlined,
        filledIcon: Icons.home,
      ),
      (
        label: context.l10n.project,
        outlinedIcon: Icons.folder_outlined,
        filledIcon: Icons.folder,
      ),
      (
        label: context.l10n.repository,
        outlinedIcon: Icons.storage_outlined,
        filledIcon: Icons.storage,
      ),
      (
        label: context.l10n.settings,
        outlinedIcon: Icons.settings_outlined,
        filledIcon: Icons.settings,
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
      extendBody: true,
      floatingActionButtonAnimator: FloatingActionButtonAnimator.noAnimation,
      floatingActionButtonLocation: _LowerCenterDockedFabLocation(
        offsetY: fabOffsetY,
      ),
      floatingActionButton: _CenterDockButton(
        colorScheme: colorScheme,
        size: fabSize,
        onPressed: () {},
      ),
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
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: EdgeInsets.fromLTRB(12.w, 0, 12.w, 10.h),
        child: CustomPaint(
          foregroundPainter: _BottomBarBorderPainter(
            shape: bottomBarShape,
            guestDiameter: fabSize,
            guestCenterY: fabOffsetY,
            color: colorScheme.outline.withValues(
              alpha: context.isDark ? 0.34 : 0.18,
            ),
            strokeWidth: 1.1,
          ),
          child: BottomAppBar(
            height: bottomBarHeight,
            padding: EdgeInsets.zero,
            color: colorScheme.surface,
            surfaceTintColor: Colors.transparent,
            elevation: 12,
            shadowColor: Colors.black.withValues(
              alpha: context.isDark ? 0.50 : 0.20,
            ),
            clipBehavior: Clip.antiAlias,
            shape: bottomBarShape,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 10.w),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: _BottomNavItem(
                      label: navItems[0].label,
                      outlinedIcon: navItems[0].outlinedIcon,
                      filledIcon: navItems[0].filledIcon,
                      selected: currentIndex.value == 0,
                      onTap: () => _changeTab(currentIndex, pageController, 0),
                    ),
                  ),
                  Expanded(
                    child: _BottomNavItem(
                      label: navItems[1].label,
                      outlinedIcon: navItems[1].outlinedIcon,
                      filledIcon: navItems[1].filledIcon,
                      selected: currentIndex.value == 1,
                      onTap: () => _changeTab(currentIndex, pageController, 1),
                    ),
                  ),
                  SizedBox(width: 76.w),
                  Expanded(
                    child: _BottomNavItem(
                      label: navItems[2].label,
                      outlinedIcon: navItems[2].outlinedIcon,
                      filledIcon: navItems[2].filledIcon,
                      selected: currentIndex.value == 2,
                      onTap: () => _changeTab(currentIndex, pageController, 2),
                    ),
                  ),
                  Expanded(
                    child: _BottomNavItem(
                      label: navItems[3].label,
                      outlinedIcon: navItems[3].outlinedIcon,
                      filledIcon: navItems[3].filledIcon,
                      selected: currentIndex.value == 3,
                      onTap: () => _changeTab(currentIndex, pageController, 3),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void _changeTab(ValueNotifier<int> currentIndex, PageController pageController, int index) {
  currentIndex.value = index;
  pageController.animateToPage(
    index,
    duration: const Duration(milliseconds: 300),
    curve: Curves.easeInOut,
  );
}

class _CenterDockButton extends StatelessWidget {
  const _CenterDockButton({
    required this.colorScheme,
    required this.size,
    required this.onPressed,
  });

  final ColorScheme colorScheme;
  final double size;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: 0.22),
            blurRadius: 14,
            spreadRadius: 0.5,
            offset: const Offset(0, 7),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: context.isDark ? 0.14 : 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: FloatingActionButton(
        onPressed: onPressed,
        elevation: 0,
        highlightElevation: 0,
        backgroundColor: Color.alphaBlend(
          Colors.white.withValues(alpha: context.isDark ? 0.05 : 0.10),
          colorScheme.primary,
        ),
        foregroundColor: colorScheme.onPrimary,
        shape: CircleBorder(
          side: BorderSide(
            color: colorScheme.onPrimary.withValues(
              alpha: context.isDark ? 0.10 : 0.18,
            ),
            width: 1,
          ),
        ),
        child: Icon(
          Icons.add_rounded,
          size: 26.sp,
        ),
      ),
    );
  }
}

class _LowerCenterDockedFabLocation extends FloatingActionButtonLocation {
  const _LowerCenterDockedFabLocation({required this.offsetY});

  final double offsetY;

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry scaffoldGeometry) {
    final baseOffset = FloatingActionButtonLocation.centerDocked.getOffset(
      scaffoldGeometry,
    );
    return Offset(baseOffset.dx, baseOffset.dy + offsetY);
  }
}

class _HalfCircleNotchedShape extends NotchedShape {
  const _HalfCircleNotchedShape({
    required this.cornerRadius,
    required this.notchMargin,
  });

  final double cornerRadius;
  final double notchMargin;

  @override
  Path getOuterPath(Rect host, Rect? guest) {
    if (guest == null || !host.overlaps(guest)) {
      return Path()
        ..addRRect(
          RRect.fromRectAndRadius(host, Radius.circular(cornerRadius)),
        );
    }

    return getOuterPathWithGuestMetrics(
      host,
      guestDiameter: guest.width,
      guestCenterY: guest.center.dy,
    );
  }

  Path getOuterPathWithGuestMetrics(
    Rect host, {
    required double guestDiameter,
    required double guestCenterY,
  }) {
    if (guestDiameter <= 0) {
      return Path()
        ..addRRect(
          RRect.fromRectAndRadius(host, Radius.circular(cornerRadius)),
        );
    }

    // ── 使用 Flutter 官方 CircularNotchedRectangle 的数学算法 ──
    final double notchRadius = guestDiameter / 2.0 + notchMargin;

    // 修正坐标：FAB 位置 (guest) 的 X 坐标是 Scaffold 坐标系的，
    // 但 host 是 BottomAppBar 本地坐标系。当 BottomAppBar 被 SafeArea
    // 包裹（有水平 padding）时，X 会有偏移。
    // 由于 FAB 是 centerDocked 且 SafeArea 左右对称，
    // notch 中心 = host 水平中心，Y 用 guest 的 Y（已被 Flutter 正确转换）。
    final Offset center = Offset(host.center.dx, guestCenterY);

    const double s1 = 15.0; // 过渡曲线起始偏移
    const double s2 = 1.0;  // 过渡曲线与圆的间距

    final double r = notchRadius;
    final double a = -1.0 * r - s2;
    final double b = host.top - center.dy;

    final double n2 =
        math.sqrt(b * b * r * r * (a * a + b * b - r * r));
    final double p2xA = ((a * r * r) - n2) / (a * a + b * b);
    final double p2xB = ((a * r * r) + n2) / (a * a + b * b);
    final double p2yA = math.sqrt(r * r - p2xA * p2xA);
    final double p2yB = math.sqrt(r * r - p2xB * p2xB);

    final List<Offset> p = List<Offset>.filled(6, Offset.zero);

    p[0] = Offset(a - s1, b);
    p[1] = Offset(a, b);
    final double cmpx = b < 0 ? -1.0 : 1.0;
    p[2] = cmpx * p2yA > cmpx * p2yB
        ? Offset(p2xA, p2yA)
        : Offset(p2xB, p2yB);
    p[3] = Offset(-1.0 * p[2].dx, p[2].dy);
    p[4] = Offset(-1.0 * p[1].dx, p[1].dy);
    p[5] = Offset(-1.0 * p[0].dx, p[0].dy);

    // 将相对坐标转换为修正后中心的绝对坐标
    for (int i = 0; i < p.length; i++) {
      p[i] = p[i] + center;
    }

    final path = Path();

    // ── 左上角圆角 ──
    path.moveTo(host.left + cornerRadius, host.top);

    // 到 notch 左侧过渡起点
    path.lineTo(p[0].dx, p[0].dy);

    // 左侧贝塞尔过渡曲线
    path.quadraticBezierTo(p[1].dx, p[1].dy, p[2].dx, p[2].dy);

    // 半圆弧
    path.arcToPoint(
      p[3],
      radius: Radius.circular(notchRadius),
      clockwise: false,
    );

    // 右侧贝塞尔过渡曲线
    path.quadraticBezierTo(p[4].dx, p[4].dy, p[5].dx, p[5].dy);

    // 到右上角
    path.lineTo(host.right - cornerRadius, host.top);

    // ── 右上角圆角 ──
    path.arcToPoint(
      Offset(host.right, host.top + cornerRadius),
      radius: Radius.circular(cornerRadius),
    );

    // 右边
    path.lineTo(host.right, host.bottom - cornerRadius);

    // ── 右下角圆角 ──
    path.arcToPoint(
      Offset(host.right - cornerRadius, host.bottom),
      radius: Radius.circular(cornerRadius),
    );

    // 底边
    path.lineTo(host.left + cornerRadius, host.bottom);

    // ── 左下角圆角 ──
    path.arcToPoint(
      Offset(host.left, host.bottom - cornerRadius),
      radius: Radius.circular(cornerRadius),
    );

    // 左边
    path.lineTo(host.left, host.top + cornerRadius);

    // ── 左上角圆角（闭合）──
    path.arcToPoint(
      Offset(host.left + cornerRadius, host.top),
      radius: Radius.circular(cornerRadius),
    );

    path.close();
    return path;
  }
}

class _BottomBarBorderPainter extends CustomPainter {
  const _BottomBarBorderPainter({
    required this.shape,
    required this.guestDiameter,
    required this.guestCenterY,
    required this.color,
    required this.strokeWidth,
  });

  final _HalfCircleNotchedShape shape;
  final double guestDiameter;
  final double guestCenterY;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = shape.getOuterPathWithGuestMetrics(
      rect,
      guestDiameter: guestDiameter,
      guestCenterY: guestCenterY,
    );

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = color;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BottomBarBorderPainter oldDelegate) {
    return oldDelegate.shape != shape ||
        oldDelegate.guestDiameter != guestDiameter ||
        oldDelegate.guestCenterY != guestCenterY ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

class _BottomNavItem extends StatelessWidget {
  const _BottomNavItem({
    required this.label,
    required this.outlinedIcon,
    required this.filledIcon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData outlinedIcon;
  final IconData filledIcon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final iconColor = selected
        ? colorScheme.primary
        : colorScheme.onSurface.withValues(alpha: 0.50);
    final labelColor = selected
        ? colorScheme.primary
        : colorScheme.onSurface.withValues(alpha: 0.44);

    return InkWell(
      borderRadius: BorderRadius.circular(14.r),
      onTap: onTap,
      child: SizedBox(
        height: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              width: 42.w,
              height: 30.h,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12.r),
                color: selected
                    ? colorScheme.primary.withValues(
                        alpha: context.isDark ? 0.16 : 0.10,
                      )
                    : Colors.transparent,
              ),
              child: Icon(
                selected ? filledIcon : outlinedIcon,
                size: 22.sp,
                color: iconColor,
              ),
            ),
            SizedBox(height: 2.h),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 250),
              style: TextStyle(
                fontSize: 10.sp,
                color: labelColor,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                height: 1.2,
              ),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
