import 'package:JsxposedX/common/pages/toast.dart';
import 'package:JsxposedX/common/widgets/overlay_window/overlay_window.dart';
import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/features/overlay_window/domain/models/overlay_window_presentation.dart';
import 'package:JsxposedX/features/overlay_window/presentation/models/overlay_scene_definition.dart';
import 'package:flutter/material.dart';
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
    return OverlayWindowScaffold(
      overlayConfig: overlayConfig,
      overlayBar: OverlayWindowBar(
        title: Text(context.l10n.overlayMemoryToolTitle),
        subtitle: Text(context.l10n.overlayFloatingToolWindow),
        leading: const Icon(
          Icons.memory_rounded,
          color: Colors.white,
          size: 20,
        ),
        showMinimizeAction: true,
        showCloseAction: false,
      ),
      margin: EdgeInsets.all(8.r),
      body: const _MemoryToolOverlayBody(),
    );
  }
}

class _MemoryToolOverlayBody extends HookConsumerWidget {
  const _MemoryToolOverlayBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.max,
      children: <Widget>[
        Text(
          context.l10n.overlayQuickWorkspace,
          style: context.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: 8.h),
        Text(
          context.l10n.overlayQuickWorkspaceDescription,
          style: context.textTheme.bodyMedium?.copyWith(
            color: context.colorScheme.onSurfaceVariant,
            height: 1.45,
          ),
        ),
        SizedBox(height: 18.h),
        Wrap(
          spacing: 12.w,
          runSpacing: 12.h,
          children: <Widget>[
            _OverlayInfoCard(
              icon: Icons.circle_rounded,
              title: context.l10n.overlayBubbleFeatureTitle,
              description: context.l10n.overlayBubbleFeatureDescription,
            ),
            _OverlayInfoCard(
              icon: Icons.crop_square_rounded,
              title: context.l10n.overlayPanelFeatureTitle,
              description: context.l10n.overlayPanelFeatureDescription,
            ),
          ],
        ),
        SizedBox(height: 20.h),
        FilledButton.icon(
          onPressed: () {
            ToastMessage.show(context.l10n.overlayConnected);
          },
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(context.l10n.test),
        ),
      ],
    );
  }
}

class _OverlayInfoCard extends StatelessWidget {
  const _OverlayInfoCard({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220.w,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.58,
          ),
          borderRadius: BorderRadius.circular(16.r),
        ),
        child: Padding(
          padding: EdgeInsets.all(16.r),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, color: context.colorScheme.primary, size: 22.sp),
              SizedBox(height: 12.h),
              Text(
                title,
                style: context.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 6.h),
              Text(
                description,
                style: context.textTheme.bodySmall?.copyWith(
                  color: context.colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
