import 'dart:io';
import 'package:JsxposedX/common/widgets/overlay_window/overlay_scene.dart';
import 'package:JsxposedX/common/widgets/overlay_window/overlay_window_geometry.dart';
import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

class OverlayWindowController extends ChangeNotifier {
  OverlayWindowController._();

  static final OverlayWindowController instance = OverlayWindowController._();
  static const double defaultBubbleSize = 58;

  Offset? _lastBubbleVisualOffset;

  OverlayWindowStatus _status = const OverlayWindowStatus(
    isSupported: true,
    hasPermission: false,
    isActive: false,
  );

  OverlayWindowStatus get status => _status;

  Future<OverlayWindowStatus> refresh() async {
    if (!_isSupportedPlatform) {
      _status = const OverlayWindowStatus(
        isSupported: false,
        hasPermission: false,
        isActive: false,
      );
      notifyListeners();
      return _status;
    }

    final hasPermission = await FlutterOverlayWindow.isPermissionGranted();
    final isActive = await FlutterOverlayWindow.isActive();
    _status = OverlayWindowStatus(
      isSupported: true,
      hasPermission: hasPermission,
      isActive: isActive,
    );
    notifyListeners();
    return _status;
  }

  Future<bool> ensurePermission() async {
    if (!_isSupportedPlatform) {
      return false;
    }

    final current = await refresh();
    if (current.hasPermission) {
      return true;
    }

    final granted = await FlutterOverlayWindow.requestPermission() ?? false;
    await refresh();
    return granted;
  }

  Future<OverlayWindowStatus> show(
    BuildContext context, {
    required int scene,
    OverlayWindowPresentation presentation = const OverlayWindowPresentation(),
  }) async {
    if (!_isSupportedPlatform) {
      return refresh();
    }

    final notificationTitle =
        presentation.notificationTitle ?? context.l10n.appName;
    final notificationContent =
        presentation.notificationContent ?? context.l10n.loading;
    final granted = await ensurePermission();
    if (!granted) {
      return status;
    }

    final bubbleLayout = await _resolveBubbleLayout(
      scene: scene,
      presentation: presentation,
    );
    final currentStatus = await refresh();
    if (!currentStatus.isActive) {
      await _showOverlayHost(
        notificationTitle: notificationTitle,
        notificationContent: notificationContent,
        bubbleLayout: bubbleLayout,
        enableDrag: presentation.enableDrag,
      );
    } else {
      await _updateOverlayLayout(
        width: bubbleLayout.hostWidth,
        height: bubbleLayout.hostHeight,
        position: bubbleLayout.hostPosition,
        enableDrag: presentation.enableDrag,
        flag: OverlayFlag.focusPointer,
      );
    }
    _lastBubbleVisualOffset = bubbleLayout.visualOffset;
    await _sharePayload(
      OverlayWindowPayload(
        scene: scene,
        displayMode: OverlayWindowDisplayMode.bubble,
      ),
    );
    return refresh();
  }

  Future<void> expand(
    BuildContext context, {
    required int scene,
    OverlayWindowPresentation presentation = const OverlayWindowPresentation(),
  }) async {
    if (!_isSupportedPlatform) {
      return;
    }

    final currentStatus = await refresh();
    if (!currentStatus.isActive) {
      return;
    }

    await _updateOverlayLayout(
      width: WindowSize.matchParent,
      height: WindowSize.fullCover,
      position: const OverlayPosition(0, 0),
      enableDrag: false,
      flag: OverlayFlag.defaultFlag,
    );
    await _sharePayload(
      OverlayWindowPayload(
        scene: scene,
        displayMode: OverlayWindowDisplayMode.panel,
      ),
    );
    await refresh();
  }

  Future<void> collapse(
    BuildContext context, {
    required int scene,
    OverlayWindowPresentation presentation = const OverlayWindowPresentation(),
  }) async {
    if (!_isSupportedPlatform) {
      return;
    }

    final currentStatus = await refresh();
    if (!currentStatus.isActive) {
      return;
    }

    final bubbleLayout = await _resolveBubbleLayout(
      scene: scene,
      presentation: presentation,
    );
    await _updateOverlayLayout(
      width: bubbleLayout.hostWidth,
      height: bubbleLayout.hostHeight,
      position: bubbleLayout.hostPosition,
      enableDrag: presentation.enableDrag,
      flag: OverlayFlag.focusPointer,
    );
    _lastBubbleVisualOffset = bubbleLayout.visualOffset;
    await _sharePayload(
      OverlayWindowPayload(
        scene: scene,
        displayMode: OverlayWindowDisplayMode.bubble,
      ),
    );
    await refresh();
  }

