import 'dart:async';
import 'dart:convert';

import 'package:JsxposedX/common/widgets/app_bottom_sheet.dart';
import 'package:JsxposedX/common/widgets/app_code_editor.dart';
import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/core/transport/jsxposed_protocol.dart';
import 'package:JsxposedX/core/utils/procedure_utils.dart';
import 'package:JsxposedX/features/home/presentation/providers/check_query_provider.dart';
import 'package:JsxposedX/features/home/presentation/providers/desktop_connection_provider.dart';
import 'package:JsxposedX/features/home/presentation/providers/desktop_locale_provider.dart';
import 'package:JsxposedX/features/home/presentation/providers/desktop_logs_provider.dart';
import 'package:JsxposedX/features/home/presentation/providers/desktop_theme_provider.dart';
import 'package:JsxposedX/features/home/presentation/utils/update_check_helper.dart';
import 'package:JsxposedX/features/home/presentation/widgets/notice_bottom_sheet.dart';
import 'package:JsxposedX/features/home/presentation/widgets/update_check_dialog.dart';
import 'package:JsxposedX/features/frida/presentation/constants/frida_prompts.dart';
import 'package:JsxposedX/features/xposed/presentation/constants/jsxposed_prompts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:re_editor/re_editor.dart';

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
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                _ActivityBar(
                  navItems: navItems,
                  currentIndex: selectedIndex,
                  onSelect: (index) => currentIndex.value = index,
                ),
                Expanded(
                  child: selectedIndex == 1
                      ? const _DesktopSettingsView()
                      : const _DesktopWorkbenchView(),
                ),
              ],
            ),
          ),
          const _DesktopStatusBar(),
        ],
      ),
    );
  }
}

class _ActivityBar extends HookConsumerWidget {
  final List<_DesktopNavItem> navItems;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  const _ActivityBar({
    required this.navItems,
    required this.currentIndex,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = context.colorScheme;
    final dividerColor = colorScheme.outlineVariant.withValues(alpha: 0.5);

    return Container(
      width: 48,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        border: Border(right: BorderSide(color: dividerColor)),
      ),
      child: Column(
        children: [
          Tooltip(
            message: 'JsxposedX',
            child: SizedBox(
              width: 48,
              height: 48,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: Image.asset(
                    'assets/images/logo.png',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ),
          Divider(height: 1, color: dividerColor),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: navItems.length - 1,
              itemBuilder: (context, index) {
                final item = navItems[index];
                final selected = currentIndex == index;
                return _ActivityButton(
                  tooltip: item.label,
                  icon: selected ? item.selectedIcon : item.icon,
                  selected: selected,
                  onPressed: () => onSelect(index),
                );
              },
            ),
          ),
          _ActivityButton(
            tooltip: navItems.last.label,
            icon: currentIndex == navItems.length - 1
                ? navItems.last.selectedIcon
                : navItems.last.icon,
            selected: currentIndex == navItems.length - 1,
            onPressed: () => onSelect(navItems.length - 1),
          ),
        ],
      ),
    );
  }
}

