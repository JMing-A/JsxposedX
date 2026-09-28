import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/features/home/presentation/providers/desktop_locale_provider.dart';
import 'package:JsxposedX/features/home/presentation/providers/desktop_theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// PC 端主页面（壳子）
///
/// PC 端定位为与手机端跨端通信的独立客户端，
/// 此处仅提供窗口骨架：侧边栏导航 + 主工作区。
/// 不依赖任何手机端业务逻辑（工程/Xposed/Frida 等）。
class DesktopHomePage extends HookConsumerWidget {
  const DesktopHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = useState(0);
    final colorScheme = context.colorScheme;
    final l10n = context.l10n;

    final navItems = <_DesktopNavItem>[
      _DesktopNavItem(
        label: l10n.desktopNavDeviceConnection,
        icon: Icons.devices_outlined,
        selectedIcon: Icons.devices,
      ),
      _DesktopNavItem(
        label: l10n.desktopNavWorkbench,
        icon: Icons.dashboard_outlined,
        selectedIcon: Icons.dashboard,
      ),
      _DesktopNavItem(
        label: l10n.desktopNavSettings,
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings,
      ),
    ];

    return Scaffold(
      body: Row(
        children: [
          _Sidebar(
            navItems: navItems,
            currentIndex: currentIndex.value,
            onSelect: (index) => currentIndex.value = index,
          ),
          Expanded(
            child: _ShellPlaceholder(
              title: navItems[currentIndex.value].label,
              colorScheme: colorScheme,
            ),
          ),
        ],
      ),
    );
  }
}

/// 侧边栏
class _Sidebar extends HookConsumerWidget {
  final List<_DesktopNavItem> navItems;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  const _Sidebar({
    required this.navItems,
    required this.currentIndex,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = context.colorScheme;
    final dividerColor = colorScheme.outlineVariant.withValues(alpha: 0.5);

    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          right: BorderSide(color: dividerColor, width: 1),
        ),
      ),
      child: Column(
        children: [
          // Logo
          Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    'assets/images/logo.png',
                    width: 32,
                    height: 32,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'JsxposedX',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: dividerColor),

          // 导航项
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
              itemCount: navItems.length,
              itemBuilder: (context, index) {
                final item = navItems[index];
                final isSelected = currentIndex == index;

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Material(
                    color: isSelected
                        ? colorScheme.primaryContainer
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      onTap: () => onSelect(index),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        height: 48,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Icon(
                              isSelected ? item.selectedIcon : item.icon,
                              color: isSelected
                                  ? colorScheme.onPrimaryContainer
                                  : colorScheme.onSurfaceVariant,
                              size: 24,
                            ),
                            const SizedBox(width: 16),
                            Text(
                              item.label,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                color: isSelected
                                    ? colorScheme.onPrimaryContainer
                                    : colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // 主题切换
          Divider(height: 1, color: dividerColor),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: () => ref.read(desktopThemeModeProvider.notifier).toggle(),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Icon(
                        context.isDark ? Icons.light_mode : Icons.dark_mode,
                        color: colorScheme.onSurfaceVariant,
                        size: 24,
                      ),
                      const SizedBox(width: 16),
                      Text(
                        context.isDark
                            ? context.l10n.desktopThemeSwitchToLight
                            : context.l10n.desktopThemeSwitchToDark,
                        style: TextStyle(
                          fontSize: 15,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 语言切换
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: () => ref.read(desktopLocaleProvider.notifier).toggle(),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Icon(
                        Icons.language,
                        color: colorScheme.onSurfaceVariant,
                        size: 24,
                      ),
                      const SizedBox(width: 16),
                      Text(
                        Localizations.localeOf(context).languageCode == 'en'
                            ? '中文'
                            : 'English',
                        style: TextStyle(
                          fontSize: 15,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 主工作区占位
class _ShellPlaceholder extends StatelessWidget {
  final String title;
  final ColorScheme colorScheme;

  const _ShellPlaceholder({
    required this.title,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: colorScheme.surface,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.construction_outlined,
              size: 64,
              color: colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.desktopFeatureTodo,
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 侧边栏导航项数据
class _DesktopNavItem {
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  const _DesktopNavItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });
}
