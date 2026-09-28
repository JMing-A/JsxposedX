import 'package:JsxposedX/common/widgets/app_bottom_sheet.dart';
import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/core/utils/procedure_utils.dart';
import 'package:JsxposedX/features/home/presentation/providers/check_query_provider.dart';
import 'package:JsxposedX/features/home/presentation/providers/desktop_connection_provider.dart';
import 'package:JsxposedX/features/home/presentation/providers/desktop_locale_provider.dart';
import 'package:JsxposedX/features/home/presentation/providers/desktop_theme_provider.dart';
import 'package:JsxposedX/features/home/presentation/utils/update_check_helper.dart';
import 'package:JsxposedX/features/home/presentation/widgets/notice_bottom_sheet.dart';
import 'package:JsxposedX/features/home/presentation/widgets/update_check_dialog.dart';
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
    final selectedIndex = currentIndex.value >= navItems.length
        ? navItems.length - 1
        : currentIndex.value;

    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!context.mounted) return;
        await AppBottomSheet.show<void>(
          context: context,
          title: context.l10n.notice,
          child: const NoticeBottomSheet(),
        );
        if (context.mounted) {
          await _checkDesktopUpdate(context, ref, showLatestResult: false);
        }
      });
      return null;
    }, const []);

    return Scaffold(
      body: Row(
        children: [
          _Sidebar(
            navItems: navItems,
            currentIndex: selectedIndex,
            onSelect: (index) => currentIndex.value = index,
          ),
          Expanded(
            child: selectedIndex == 1
                ? const _DesktopSettingsView()
                : _ShellPlaceholder(
                    title: navItems[selectedIndex].label,
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
      width: 272,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(right: BorderSide(color: dividerColor, width: 1)),
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

          // 设备连接（左下角常驻）
          Divider(height: 1, color: dividerColor),
          const _ConnectionPanel(),

          // 主题切换
          Divider(height: 1, color: dividerColor),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: () =>
                    ref.read(desktopThemeModeProvider.notifier).toggle(),
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

Future<void> _checkDesktopUpdate(
  BuildContext context,
  WidgetRef ref, {
  required bool showLatestResult,
}) async {
  try {
    if (showLatestResult) {
      ref.invalidate(updateInfoProvider);
    }
    final localBuildNumber = await ProcedureUtils.getBuildNumber();
    final update = await ref.read(updateInfoProvider.future);
    if (!context.mounted) return;

    if (shouldShowUpdateDialog(
      update: update,
      localBuildNumber: localBuildNumber,
    )) {
      await UpdateCheckDialog.show(context, update: update);
      return;
    }

    if (showLatestResult && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.desktopUpdateLatest)));
    }
  } catch (error, stackTrace) {
    debugPrint('Failed to check desktop update: $error');
    debugPrintStack(stackTrace: stackTrace);
    if (showLatestResult && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.desktopUpdateCheckFailed)),
      );
    }
  }
}

class _DesktopSettingsView extends HookConsumerWidget {
  const _DesktopSettingsView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isChecking = useState(false);
    final colorScheme = context.colorScheme;