class _ActivityButton extends StatelessWidget {
  const _ActivityButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.selected = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 48,
        height: 48,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    width: 2,
                    color: selected ? colors.primary : Colors.transparent,
                  ),
                ),
              ),
              child: Icon(
                icon,
                size: 24,
                color: selected ? colors.onSurface : colors.onSurfaceVariant,
              ),
            ),
          ),
        ),
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
    final packageInfo = useFuture(
      useMemoized(ProcedureUtils.getPackageInfo, const []),
    );
    final version = packageInfo.data;

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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  context.l10n.desktopSettingsAppearance,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Material(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(
                          context.isDark
                              ? Icons.dark_mode_outlined
                              : Icons.light_mode_outlined,
                        ),
                        title: Text(context.l10n.desktopSettingsColorTheme),
                        subtitle: Text(
                          context.isDark
                              ? context.l10n.desktopSettingsThemeDark
                              : context.l10n.desktopSettingsThemeLight,
                        ),
                        trailing: Switch(
                          value: context.isDark,
                          onChanged: (_) => ref
                              .read(desktopThemeModeProvider.notifier)
                              .toggle(),
                        ),
                        onTap: () => ref
                            .read(desktopThemeModeProvider.notifier)
                            .toggle(),
                      ),
                      Divider(height: 1, color: colorScheme.outlineVariant),
                      ListTile(
                        leading: const Icon(Icons.language),
                        title: Text(
                          context.l10n.desktopSettingsDisplayLanguage,
                        ),
                        subtitle: Text(
                          Localizations.localeOf(context).languageCode == 'en'
                              ? context.l10n.english
                              : context.l10n.chinese,
                        ),
                        trailing: const Icon(Icons.swap_horiz),
                        onTap: () =>
                            ref.read(desktopLocaleProvider.notifier).toggle(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  context.l10n.desktopSettingsApplication,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Material(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    leading: const Icon(Icons.system_update_alt),
                    title: Text(context.l10n.desktopUpdateCheck),
                    subtitle: Text(
                      version == null
                          ? context.l10n.desktopUpdateCheckDescription
                          : context.l10n.desktopCurrentVersion(
                              version.version,
                              version.buildNumber,
                            ),
                    ),
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopWorkbenchView extends HookConsumerWidget {
  const _DesktopWorkbenchView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(desktopConnectionProvider);
    final colors = context.colorScheme;
    final outputExpanded = useState(true);

    // 连接建立后拉一次手机端控制台状态，保证暂停/自动滚动/搜索与手机端一致
    useEffect(() {
      if (connection.isConnected) {
        ref.read(desktopLogsProvider.notifier).syncState();
      }
      return null;
    }, [connection.isConnected]);

    return ColoredBox(
      color: colors.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showProjectPane = constraints.maxWidth >= 700;
          final showExpandedOutput =
              outputExpanded.value && constraints.maxHeight >= 240;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showProjectPane) ...[
                const SizedBox(width: 220, child: _ProjectExplorer()),
                VerticalDivider(width: 1, color: colors.outlineVariant),
              ],
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: _EditorWorkspace(
                        connected: connection.isConnected,
                      ),
                    ),
                    if (constraints.maxHeight >= 40)
                      SizedBox(
                        height: showExpandedOutput ? 240 : 39,
                        child: _RunOutputPanel(
                          expanded: showExpandedOutput,
                          onToggle: () =>
                              outputExpanded.value = !outputExpanded.value,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

Future<void> _showDeviceDetails(
  BuildContext context,
  DesktopConnectionState connection,
) async {
  final info = connection.deviceInfo;
  if (info == null) return;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(info.model ?? context.l10n.desktopDeviceDefaultName),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.desktopDeviceSummary(
                info.manufacturer ?? 'Android',
                '${info.androidApi}',
                info.abi,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              context.l10n.desktopDeviceCapabilities,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            ...?connection.capabilities?.values.entries.map(
              (entry) => _CapabilityRow(name: entry.key, value: entry.value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).closeButtonLabel),
        ),
      ],
    ),
  );
}

/// 资源管理器与编辑器共享的脚本选择状态
@immutable
class DesktopScriptSelection {
  const DesktopScriptSelection({
    required this.packageName,
    required this.source,
    required this.localPath,
    required this.name,
  });

  final String packageName;
  final String source;
  final String localPath;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is DesktopScriptSelection &&
      other.packageName == packageName &&
      other.source == source &&
      other.localPath == localPath;

  @override
  int get hashCode => Object.hash(packageName, source, localPath);
}

class _SelectedScriptNotifier extends Notifier<DesktopScriptSelection?> {
  @override
  DesktopScriptSelection? build() => null;

  set selection(DesktopScriptSelection? value) => state = value;
}

final _selectedScriptProvider =
    NotifierProvider<_SelectedScriptNotifier, DesktopScriptSelection?>(
      _SelectedScriptNotifier.new,
    );

class _ProjectExplorer extends ConsumerWidget {
  const _ProjectExplorer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(desktopConnectionProvider);
    final revision = ref
        .watch(desktopConnectionProvider.notifier)
        .contextRevision;
    final selected = ref.watch(_selectedScriptProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
          child: Text(
            context.l10n.desktopExplorerTitle,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
        Expanded(
          child: !connection.isConnected
              ? _ExplorerPlaceholder(
                  icon: Icons.link_off,
                  message: context.l10n.desktopEditorConnectDevice,
                )
              : ValueListenableBuilder<int>(
                  valueListenable: revision,
                  builder: (context, _, _) => _ProjectTree(
                    connection: connection,
                    selected: selected,
                    onSelect: (selection) =>
                        ref.read(_selectedScriptProvider.notifier).selection =
                            selection,
                  ),
                ),
        ),
      ],
    );
  }
}

class _ExplorerPlaceholder extends StatelessWidget {
  const _ExplorerPlaceholder({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Icon(icon, size: 32, color: colors.outline),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// 项目（包名目录）二级树，脚本按 Frida / Xposed 分组
class _ProjectTree extends ConsumerStatefulWidget {
  const _ProjectTree({
    required this.connection,
    required this.selected,
    required this.onSelect,
  });

  final DesktopConnectionState connection;
  final DesktopScriptSelection? selected;
  final ValueChanged<DesktopScriptSelection> onSelect;

  @override
  ConsumerState<_ProjectTree> createState() => _ProjectTreeState();
}

class _ProjectTreeState extends ConsumerState<_ProjectTree> {
  late Future<_ExplorerData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ExplorerData> _load() async {
    final notifier = ref.read(desktopConnectionProvider.notifier);
    final projects = await notifier.listProjects();
    final scripts = <String, Map<String, List<DesktopScript>>>{};
    for (final project in projects) {
      final bySource = <String, List<DesktopScript>>{};
      for (final source in JsxposedScriptSource.values) {
        bySource[source] = await notifier.listScripts(
          packageName: project.packageName,
          source: source,
        );
      }
      scripts[project.packageName] = bySource;
    }
    return _ExplorerData(projects: projects, scripts: scripts);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ExplorerData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _ExplorerPlaceholder(
            icon: Icons.error_outline,
            message: '${snapshot.error}',
          );
        }
        if (!snapshot.hasData) {
          return const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final data = snapshot.data!;
        if (data.projects.isEmpty) {
          return _ExplorerPlaceholder(
            icon: Icons.folder_off_outlined,
            message: context.l10n.desktopExplorerDescription,
          );
        }
        return ListView(
          children: [
            for (final project in data.projects)
              _ProjectNode(
                project: project,
                scripts: data.scripts[project.packageName] ?? const {},
                selected: widget.selected,
                onSelect: widget.onSelect,
                onChanged: () {
                  final future = _load();
                  // 用块体赋值：箭头写法会把 Future 作为返回值交给 setState，
                  // Flutter 检测到回调返回 Future 会抛断言
                  setState(() {
                    _future = future;
                  });
                },
              ),
          ],
        );
      },
    );
  }
}

class _ExplorerData {
  const _ExplorerData({required this.projects, required this.scripts});

  final List<DesktopProject> projects;
  final Map<String, Map<String, List<DesktopScript>>> scripts;
}

class _ProjectNode extends ConsumerStatefulWidget {
  const _ProjectNode({
    required this.project,
    required this.scripts,
    required this.selected,
    required this.onSelect,
    required this.onChanged,
  });

  final DesktopProject project;
  final Map<String, List<DesktopScript>> scripts;
  final DesktopScriptSelection? selected;
  final ValueChanged<DesktopScriptSelection> onSelect;
  final VoidCallback onChanged;

  @override
  ConsumerState<_ProjectNode> createState() => _ProjectNodeState();
}

class _ProjectNodeState extends ConsumerState<_ProjectNode> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final project = widget.project;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          leading: Icon(
            _expanded ? Icons.expand_more : Icons.chevron_right,
            size: 18,
          ),
          title: Text(
            project.name.isEmpty ? project.packageName : project.name,
            style: const TextStyle(fontSize: 13),
          ),
          subtitle: Text(
            project.packageName,
            style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
          ),
          onTap: () => setState(() => _expanded = !_expanded),
        ),
        if (_expanded)
          for (final entry in widget.scripts.entries)
            _ScriptGroup(
              packageName: project.packageName,
              source: entry.key,
              scripts: entry.value,
              selected: widget.selected,
              onSelect: widget.onSelect,
              onChanged: widget.onChanged,
            ),
      ],
    );
  }
}

class _ScriptGroup extends StatelessWidget {
  const _ScriptGroup({
    required this.packageName,
    required this.source,
    required this.scripts,
    required this.selected,
    required this.onSelect,
    required this.onChanged,
  });

  final String packageName;
  final String source;
  final List<DesktopScript> scripts;
  final DesktopScriptSelection? selected;
  final ValueChanged<DesktopScriptSelection> onSelect;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final label = source == JsxposedScriptSource.frida
        ? context.l10n.desktopExplorerFridaScripts
        : context.l10n.desktopExplorerXposedScripts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(34, 6, 12, 2),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
        if (scripts.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(34, 2, 12, 2),
            child: Text(
              context.l10n.desktopExplorerNoScripts,
              style: TextStyle(fontSize: 11, color: colors.outline),
            ),
          ),
        for (final script in scripts)
          _ScriptNode(
            packageName: packageName,
            source: source,
            script: script,
            active:
                selected?.packageName == packageName &&
                selected?.source == source &&
                selected?.localPath == script.localPath,
            onSelect: onSelect,
            onChanged: onChanged,
          ),
      ],
    );
  }
}

