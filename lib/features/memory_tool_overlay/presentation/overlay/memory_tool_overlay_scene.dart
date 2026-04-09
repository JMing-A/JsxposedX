import 'package:JsxposedX/common/widgets/overlay_window/overlay_window.dart';
import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/pages/memory_tool_overlay.dart';
import 'package:JsxposedX/features/overlay_window/domain/models/overlay_window_presentation.dart';
import 'package:JsxposedX/features/overlay_window/presentation/models/overlay_scene_definition.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class MemoryToolOverlayScene {
  const MemoryToolOverlayScene._();

  static const int sceneId = 0;

  static const OverlaySceneDefinition definition = OverlaySceneDefinition(
    sceneId: sceneId,
    bubbleSize: OverlayWindowPresentation.defaultBubbleSize,
    title: _title,
    subtitle: _subtitle,
    notificationTitle: _title,
    notificationContent: _notificationContent,
    panelBuilder: _panelBuilder,
    panelMargin: _panelMargin,
    panelHeaderBuilder: _panelHeaderBuilder,
  );

  static String _title(BuildContext context) =>
      context.l10n.overlayMemoryToolTitle;

  static String _subtitle(BuildContext context) =>
      context.l10n.overlayFloatingToolWindow;

  static String _notificationContent(BuildContext context) =>
      context.l10n.overlayWindowNotificationContent;

  static EdgeInsetsGeometry _panelMargin(BuildContext context) =>
      EdgeInsets.all(8.r);

  static Widget _panelHeaderBuilder(
    BuildContext context,
    OverlayScenePanelControls controls,
  ) {
    return OverlayWindowHeader(
      leading: Container(
        width: 42.w,
        height: 42.w,
        decoration: BoxDecoration(
          color: context.colorScheme.primary,
          borderRadius: BorderRadius.circular(14.r),
        ),
        child: const Icon(
          Icons.memory_rounded,
          color: Colors.white,
          size: 20,
        ),
      ),
      title: _title(context),
      subtitle: _subtitle(context),
      actions: <Widget>[
        OverlayWindowHeaderButton(
          icon: Icons.remove_rounded,
          onPressed: controls.minimize,
        ),
        OverlayWindowHeaderButton(
          icon: Icons.close_rounded,
          onPressed: controls.close,
        ),
      ],
    );
  }

  static MemoryToolOverlay _panelBuilder(BuildContext context) =>
      const MemoryToolOverlay();
}