    return ColoredBox(
      color: colorScheme.surface,
      child: ListView(
        padding: const EdgeInsets.all(32),
        children: [
          Text(
            context.l10n.desktopNavSettings,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 24),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Material(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                leading: const Icon(Icons.system_update_alt),
                title: Text(context.l10n.desktopUpdateCheck),
                subtitle: Text(context.l10n.desktopUpdateCheckDescription),
                trailing: isChecking.value
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.chevron_right),
                enabled: !isChecking.value,
                onTap: () async {
                  isChecking.value = true;
                  await _checkDesktopUpdate(
                    context,
                    ref,
                    showLatestResult: true,
                  );
                  if (context.mounted) {
                    isChecking.value = false;
                  }
                },
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

  const _ShellPlaceholder({required this.title, required this.colorScheme});

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

/// 左下角设备连接面板
///
/// 常驻侧边栏底部，通过 WebSocket 与手机端保持即时连接。
enum _DesktopConnectionMode { adb, wifi }

Future<void> _showAdbSettingsDialog(
  BuildContext context,
  DesktopConnectionNotifier notifier,
) async {
  final pairAddressController = TextEditingController();
  final pairCodeController = TextEditingController();
  final connectAddressController = TextEditingController();
  final l10n = context.l10n;

  await showDialog<void>(
    context: context,
    builder: (context) {
      var isRunning = false;
      String? commandOutput;
      var commandSucceeded = false;

      return StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(l10n.desktopConnectionAdbSettings),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.desktopConnectionPairSection,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: pairAddressController,
                    enabled: !isRunning,
                    decoration: InputDecoration(
                      labelText: l10n.desktopConnectionPairAddressHint,
                      prefixIcon: const Icon(Icons.link),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: pairCodeController,
                          enabled: !isRunning,
                          decoration: InputDecoration(
                            labelText: l10n.desktopConnectionPairCodeHint,
                            prefixIcon: const Icon(Icons.password),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: isRunning
                            ? null
                            : () async {
                                if (pairAddressController.text.trim().isEmpty ||
                                    pairCodeController.text.trim().isEmpty) {
                                  return;
                                }
                                setDialogState(() {
                                  isRunning = true;
                                  commandOutput = null;
                                  commandSucceeded = false;
                                });
                                final result = await notifier.pairAdb(
                                  pairAddressController.text,
                                  pairCodeController.text,
                                );
                                if (!context.mounted) return;
                                setDialogState(() {
                                  isRunning = false;
                                  commandSucceeded = result.isSuccess;
                                  commandOutput = result.isSuccess
                                      ? '${result.details}\n\n${l10n.desktopConnectionPairNextStep}'
                                      : result.details;
                                });
                              },
                        child: Text(l10n.desktopConnectionPair),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    l10n.desktopConnectionWirelessSection,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: connectAddressController,
                          enabled: !isRunning,
                          decoration: InputDecoration(
                            labelText: l10n.desktopConnectionAdbAddressHint,
                            prefixIcon: const Icon(Icons.wifi),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: isRunning
                            ? null
                            : () async {
                                if (connectAddressController.text
                                    .trim()
                                    .isEmpty) {
                                  return;
                                }
                                setDialogState(() {
                                  isRunning = true;
                                  commandOutput = null;
                                  commandSucceeded = false;
                                });
                                final result = await notifier
                                    .connectAdbWireless(
                                      connectAddressController.text,
                                    );
                                if (!context.mounted) return;
                                if (result.isSuccess) {
                                  Navigator.pop(context);
                                  await notifier.connectAdb();
                                  return;
                                }
                                setDialogState(() {
                                  isRunning = false;
                                  commandOutput = result.details;
                                });
                              },
                        child: Text(l10n.desktopConnectionAdbConnect),
                      ),
                    ],
                  ),
                  if (isRunning) ...[
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(),
                  ],
                  if (commandOutput != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxHeight: 220),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: commandSucceeded
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Theme.of(context).colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          commandOutput!,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isRunning ? null : () => Navigator.pop(context),
              child: Text(MaterialLocalizations.of(context).closeButtonLabel),
            ),
          ],
        ),
      );
    },
  );

  pairAddressController.dispose();
  pairCodeController.dispose();
  connectAddressController.dispose();
}

class _ConnectionToolButton extends StatelessWidget {
  const _ConnectionToolButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.color,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 32,
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        onPressed: onPressed,
        icon: Icon(icon, size: 17, color: color),
      ),
    );
  }
}