class _ScriptNode extends ConsumerWidget {
  const _ScriptNode({
    required this.packageName,
    required this.source,
    required this.script,
    required this.active,
    required this.onSelect,
    required this.onChanged,
  });

  final String packageName;
  final String source;
  final DesktopScript script;
  final bool active;
  final ValueChanged<DesktopScriptSelection> onSelect;
  final VoidCallback onChanged;

  Future<void> _toggle(
    WidgetRef ref,
    BuildContext context,
    bool enabled,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(desktopConnectionProvider.notifier)
          .toggleScript(
            packageName: packageName,
            source: source,
            localPath: script.localPath,
            enabled: enabled,
          );
      onChanged();
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colorScheme;
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.only(left: 30, right: 8),
      selected: active,
      selectedTileColor: colors.primary.withValues(alpha: 0.10),
      leading: Icon(
        Icons.description_outlined,
        size: 16,
        color: script.enabled ? colors.primary : colors.outline,
      ),
      title: Text(script.name, style: const TextStyle(fontSize: 12)),
      trailing: SizedBox(
        height: 24,
        child: Switch(
          value: script.enabled,
          onChanged: (value) => _toggle(ref, context, value),
        ),
      ),
      onTap: () => onSelect(
        DesktopScriptSelection(
          packageName: packageName,
          source: source,
          localPath: script.localPath,
          name: script.name,
        ),
      ),
    );
  }
}

class _CapabilityRow extends StatelessWidget {
  const _CapabilityRow({required this.name, required this.value});

  final String name;
  final dynamic value;

  @override
  Widget build(BuildContext context) {
    final available = value is bool
        ? value as bool
        : value is Map
        ? value['available'] == true
        : value != null;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        available ? Icons.check_circle_outline : Icons.block,
        size: 17,
        color: available
            ? const Color(0xFF2E7D32)
            : context.colorScheme.outline,
      ),
      title: Text(name),
    );
  }
}

class _EditorWorkspace extends ConsumerStatefulWidget {
  const _EditorWorkspace({required this.connected});

  final bool connected;

  @override
  ConsumerState<_EditorWorkspace> createState() => _EditorWorkspaceState();
}

class _EditorWorkspaceState extends ConsumerState<_EditorWorkspace> {
  DesktopScriptSelection? _loaded;
  CodeLineEditingController? _controller;
  bool _loading = false;
  bool _running = false;

  /// Frida 脚本保存后是否重启目标应用。Xposed 必须重启才能生效，故不参与开关。
  bool _restartApp = false;
  String? _error;