  Future<OverlayWindowStatus> hide() async {
    if (_isSupportedPlatform) {
      await FlutterOverlayWindow.closeOverlay();
    }
    return refresh();
  }

  bool get _isSupportedPlatform => !kIsWeb && Platform.isAndroid;

  Future<void> _sharePayload(OverlayWindowPayload payload) {
    return FlutterOverlayWindow.shareData(payload.toMap());
  }

  Future<void> _showOverlayHost({
    required String notificationTitle,
    required String notificationContent,
    required _BubbleOverlayLayout bubbleLayout,
    required bool enableDrag,
  }) {
    return FlutterOverlayWindow.showOverlay(
      width: bubbleLayout.hostWidth,
      height: bubbleLayout.hostHeight,
      alignment: OverlayAlignment.topLeft,
      positionGravity: PositionGravity.none,
      enableDrag: enableDrag,
      flag: OverlayFlag.focusPointer,
      visibility: NotificationVisibility.visibilityPublic,
      overlayTitle: notificationTitle,
      overlayContent: notificationContent,
      startPosition: bubbleLayout.hostPosition,
    );
  }

  Future<void> _updateOverlayLayout({
    required int width,
    required int height,
    required OverlayPosition position,
    required bool enableDrag,
    required OverlayFlag flag,
  }) {
    return FlutterOverlayWindow.updateOverlayLayout(
      width: width,
      height: height,
      position: position,
      enableDrag: enableDrag,
      flag: flag,
    );
  }

  Future<_BubbleOverlayLayout> _resolveBubbleLayout({
    required int scene,
    required OverlayWindowPresentation presentation,
  }) async {
    final viewport = await FlutterOverlayWindow.getOverlayViewportMetrics();
    final bubbleSize = _bubbleSizeForScene(scene, presentation);
    final visualOffset = OverlayWindowGeometry.clampBubbleVisualOffset(
      _lastBubbleVisualOffset ??
          OverlayWindowGeometry.defaultBubbleVisualOffset(
            viewport: viewport,
            bubbleSize: bubbleSize,
          ),
      viewport: viewport,
      bubbleSize: bubbleSize,
    );
    return _BubbleOverlayLayout(
      hostWidth: _bubbleHostWidth(presentation).round(),
      hostHeight: _bubbleHostHeight(presentation).round(),
      hostPosition: OverlayWindowGeometry.hostPositionFromVisualOffset(
        visualOffset,
      ),
      visualOffset: visualOffset,
    );
  }

  double _bubbleSizeForScene(
    int scene,
    OverlayWindowPresentation presentation,
  ) {
    switch (scene) {
      case OverlaySceneEnum.memoryTool:
        return presentation.bubbleSize;
      default:
        return presentation.bubbleSize;
    }
  }

  double _bubbleHostWidth(OverlayWindowPresentation presentation) {
    return presentation.width ??
        OverlayWindowGeometry.bubbleHostExtent(presentation.bubbleSize);
  }

  double _bubbleHostHeight(OverlayWindowPresentation presentation) {
    return presentation.height ??
        OverlayWindowGeometry.bubbleHostExtent(presentation.bubbleSize);
  }
}

class OverlayWindowPresentation {
  const OverlayWindowPresentation({
    this.width,
    this.height,
    this.bubbleSize = OverlayWindowController.defaultBubbleSize,
    this.enableDrag = true,
    this.notificationTitle,
    this.notificationContent,
  });

  final double? width;
  final double? height;
  final double bubbleSize;
  final bool enableDrag;
  final String? notificationTitle;
  final String? notificationContent;
}

class OverlayWindowStatus {
  const OverlayWindowStatus({
    required this.isSupported,
    required this.hasPermission,
    required this.isActive,
  });

  final bool isSupported;
  final bool hasPermission;
  final bool isActive;

  bool get canShow => isSupported && hasPermission;
}

class _BubbleOverlayLayout {
  const _BubbleOverlayLayout({
    required this.hostWidth,
    required this.hostHeight,
    required this.hostPosition,
    required this.visualOffset,
  });

  final int hostWidth;
  final int hostHeight;
  final OverlayPosition hostPosition;
  final Offset visualOffset;
}