class _ConnectionStatusRow extends StatelessWidget {
  const _ConnectionStatusRow({required this.color, required this.text});

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: context.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _ConnectionPanel extends HookConsumerWidget {
  const _ConnectionPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(desktopConnectionProvider);
    final notifier = ref.read(desktopConnectionProvider.notifier);
    final mode = useState(_DesktopConnectionMode.adb);
    final wifiAddress = useState('');
    final colorScheme = context.colorScheme;
    final l10n = context.l10n;

    final selectedDevice = connection.adbDevices
        .where((device) => device.serial == connection.selectedAdbSerial)
        .firstOrNull;
    final address = mode.value == _DesktopConnectionMode.adb
        ? 'ws://127.0.0.1:8765'
        : wifiAddress.value.trim();

    final statusColor = switch (connection.status) {
      DesktopConnectionStatus.connected => const Color(0xFF4CAF50),
      DesktopConnectionStatus.connecting => const Color(0xFFFFA726),
      DesktopConnectionStatus.disconnected => colorScheme.outline,
    };

    final statusText = switch (connection.status) {
      DesktopConnectionStatus.connected => l10n.desktopConnectionConnected,
      DesktopConnectionStatus.connecting => l10n.desktopConnectionConnecting,
      DesktopConnectionStatus.disconnected =>
        l10n.desktopConnectionDisconnected,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.devices_outlined,
                size: 18,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.desktopNavDeviceConnection,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              if (mode.value == _DesktopConnectionMode.adb)
                _ConnectionToolButton(
                  tooltip: l10n.desktopConnectionRefresh,
                  icon: Icons.refresh,
                  onPressed: connection.isConnecting
                      ? null
                      : notifier.scanAdbDevices,
                ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<_DesktopConnectionMode>(
              segments: [
                ButtonSegment(
                  value: _DesktopConnectionMode.adb,
                  label: Text(l10n.desktopConnectionAdb),
                  icon: const Icon(Icons.usb, size: 16),
                ),
                ButtonSegment(
                  value: _DesktopConnectionMode.wifi,
                  label: Text(l10n.desktopConnectionWifi),
                  icon: const Icon(Icons.wifi, size: 16),
                ),
              ],
              selected: {mode.value},
              onSelectionChanged: connection.isConnecting
                  ? null
                  : (selection) {
                      notifier.clearError();
                      mode.value = selection.first;
                      if (mode.value == _DesktopConnectionMode.adb) {
                        wifiAddress.value = '';
                      }
                    },
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (!connection.isConnected) ...[
            if (mode.value == _DesktopConnectionMode.adb) ...[
              OutlinedButton.icon(
                onPressed: connection.isConnecting
                    ? null
                    : () => _showAdbSettingsDialog(context, notifier),
                icon: const Icon(Icons.settings_ethernet, size: 17),
                label: Text(l10n.desktopConnectionConfigureAdb),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: ValueKey(connection.selectedAdbSerial),
                initialValue: connection.selectedAdbSerial,
                isExpanded: true,
                items: connection.adbDevices
                    .map(
                      (device) => DropdownMenuItem(
                        value: device.serial,
                        enabled: device.isAuthorized,
                        child: Text(
                          device.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: connection.isConnecting
                    ? null
                    : (serial) {
                        if (serial != null) notifier.selectAdbDevice(serial);
                      },
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.smartphone, size: 18),
                  prefixIconConstraints: const BoxConstraints(minWidth: 38),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 11,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ] else
              TextField(
                enabled: !connection.isConnecting,
                onChanged: (value) => wifiAddress.value = value,
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                  hintText: l10n.desktopConnectionAddressHint,
                  prefixIcon: const Icon(Icons.link, size: 18),
                  prefixIconConstraints: const BoxConstraints(minWidth: 38),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 11,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            const SizedBox(height: 10),
          ],
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: _ConnectionStatusRow(
              color: statusColor,
              text:
                  mode.value == _DesktopConnectionMode.adb &&
                      connection.isConnected &&
                      selectedDevice != null
                  ? l10n.desktopConnectionAdbActive(selectedDevice.displayName)
                  : statusText,
            ),
          ),
          if (selectedDevice != null && !selectedDevice.isAuthorized) ...[
            const SizedBox(height: 8),
            Text(
              l10n.desktopConnectionDeviceUnauthorized,
              style: TextStyle(fontSize: 11, color: colorScheme.error),
            ),
          ],
          if (connection.error != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 16,
                    color: colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: SelectableText(
                      connection.error!,
                      maxLines: 3,
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                  _ConnectionToolButton(
                    tooltip: MaterialLocalizations.of(context).closeButtonLabel,
                    icon: Icons.close,
                    color: colorScheme.onErrorContainer,
                    onPressed: notifier.clearError,
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          if (connection.isConnected) ...[
            Text(
              connection.address,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 7),
          ],
          SizedBox(
            height: 38,
            child: connection.isConnected
                ? OutlinedButton.icon(
                    onPressed: notifier.disconnect,
                    icon: const Icon(Icons.link_off, size: 17),
                    label: Text(l10n.desktopConnectionDisconnect),
                  )
                : FilledButton.icon(
                    onPressed:
                        connection.isConnecting ||
                            (mode.value == _DesktopConnectionMode.adb
                                ? selectedDevice?.isAuthorized != true
                                : address.isEmpty)
                        ? null
                        : mode.value == _DesktopConnectionMode.adb
                        ? notifier.connectAdb
                        : () => notifier.connect(address),
                    icon: connection.isConnecting
                        ? const SizedBox.square(
                            dimension: 15,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            mode.value == _DesktopConnectionMode.adb
                                ? Icons.phone_android
                                : Icons.wifi,
                            size: 17,
                          ),
                    label: Text(
                      connection.isConnecting
                          ? l10n.desktopConnectionConnecting
                          : mode.value == _DesktopConnectionMode.adb
                          ? l10n.desktopConnectionConnectAdb
                          : l10n.desktopConnectionConnectWifi,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