  static final _fridaPrompts = buildFridaPromptsBuilder();
  static final _xposedPrompts = buildJsxposedPromptsBuilder();

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // build 只负责渲染，选中变化用 listen 处理，避免在 build 期间 setState
    _syncSelection(ref.read(_selectedScriptProvider));
  }

  /// 切换选中脚本时重新从手机端拉取内容，本地未保存的修改会被覆盖
  void _syncSelection(DesktopScriptSelection? selection) {
    if (selection == _loaded) return;
    if (selection == null) {
      setState(() {
        _loaded = null;
        _controller?.dispose();
        _controller = null;
        _error = null;
      });
      return;
    }
    setState(() {
      _loaded = selection;
      _loading = true;
      _error = null;
    });
    final notifier = ref.read(desktopConnectionProvider.notifier);
    notifier
        .readScript(
          packageName: selection.packageName,
          source: selection.source,
          localPath: selection.localPath,
        )
        .then((content) {
          if (!mounted || _loaded != selection) return;
          final previous = _controller;
          setState(() {
            _controller = CodeLineEditingController.fromText(content);
            _loading = false;
          });
          previous?.dispose();
        })
        .catchError((Object error) {
          if (!mounted || _loaded != selection) return;
          setState(() {
            _loading = false;
            _error = '$error';
          });
        });
  }

  /// Ctrl/Cmd+S 与运行按钮共用：保存到手机端并触发注入。
  /// Xposed 侧恒为重启应用，Frida 侧由用户开关决定。
  Future<void> _saveAndRun() async {
    final selection = _loaded;
    final controller = _controller;
    if (selection == null || controller == null) return;
    setState(() => _running = true);
    final messenger = ScaffoldMessenger.of(context);
    final isFrida = selection.source == JsxposedScriptSource.frida;
    final runningMessage = context.l10n.desktopEditorRunning;
    try {
      await ref
          .read(desktopConnectionProvider.notifier)
          .runScript(
            packageName: selection.packageName,
            source: selection.source,
            localPath: selection.localPath,
            content: controller.text,
            restartApp: isFrida ? _restartApp : true,
          );
      messenger.showSnackBar(SnackBar(content: Text(runningMessage)));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    // 选中变化通过 listen 处理，build 只做渲染，避免每次重建都重新加载脚本
    ref.listen(_selectedScriptProvider, (_, next) => _syncSelection(next));
    final selection = _loaded;

    return CallbackShortcuts(
      bindings: {
        // Mac 用 Cmd+S，Windows/Linux 用 Ctrl+S，与手机端「保存并运行」等价
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _saveAndRun,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true):
            _saveAndRun,
      },
      child: Focus(
        autofocus: true,
        child: Column(
          children: [
            _buildEditorToolbar(colors, selection),
            Expanded(child: _buildBody(colors, selection)),
          ],
        ),
      ),
    );
  }

  Widget _buildEditorToolbar(
    ColorScheme colors,
    DesktopScriptSelection? selection,
  ) {
    final isFrida = selection?.source == JsxposedScriptSource.frida;
    final busy = _running || _loading;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: colors.surfaceContainerLow,
      child: Row(
        children: [
          const Icon(Icons.code, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              selection?.name ?? context.l10n.desktopEditorUntitled,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (selection != null) ...[
            // Frida 无需重启即可热更新，是否重启交给用户决定
            if (isFrida) ...[
              Text(
                context.l10n.desktopEditorRestartApp,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(width: 4),
              Switch(
                value: _restartApp,
                onChanged: busy
                    ? null
                    : (value) => setState(() => _restartApp = value),
              ),
              const SizedBox(width: 4),
            ],
            IconButton(
              tooltip: context.l10n.desktopEditorSaveAndRun,
              visualDensity: VisualDensity.compact,
              onPressed: busy ? null : _saveAndRun,
              icon: _running
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow, size: 18),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBody(ColorScheme colors, DesktopScriptSelection? selection) {
    if (selection == null) {
      return _EditorEmptyState(
        icon: Icons.code_outlined,
        title: widget.connected
            ? context.l10n.desktopEditorCreateScript
            : context.l10n.desktopEditorConnectDevice,
        description: context.l10n.desktopEditorDescription,
      );
    }
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_error != null) {
      return _EditorEmptyState(
        icon: Icons.error_outline,
        title: context.l10n.desktopEditorLoadFailed,
        description: _error!,
      );
    }
    return Padding(
      padding: const EdgeInsets.all(12),
      child: AppCodeEditor(
        controller: _controller!,
        language: 'javascript',
        readOnly: false,
        // 与手机端共用同一套内置代码提示
        promptsBuilder: selection.source == JsxposedScriptSource.frida
            ? _fridaPrompts
            : _xposedPrompts,
        // 桌面端使用物理键盘，不需要符号输入栏
        showToolbar: false,
      ),
    );
  }
}

class _EditorEmptyState extends StatelessWidget {
  const _EditorEmptyState({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: colors.outline),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            description,
            style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _RunOutputPanel extends ConsumerStatefulWidget {
  const _RunOutputPanel({required this.expanded, required this.onToggle});

  final bool expanded;
  final VoidCallback onToggle;

  @override
  ConsumerState<_RunOutputPanel> createState() => _RunOutputPanelState();
}

class _RunOutputPanelState extends ConsumerState<_RunOutputPanel> {
  /// 复制的日志条数上限，与手机端控制台保持一致
  static const _maxCopyEntries = 5000;

  /// 搜索输入的防抖时长，避免每次敲键都走一趟协议
  static const _searchDebounce = Duration(milliseconds: 200);

  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  Timer? _searchDebounceTimer;
  String? _sourceFilter;
  String? _levelFilter;
  bool _regexEnabled = false;
  bool _caseSensitive = false;
  bool _showHistory = false;

  @override
  void initState() {
    super.initState();
    // 自动滚动由手机端的 autoScroll 状态决定，这里只负责落到列表底部
    ref.listenManual(desktopLogsProvider, (previous, next) {
      if (!next.state.autoScroll || !mounted) return;
      if (previous?.entries.length == next.entries.length) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        _scrollController.jumpTo(
          _scrollController.position.maxScrollExtent,
        );
      });
    });
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 把搜索词防抖后交给手机端，本地不保留搜索状态
  void _onSearchChanged(String value) {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(
      _searchDebounce,
      () => ref.read(desktopLogsProvider.notifier).setSearch(value),
    );
  }

  void _copyEntry(DesktopLogEntry entry) {
    Clipboard.setData(ClipboardData(text: _formatEntry(entry)));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.consoleLogCopied)));
  }

  @override
  Widget build(BuildContext context) {
    final mirror = ref.watch(desktopLogsProvider);
    final consoleState = mirror.state;
    final matcher = _SearchMatcher(
      query: consoleState.searchQuery,
      regex: _regexEnabled,
      caseSensitive: _caseSensitive,
    );

    final filtered = [
      for (final entry in mirror.entries)
        if (_sourceFilter == null &&
            _levelFilter == null &&
            !matcher.isActive)
          entry
        else if (_matchesEntry(entry, matcher))
          entry,
    ];
    final levelCounts = _countLevels(filtered);

    final filteredHistory = [
      for (final log in mirror.historyLogs)
        if (_matchesHistory(log, matcher)) log,
    ];

    final list = _showHistory
        ? _buildHistoryList(mirror, filtered, filteredHistory, matcher)
        : _buildLogList(
            entries: filtered,
            totalCount: mirror.entries.length,
            hasFilter: _hasFilter(matcher),
            matcher: matcher,
          );

    final colors = context.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      child: Column(
        children: [
          _ConsoleToolbar(
            state: consoleState,
            filteredCount: filtered.length,
            totalCount: mirror.entries.length,
            levelCounts: levelCounts,
            regexEnabled: _regexEnabled,
            caseSensitive: _caseSensitive,
            regexValid: matcher.regexValid,
            showHistory: _showHistory,
            searchController: _searchController,
            onSearchChanged: _onSearchChanged,
            onToggleRegex: () => setState(() => _regexEnabled = !_regexEnabled),
            onToggleCase: () =>
                setState(() => _caseSensitive = !_caseSensitive),
            onToggleAutoScroll: () => ref
                .read(desktopLogsProvider.notifier)
                .setAutoScroll(!consoleState.autoScroll),
            onToggleHistory: () => setState(() {
              _showHistory = !_showHistory;
              if (_showHistory && mirror.historyLogs.isEmpty) {
                ref.read(desktopLogsProvider.notifier).loadHistory();
              }
            }),
            onTogglePause: () => ref
                .read(desktopLogsProvider.notifier)
                .setPaused(!consoleState.isPaused),
            onCopyVisible: () => _copyVisible(filtered),
            onExportVisible: () => _exportVisible(filtered),
            onDeleteHistory: _deleteHistory,
            onClear: () => ref.read(desktopLogsProvider.notifier).clear(),
            expanded: widget.expanded,
            onToggleExpanded: widget.onToggle,
          ),
          Divider(height: 1, thickness: 0.6, color: colors.outlineVariant),
          _ConsoleFilterRow(
            sourceFilter: _sourceFilter,
            levelFilter: _levelFilter,
            onSourceChanged: (value) => setState(() => _sourceFilter = value),
            onLevelChanged: (value) => setState(() => _levelFilter = value),
          ),
          Divider(
            height: 1,
            thickness: 0.4,
            color: colors.outlineVariant.withValues(alpha: 0.6),
          ),
          Expanded(
            child: widget.expanded
                ? list
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  bool _hasFilter(_SearchMatcher matcher) =>
      _sourceFilter != null || _levelFilter != null || matcher.isActive;

  bool _matchesEntry(DesktopLogEntry entry, _SearchMatcher matcher) {
    if (_sourceFilter != null && entry.source != _sourceFilter) return false;
    if (_levelFilter != null && entry.level != _levelFilter) return false;
    if (matcher.isActive && !matcher.matches(entry.searchText)) return false;
    return true;
  }

  bool _matchesHistory(DesktopHistoryLog log, _SearchMatcher matcher) {
    if (!_showHistory) return false;
    if (_sourceFilter != null && log.source != _sourceFilter) return false;
    if (_levelFilter != null && log.level != _levelFilter) return false;
    if (matcher.isActive) {
      final haystack = [
        log.message,
        log.scriptName,
        log.source,
        log.stackTrace,
      ].join('\n');
      if (!matcher.matches(haystack)) return false;
    }
    return true;
  }

  Map<String, int> _countLevels(List<DesktopLogEntry> entries) {
    final counts = {'D': 0, 'I': 0, 'W': 0, 'E': 0};
    for (final entry in entries) {
      if (counts.containsKey(entry.level)) {
        counts[entry.level] = counts[entry.level]! + 1;
      }
    }
    return counts;
  }

  Widget _buildLogList({
    required List<DesktopLogEntry> entries,
    required int totalCount,
    required bool hasFilter,
    required _SearchMatcher matcher,
  }) {
    if (entries.isEmpty) {
      return _ConsoleEmptyState(
        isFiltered: hasFilter,
        message: hasFilter
            ? context.l10n.noLogsFiltered
            : context.l10n.noLogs,
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: entries.length,
      itemBuilder: (context, index) => _LogRow(
        entry: entries[index],
        matcher: matcher,
        onCopy: () => _copyEntry(entries[index]),
      ),
    );
  }

  Widget _buildHistoryList(
    DesktopConsoleMirror mirror,
    List<DesktopLogEntry> liveEntries,
    List<DesktopHistoryLog> historyEntries,
    _SearchMatcher matcher,
  ) {
    if (mirror.historyLoading && mirror.historyLogs.isEmpty) {
      return const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final conversationId = mirror.state.sessionConversationId;
    if (conversationId == null || conversationId.isEmpty) {
      return _ConsoleEmptyState(
        isFiltered: false,
        message: context.l10n.consoleDeleteHistoryUnavailable,
      );
    }
    if (mirror.historyLogs.isEmpty && liveEntries.isEmpty) {
      return _ConsoleEmptyState(
        isFiltered: false,
        message: context.l10n.consoleNoHistory,
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount:
          historyEntries.length +
          liveEntries.length +
          1 +
          (liveEntries.isEmpty ? 0 : 1),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _HistoryLoadOlderButton(
            loading: mirror.historyLoading,
            hasMore: mirror.historyHasMore,
            error: mirror.historyError,
            onTap: () =>
                ref.read(desktopLogsProvider.notifier).loadHistory(older: true),
          );
        }
        final historyEnd = 1 + historyEntries.length;
        if (index < historyEnd) {
          return _PersistedLogRow(log: historyEntries[index - 1]);
        }
        if (index == historyEnd) {
          return _LiveSectionDivider(
            label: context.l10n.consoleLiveBelow,
          );
        }
        return _LogRow(
          entry: liveEntries[index - historyEnd - 1],
          matcher: matcher,
          onCopy: () => _copyEntry(liveEntries[index - historyEnd - 1]),
        );
      },
    );
  }

  Future<void> _copyVisible(List<DesktopLogEntry> entries) async {
    final truncated = entries.length > _maxCopyEntries;
    final source = truncated
        ? entries.sublist(entries.length - _maxCopyEntries)
        : entries;
    await Clipboard.setData(
      ClipboardData(text: source.map(_formatEntry).join('\n')),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          truncated
              ? context.l10n.consoleCopiedTruncated(
                  source.length,
                  entries.length,
                )
              : context.l10n.consoleCopied(source.length),
        ),
      ),
    );
  }

  Future<void> _exportVisible(List<DesktopLogEntry> entries) async {
    final text = entries.map(_formatEntry).join('\n');
    final sessionId = ref.read(desktopLogsProvider).state.sessionId;
    try {
      await FilePicker.platform.saveFile(
        dialogTitle: context.l10n.consoleExportDialogTitle,
        fileName: 'jsxposed-console-$sessionId.log',
        bytes: utf8.encode(text),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.exportFailed('$error'))),
      );
    }
  }

  Future<void> _deleteHistory() async {
    final conversationId = ref
        .read(desktopLogsProvider)
        .state
        .sessionConversationId;
    if (conversationId == null || conversationId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.consoleDeleteHistoryUnavailable)),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.consoleDeleteHistoryConfirmTitle),
        content: Text(context.l10n.consoleDeleteHistoryConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(desktopLogsProvider.notifier).deleteHistory();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.consoleDeleteHistoryDone)),
    );
  }
}

