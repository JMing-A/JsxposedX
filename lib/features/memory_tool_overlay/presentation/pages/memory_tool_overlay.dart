import 'package:JsxposedX/common/widgets/overlay_window/overlay_window.dart';
import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/providers/memory_query_provider.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/widgets/memory_tool_overlay_l10n.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/widgets/process_avatar.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/widgets/process_picker_dialog.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/widgets/selected_process_panel.dart';
import 'package:JsxposedX/features/overlay_window/domain/models/overlay_window_presentation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class MemoryToolOverlay extends HookConsumerWidget {
  const MemoryToolOverlay({super.key});

  OverlayWindowConfig get overlayConfig => OverlayWindowConfig(
    sceneId: 0,
    bubbleSize: OverlayWindowPresentation.defaultBubbleSize,
    notificationTitle: (context) => context.l10n.overlayMemoryToolTitle,
    notificationContent: (context) =>
        context.l10n.overlayWindowNotificationContent,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    useAutomaticKeepAlive();
    final isPickerVisible = useState(false);
    final selectedProcess = ref.watch(memoryToolSelectedProcessProvider);
    final mediaQuery = MediaQuery.of(context);
    final isPortrait = mediaQuery.orientation == Orientation.portrait;
    final portraitTopInset = isPortrait ? mediaQuery.padding.top : 0.0;

    return DefaultTabController(
      length: 3,
      child: Stack(
        children: [
          OverlayWindowScaffold(
            overlayConfig: overlayConfig,
            overlayBar: OverlayWindowBar(
              backgroundColor: context.colorScheme.surface.withValues(alpha: 0.3),
              toolbarHeight: 52.r,
              titleSpacing: 0,
              leadingWidth: 48.r,
              leading: IconButton(
                padding: EdgeInsets.zero,
                onPressed: () {
                  isPickerVisible.value = true;
                },
                icon: ProcessAvatar(process: selectedProcess),
              ),
              title: TabBar(
                dividerColor: Colors.transparent,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  borderRadius: BorderRadius.circular(14.r),
                  color: context.colorScheme.primary.withValues(alpha: 0.14),
                ),
                labelColor: context.colorScheme.primary,
                unselectedLabelColor: context.colorScheme.onSurfaceVariant,
                labelStyle: context.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
                tabs: <Widget>[
                  Tab(text: context.l10n.memoryToolTabSearch),
                  Tab(text: context.l10n.memoryToolTabEdit),
                  Tab(text: context.l10n.memoryToolTabWatch),
                ],
              ),
              showMinimizeAction: true,
              showCloseAction: false,
            ),
            backgroundColor: context.colorScheme.surface.withValues(alpha: 0.6),
            padding: EdgeInsets.only(top: portraitTopInset),
            body: SelectedProcessPanel(selectedProcess: selectedProcess),
          ),
          if (isPickerVisible.value)
            Positioned.fill(
              child: MemoryToolProcessPickerDialog(
                onClose: () {
                  isPickerVisible.value = false;
                },
                onSelected: (process) {
                  ref
                      .read(memoryToolSelectedProcessProvider.notifier)
                      .select(process);
                  isPickerVisible.value = false;
                },
                onRetry: () {
                  ref.invalidate(getProcessInfoProvider(offset: 0, limit: 20));
                },
              ),
            ),
        ],
      ),
    );
  }
}