/// 与手机端控制台一致的检索匹配器：支持普通串与正则，并负责命中高亮切分
class _SearchMatcher {
  _SearchMatcher({
    required String query,
    required this.regex,
    required this.caseSensitive,
  }) : needle = caseSensitive ? query : query.toLowerCase(),
       regexValid = _checkRegex(query, regex, caseSensitive),
       _pattern = regex && _checkRegex(query, regex, caseSensitive)
           ? RegExp(query, caseSensitive: caseSensitive)
           : null;

  final String needle;
  final bool regex;
  final bool caseSensitive;
  final bool regexValid;
  final RegExp? _pattern;

  bool get isActive => regex ? regexValid && needle.isNotEmpty : needle.isNotEmpty;

  static bool _checkRegex(String query, bool regex, bool caseSensitive) {
    if (!regex || query.isEmpty) return true;
    try {
      RegExp(query, caseSensitive: caseSensitive);
      return true;
    } catch (_) {
      return false;
    }
  }

  bool matches(String haystack) {
    if (!isActive) return true;
    if (_pattern != null) return _pattern.hasMatch(haystack);
    return (caseSensitive ? haystack : haystack.toLowerCase()).contains(needle);
  }

  /// 把 [text] 按命中位置切成 span，命中片段使用 [highlight]
  List<TextSpan> split(String text, TextStyle base, TextStyle highlight) {
    if (!isActive) return [TextSpan(text: text, style: base)];
    final ranges = <(int, int)>[];
    if (_pattern != null) {
      for (final match in _pattern.allMatches(text)) {
        ranges.add((match.start, match.end));
      }
    } else {
      final haystack = caseSensitive ? text : text.toLowerCase();
      var start = haystack.indexOf(needle);
      while (start != -1) {
        ranges.add((start, start + needle.length));
        start = haystack.indexOf(needle, start + needle.length);
      }
    }
    if (ranges.isEmpty) return [TextSpan(text: text, style: base)];

    final spans = <TextSpan>[];
    var cursor = 0;
    for (final (start, end) in ranges) {
      if (start < cursor) continue;
      if (start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, start), style: base));
      }
      spans.add(TextSpan(text: text.substring(start, end), style: highlight));
      cursor = end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor), style: base));
    }
    return spans;
  }
}

class _ConsoleToolbar extends StatelessWidget {
  const _ConsoleToolbar({
    required this.state,
    required this.filteredCount,
    required this.totalCount,
    required this.levelCounts,
    required this.regexEnabled,
    required this.caseSensitive,
    required this.regexValid,
    required this.showHistory,
    required this.searchController,
    required this.onSearchChanged,
    required this.onToggleRegex,
    required this.onToggleCase,
    required this.onToggleAutoScroll,
    required this.onToggleHistory,
    required this.onTogglePause,
    required this.onCopyVisible,
    required this.onExportVisible,
    required this.onDeleteHistory,
    required this.onClear,
    required this.expanded,
    required this.onToggleExpanded,
  });

  static const _kLevels = ['E', 'W', 'I', 'D'];

  final DesktopConsoleState state;
  final int filteredCount;
  final int totalCount;
  final Map<String, int> levelCounts;
  final bool regexEnabled;
  final bool caseSensitive;
  final bool regexValid;
  final bool showHistory;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onToggleRegex;
  final VoidCallback onToggleCase;
  final VoidCallback onToggleAutoScroll;
  final VoidCallback onToggleHistory;
  final VoidCallback onTogglePause;
  final VoidCallback onCopyVisible;
  final VoidCallback onExportVisible;
  final VoidCallback onDeleteHistory;
  final VoidCallback onClear;
  final bool expanded;
  final VoidCallback onToggleExpanded;

  Color _statusColor(BuildContext context) {
    if (state.isPaused) return const Color(0xFFFFA726);
    if (state.isRunning || state.isStarting) return const Color(0xFF66BB6A);
    return context.colorScheme.onSurfaceVariant;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final hasFilter = filteredCount != totalCount;
    return Container(
      height: 38,
      color: colors.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Icon(
            Icons.terminal_rounded,
            size: 13,
            color: colors.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: _statusColor(context),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            context.l10n.terminal,
            style: TextStyle(
              fontSize: 11,
              color: colors.onSurface,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          if (totalCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: hasFilter
                    ? colors.primary.withValues(alpha: 0.12)
                    : colors.onSurface.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                hasFilter ? '$filteredCount/$totalCount' : '$totalCount',
                style: TextStyle(
                  fontSize: 9.5,
                  fontFamily: 'monospace',
                  color: hasFilter ? colors.primary : colors.onSurfaceVariant,
                ),
              ),
            ),
          for (final level in _kLevels)
            if ((levelCounts[level] ?? 0) > 0)
              _LevelCountBadge(level: level, count: levelCounts[level]!),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 26,
              child: TextField(
                controller: searchController,
                onChanged: onSearchChanged,
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: colors.onSurface,
                ),
                cursorColor: colors.primary,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: context.l10n.terminalFilterHint,
                  hintStyle: TextStyle(
                    fontSize: 11,
                    color: colors.onSurfaceVariant,
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 14,
                    color: regexValid ? colors.onSurfaceVariant : colors.error,
                  ),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 26,
                    minHeight: 26,
                  ),
                  suffixIcon: regexEnabled
                      ? Text(
                          '.*',
                          style: TextStyle(
                            fontSize: 10,
                            fontFamily: 'monospace',
                            color: colors.primary,
                          ),
                        )
                      : (caseSensitive
                            ? Text(
                                'Aa',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontFamily: 'monospace',
                                  color: colors.primary,
                                ),
                              )
                            : null),
                  suffixIconConstraints: const BoxConstraints(
                    minWidth: 26,
                    minHeight: 26,
                  ),
                  filled: true,
                  fillColor: colors.onSurface.withValues(alpha: 0.06),
                  contentPadding: const EdgeInsets.symmetric(vertical: 4),
                  border: const OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.all(Radius.circular(4)),
                  ),
                  enabledBorder: const OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.all(Radius.circular(4)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      width: 0.8,
                      color: regexValid
                          ? colors.onSurface.withValues(alpha: 0.5)
                          : colors.error,
                    ),
                    borderRadius: const BorderRadius.all(Radius.circular(4)),
                  ),
                ),
              ),
            ),
          ),
          _ToolbarIconButton(
            icon: Icons.code_rounded,
            tooltip: context.l10n.consoleRegexSearch,
            active: regexEnabled,
            onTap: onToggleRegex,
          ),
          _ToolbarIconButton(
            icon: Icons.text_fields_rounded,
            tooltip: context.l10n.consoleCaseSensitive,
            active: caseSensitive,
            onTap: onToggleCase,
          ),
          _ToolbarIconButton(
            icon: state.autoScroll
                ? Icons.vertical_align_bottom_rounded
                : Icons.pause_circle_outline_rounded,
            tooltip: context.l10n.consoleHistory,
            active: state.autoScroll,
            onTap: onToggleAutoScroll,
          ),
          _ToolbarIconButton(
            icon: showHistory
                ? Icons.history_rounded
                : Icons.history_toggle_off_rounded,
            tooltip: context.l10n.consoleHistory,
            active: showHistory,
            onTap: onToggleHistory,
          ),
          _ToolbarIconButton(
            icon: state.isPaused
                ? Icons.play_arrow_rounded
                : Icons.pause_rounded,
            tooltip: state.isPaused
                ? context.l10n.consoleResumeOutput
                : context.l10n.consolePauseOutput,
            active: state.isPaused,
            onTap: onTogglePause,
          ),
          PopupMenuButton<String>(
            tooltip: context.l10n.consoleActions,
            padding: EdgeInsets.zero,
            iconSize: 15,
            icon: Icon(Icons.more_vert, color: colors.onSurfaceVariant),
            constraints: const BoxConstraints(minWidth: 27, minHeight: 28),
            color: colors.surfaceContainerHigh,
            onSelected: (value) {
              switch (value) {
                case 'copy':
                  onCopyVisible();
                case 'export':
                  onExportVisible();
                case 'deleteHistory':
                  onDeleteHistory();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'copy',
                child: _MenuRow(
                  icon: Icons.copy_all_outlined,
                  label: context.l10n.consoleCopyVisible,
                ),
              ),
              PopupMenuItem(
                value: 'export',
                child: _MenuRow(
                  icon: Icons.download_outlined,
                  label: context.l10n.consoleExportVisible,
                ),
              ),
              PopupMenuItem(
                value: 'deleteHistory',
                child: _MenuRow(
                  icon: Icons.delete_outline,
                  label: context.l10n.consoleDeleteHistory,
                ),
              ),
            ],
          ),
          _ToolbarIconButton(
            icon: Icons.delete_sweep_outlined,
            tooltip: context.l10n.consoleClearViewTooltip,
            onTap: onClear,
          ),
          _ToolbarIconButton(
            icon: expanded ? Icons.expand_more : Icons.expand_less,
            tooltip: expanded
                ? context.l10n.desktopOutputCollapse
                : context.l10n.desktopOutputExpand,
            onTap: onToggleExpanded,
          ),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: context.colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: context.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}

class _ToolbarIconButton extends StatelessWidget {
  const _ToolbarIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 27,
          height: 28,
          child: Icon(
            icon,
            size: 15,
            color: active
                ? context.colorScheme.primary
                : context.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _LevelCountBadge extends StatelessWidget {
  const _LevelCountBadge({required this.level, required this.count});

  final String level;
  final int count;

  Color get _color => switch (level) {
    'E' => const Color(0xFFEF5350),
    'W' => const Color(0xFFFFA726),
    'D' => const Color(0xFF42A5F5),
    _ => const Color(0xFF90A4AE),
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: _color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          '$level$count',
          style: TextStyle(
            fontSize: 9,
            fontFamily: 'monospace',
            fontWeight: FontWeight.w600,
            color: _color,
          ),
        ),
      ),
    );
  }
}

class _ConsoleFilterRow extends StatelessWidget {
  const _ConsoleFilterRow({
    required this.sourceFilter,
    required this.levelFilter,
    required this.onSourceChanged,
    required this.onLevelChanged,
  });

  static const _kSources = ['session', 'frida', 'xposed', 'app', 'framework', 'system'];
  static const _kLevels = ['D', 'I', 'W', 'E'];

  final String? sourceFilter;
  final String? levelFilter;
  final ValueChanged<String?> onSourceChanged;
  final ValueChanged<String?> onLevelChanged;

  String _sourceLabel(BuildContext context, String source) =>
      switch (source) {
        'session' => context.l10n.consoleSourceSession,
        'frida' => context.l10n.consoleSourceFrida,
        'xposed' => context.l10n.consoleSourceXposed,
        'app' => context.l10n.consoleSourceApp,
        'framework' => context.l10n.consoleSourceCore,
        _ => context.l10n.consoleSourceSystem,
      };

  String _levelLabel(BuildContext context, String level) =>
      switch (level) {
        'D' => context.l10n.consoleLevelDebug,
        'I' => context.l10n.consoleLevelInfo,
        'W' => context.l10n.consoleLevelWarn,
        _ => context.l10n.consoleLevelError,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      color: context.colorScheme.surfaceContainerLowest,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        children: [
          _TagChip(
            label: context.l10n.consoleAll,
            selected: sourceFilter == null && levelFilter == null,
            onTap: () => onSourceChanged(null),
          ),
          for (final source in _kSources) ...[
            const SizedBox(width: 6),
            _TagChip(
              label: _sourceLabel(context, source),
              selected: sourceFilter == source,
              onTap: () => onSourceChanged(
                sourceFilter == source ? null : source,
              ),
            ),
          ],
          const SizedBox(width: 8),
          Container(width: 1, color: context.colorScheme.outlineVariant),
          const SizedBox(width: 8),
          for (final level in _kLevels) ...[
            _TagChip(
              label: _levelLabel(context, level),
              selected: levelFilter == level,
              onTap: () => onLevelChanged(
                levelFilter == level ? null : level,
              ),
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: selected
              ? context.colorScheme.primary.withValues(alpha: 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? context.colorScheme.primary.withValues(alpha: 0.32)
                : context.colorScheme.outlineVariant,
            width: 0.8,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: selected
                ? context.colorScheme.primary
                : context.colorScheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _ConsoleEmptyState extends StatelessWidget {
  const _ConsoleEmptyState({required this.isFiltered, required this.message});

  final bool isFiltered;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isFiltered ? Icons.filter_list_off : Icons.terminal_rounded,
            size: 28,
            color: context.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: TextStyle(
              fontSize: 12,
              color: context.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _LogRow extends StatefulWidget {
  const _LogRow({
    required this.entry,
    required this.matcher,
    required this.onCopy,
  });

  final DesktopLogEntry entry;
  final _SearchMatcher matcher;
  final VoidCallback onCopy;

  @override
  State<_LogRow> createState() => _LogRowState();
}

class _LogRowState extends State<_LogRow> {
  bool _stackExpanded = false;

  DesktopLogEntry get entry => widget.entry;

  Color get _levelColor => switch (entry.level) {
    'E' || 'F' => const Color(0xFFEF5350),
    'W' => const Color(0xFFFFA726),
    'D' => const Color(0xFF42A5F5),
    _ => const Color(0xFFB0BEC5),
  };

  Color get _sourceColor => switch (entry.source) {
    'frida' => const Color(0xFFFFB74D),
    'xposed' => const Color(0xFF81C784),
    'app' => const Color(0xFF64B5F6),
    'framework' => const Color(0xFFBA68C8),
    _ => const Color(0xFF90A4AE),
  };

  Color get _rowBgColor => switch (entry.level) {
    'E' || 'F' => const Color(0x14EF5350),
    'W' => const Color(0x0DFFA726),
    _ => Colors.transparent,
  };

  TextStyle _messageStyle(BuildContext context) => TextStyle(
    fontFamily: 'monospace',
    fontSize: 11.5,
    color: entry.level == 'E' || entry.level == 'F'
        ? const Color(0xFFEF9A9A)
        : entry.level == 'W'
        ? const Color(0xFFFFCC80)
        : context.colorScheme.onSurface,
    height: 1.35,
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final messageStyle = _messageStyle(context);
    final timeDisplay = entry.timestamp.length > 6
        ? entry.timestamp.substring(6)
        : '';
    final hasStructured = entry.tag.isNotEmpty || entry.source.isNotEmpty;
    final messageText = hasStructured ? entry.message : entry.rawLine;
    final meta = [
      entry.source.toUpperCase(),
      if (entry.scriptName.isNotEmpty) entry.scriptName,
      if (entry.tag.isNotEmpty) entry.tag,
    ].join('  ·  ');
    final highlightStyle = messageStyle.copyWith(
      color: const Color(0xFF111111),
      backgroundColor: const Color(0xFFFFD54F),
      fontWeight: FontWeight.w600,
    );

    return InkWell(
      onLongPress: widget.onCopy,
      child: Container(
        color: _rowBgColor,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 16,
              height: 16,
              margin: const EdgeInsets.only(top: 2),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _levelColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                entry.level,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                  color: _levelColor,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          meta,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            color: _sourceColor.withValues(alpha: 0.85),
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (timeDisplay.isNotEmpty)
                        Text(
                          timeDisplay,
                          style: TextStyle(
                            fontSize: 9,
                            color: colors.onSurfaceVariant.withValues(
                              alpha: 0.7,
                            ),
                            fontFamily: 'monospace',
                          ),
                        ),
                    ],
                  ),
                  Text.rich(
                    TextSpan(
                      children: widget.matcher.split(
                        messageText,
                        messageStyle,
                        highlightStyle,
                      ),
                    ),
                  ),
                  if (entry.stackTrace.isNotEmpty)
                    GestureDetector(
                      onTap: () =>
                          setState(() => _stackExpanded = !_stackExpanded),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.stackTrace,
                            maxLines: _stackExpanded ? null : 5,
                            overflow: _stackExpanded
                                ? TextOverflow.visible
                                : TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 10,
                              color: Color(0xFFEF9A9A),
                              height: 1.3,
                            ),
                          ),
                          Text(
                            _stackExpanded
                                ? context.l10n.consoleCollapseStack
                                : context.l10n.consoleExpandStack,
                            style: TextStyle(
                              fontSize: 9,
                              color: colors.primary,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: context.l10n.consoleLogCopied,
              iconSize: 14,
              visualDensity: VisualDensity.compact,
              onPressed: widget.onCopy,
              icon: Icon(
                Icons.copy_rounded,
                color: colors.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PersistedLogRow extends StatelessWidget {
  const _PersistedLogRow({required this.log});

  final DesktopHistoryLog log;

  @override
  Widget build(BuildContext context) {
    final buffer = StringBuffer()
      ..write('[${log.timestamp.toLocal()}] ')
      ..write('[${log.source}/${log.level}] ');
    if (log.scriptName.isNotEmpty) buffer.write('${log.scriptName} ');
    if (log.runId.isNotEmpty) buffer.write('(run ${log.runId}): ');
    buffer.write(log.message);
    if (log.stackTrace.isNotEmpty) buffer.write('\n${log.stackTrace}');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: SelectableText(
        buffer.toString(),
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 11,
          color: context.colorScheme.onSurfaceVariant,
          height: 1.35,
        ),
      ),
    );
  }
}

class _LiveSectionDivider extends StatelessWidget {
  const _LiveSectionDivider({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Divider(color: context.colorScheme.outlineVariant, height: 1),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 9.5,
                color: context.colorScheme.onSurfaceVariant,
                fontFamily: 'monospace',
              ),
            ),
          ),
          Expanded(
            child: Divider(color: context.colorScheme.outlineVariant, height: 1),
          ),
        ],
      ),
    );
  }
}

class _HistoryLoadOlderButton extends StatelessWidget {
  const _HistoryLoadOlderButton({
    required this.loading,
    required this.hasMore,
    required this.error,
    required this.onTap,
  });

  final bool loading;
  final bool hasMore;
  final String? error;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Center(
        child: loading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : TextButton(
                onPressed: hasMore ? onTap : null,
                child: Text(
                  error == null
                      ? context.l10n.consoleLoadOlder
                      : '$error',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
      ),
    );
  }
}

String _formatEntry(DesktopLogEntry entry) {
  final buffer = StringBuffer();
  if (entry.timestamp.isNotEmpty) buffer.write('${entry.timestamp} ');
  buffer.write('${entry.level} [${entry.source.toUpperCase()}]');
  if (entry.scriptName.isNotEmpty) buffer.write('[${entry.scriptName}]');
  if (entry.pid.isNotEmpty) buffer.write('[pid:${entry.pid}]');
  buffer.write(' ${entry.displayText}');
  if (entry.stackTrace.isNotEmpty) buffer.write('\n${entry.stackTrace}');
  return buffer.toString();
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

class _DesktopStatusBar extends ConsumerWidget {
  const _DesktopStatusBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(desktopConnectionProvider);
    final colors = context.colorScheme;
    final connected = connection.isConnected;
    return Container(
      height: 22,
      color: connected ? colors.primary : colors.surfaceContainerHighest,
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            InkWell(
              onTap: () => _showConnectionManager(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Icon(
                      connected ? Icons.device_hub : Icons.phonelink_off,
                      size: 13,
                      color: connected
                          ? colors.onPrimary
                          : colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      connection.deviceInfo?.model ??
                          (connection.isConnecting
                              ? context.l10n.desktopStatusConnecting
                              : context.l10n.desktopStatusNoDevice),
                      style: TextStyle(
                        fontSize: 11,
                        color: connected
                            ? colors.onPrimary
                            : colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (connected && constraints.maxWidth >= 420)
              InkWell(
                onTap: () => _showDeviceDetails(context, connection),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    context.l10n.desktopStatusDeviceInfo(
                      '${connection.deviceInfo?.androidApi ?? '-'}',
                      connection.deviceInfo?.abi ?? '-',
                    ),
                    style: TextStyle(fontSize: 11, color: colors.onPrimary),
                  ),
                ),
              ),
            const Spacer(),
            if (constraints.maxWidth >= 560)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'Jsxposed Protocol 1.0',
                  style: TextStyle(
                    fontSize: 11,
                    color: connected
                        ? colors.onPrimary
                        : colors.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showConnectionManager(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.l10n.desktopNavDeviceConnection),
      content: const SizedBox(
        width: 380,
        child: SingleChildScrollView(child: _ConnectionPanel()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).closeButtonLabel),
        ),
      ],
    ),
  );
}

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

class _AdbDeviceTile extends StatelessWidget {
  const _AdbDeviceTile({
    required this.device,
    required this.selected,
    required this.busy,
    required this.onTap,
  });

  final DesktopAdbDevice device;
  final bool selected;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final authorized = device.isAuthorized;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? colors.primaryContainer : colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: busy ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Icon(
                  authorized ? Icons.phone_android : Icons.phonelink_lock,
                  size: 17,
                  color: authorized ? colors.primary : colors.outline,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        authorized
                            ? device.serial
                            : context.l10n.desktopConnectionDeviceUnauthorized,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          color: authorized
                              ? colors.onSurfaceVariant
                              : colors.error,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  Icon(Icons.check_circle, size: 17, color: colors.primary),
              ],
            ),
          ),
        ),
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
          if (mode.value == _DesktopConnectionMode.adb) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.desktopDeviceListTitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                _ConnectionToolButton(
                  tooltip: l10n.desktopConnectionRefresh,
                  icon: Icons.refresh,
                  onPressed: connection.isConnecting
                      ? null
                      : notifier.scanAdbDevices,
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (connection.adbDevices.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  l10n.desktopDeviceListEmpty,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              Column(
                children: connection.adbDevices
                    .map(
                      (device) => _AdbDeviceTile(
                        device: device,
                        selected: device.serial == connection.selectedAdbSerial,
                        busy: connection.isConnecting,
                        onTap: () => notifier.switchAdbDevice(device.serial),
                      ),
                    )
                    .toList(),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: connection.isConnecting
                  ? null
                  : () => _showAdbSettingsDialog(context, notifier),
              icon: const Icon(Icons.settings_ethernet, size: 17),
              label: Text(l10n.desktopConnectionConfigureAdb),
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
