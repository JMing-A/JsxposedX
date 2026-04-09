import 'dart:async';

import 'package:JsxposedX/common/widgets/cache_image.dart';
import 'package:JsxposedX/common/widgets/overlay_window/overlay_scene.dart';
import 'package:JsxposedX/common/widgets/overlay_window/overlay_window.dart';
import 'package:JsxposedX/common/widgets/overlay_window/overlay_window_controller.dart';
import 'package:JsxposedX/common/widgets/overlay_window/overlay_window_geometry.dart';
import 'package:JsxposedX/common/widgets/overlay_window/overlay_window_scope.dart';
import 'package:JsxposedX/core/constants/assets_constants.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/pages/memory_tool_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

class OverlayWindowRenderer extends StatefulWidget {
  const OverlayWindowRenderer({super.key});

  @override
  State<OverlayWindowRenderer> createState() => _OverlayWindowRendererState();
}

class _OverlayWindowRendererState extends State<OverlayWindowRenderer>
    with WidgetsBindingObserver {
  static const double _panelMaxWidth = 560;
  static const double _panelMaxHeight = 720;

  StreamSubscription<dynamic>? _subscription;
  OverlayWindowPayload _payload = const OverlayWindowPayload(
    scene: OverlaySceneEnum.memoryTool,
  );
  OverlayViewportMetrics? _viewportMetrics;
  Offset? _bubbleVisualOffset;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscription = FlutterOverlayWindow.overlayListener.listen(_handlePayload);
    unawaited(_refreshViewportMetrics(syncBubblePosition: true));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    unawaited(_refreshViewportMetrics(syncBubblePosition: _payload.isBubble));
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: _payload.isPanel ? _buildPanelWindow(context) : _buildBubble(),
    );
  }

  void _handlePayload(dynamic rawPayload) {
    final overlayEvent = OverlayWindowEvent.maybeFromRaw(rawPayload);
    if (overlayEvent != null) {
      _handleOverlayEvent(overlayEvent);
      return;
    }

    final nextPayload = OverlayWindowPayload.fromRaw(rawPayload);
    if (!mounted) {
      return;
    }

    setState(() {
      _payload = nextPayload;
    });

    if (nextPayload.isBubble) {
      unawaited(_syncBubbleVisualOffsetFromHost());
    }
  }

  void _handleOverlayEvent(OverlayWindowEvent event) {
    if (!mounted || !_payload.isBubble) {
      return;
    }

    if (event.isBubbleTap) {
      unawaited(_setDisplayMode(OverlayWindowDisplayMode.panel));
      return;
    }

    if (!event.isBubbleDragEnd) {
      return;
    }

    final hostPosition = event.hostPosition;
    final viewport = _viewportMetrics;
    if (hostPosition == null || viewport == null) {
      return;
    }

    final bubbleSize = _bubbleSizeForScene(_payload.scene);
    final visualOffset = OverlayWindowGeometry.visualOffsetFromHostPosition(
      OverlayPosition(hostPosition.x, hostPosition.y),
    );
    final snappedVisualOffset = OverlayWindowGeometry.snapBubbleVisualOffset(
      visualOffset,
      viewport: viewport,
      bubbleSize: bubbleSize,
    );

    setState(() {
      _bubbleVisualOffset = snappedVisualOffset;
    });
    unawaited(_moveBubbleHostToVisualOffset(snappedVisualOffset));
  }

  Future<void> _setDisplayMode(String displayMode) async {
    if (_payload.displayMode == displayMode) {
      return;
    }

    if (displayMode == OverlayWindowDisplayMode.panel) {
      final updated = await FlutterOverlayWindow.updateOverlayLayout(
        width: WindowSize.matchParent,
        height: WindowSize.fullCover,
        position: const OverlayPosition(0, 0),
        enableDrag: false,
        flag: OverlayFlag.defaultFlag,
      );
      if (!mounted || updated != true) {
        return;
      }
      setState(() {
        _payload = _payload.copyWith(
          displayMode: OverlayWindowDisplayMode.panel,
        );
      });
      return;
    }

    final viewport = await _ensureViewportMetrics();
    if (!mounted || viewport == null) {
      return;
    }

    final bubbleSize = _bubbleSizeForScene(_payload.scene);
    final bubbleVisualOffset = OverlayWindowGeometry.clampBubbleVisualOffset(
      _bubbleVisualOffset ??
          OverlayWindowGeometry.defaultBubbleVisualOffset(
            viewport: viewport,
            bubbleSize: bubbleSize,
          ),
      viewport: viewport,
      bubbleSize: bubbleSize,
    );

    final updated = await FlutterOverlayWindow.updateOverlayLayout(
      width: OverlayWindowGeometry.bubbleHostExtent(bubbleSize).round(),
      height: OverlayWindowGeometry.bubbleHostExtent(bubbleSize).round(),
      position: OverlayWindowGeometry.hostPositionFromVisualOffset(
        bubbleVisualOffset,
      ),
      enableDrag: true,
      flag: OverlayFlag.focusPointer,
    );
    if (!mounted || updated != true) {
      return;
    }
    setState(() {
      _bubbleVisualOffset = bubbleVisualOffset;
      _payload = _payload.copyWith(
        displayMode: OverlayWindowDisplayMode.bubble,
      );
    });
  }

  Widget _buildPanelWindow(BuildContext context) {
    return OverlayWindow(
      title: _resolveTitle(_payload.scene),
      subtitle: 'Floating tool window',
      onBackdropTap: () => _setDisplayMode(OverlayWindowDisplayMode.bubble),
      onMinimize: () => _setDisplayMode(OverlayWindowDisplayMode.bubble),
      onClose: () {
        unawaited(OverlayWindowScope.of(context).hide());
      },
      maxWidth: _panelMaxWidth,
      maxHeight: _panelMaxHeight,
      child: _buildScene(_payload.scene),
    );
  }

  Widget _buildBubble() {
    return SizedBox.expand(
      child: Padding(
        padding: const EdgeInsets.all(OverlayWindowGeometry.bubbleHostPadding),
        child: _OverlayBubble(size: _bubbleSizeForScene(_payload.scene)),
      ),
    );
  }

  Future<OverlayViewportMetrics?> _ensureViewportMetrics() async {
    if (_viewportMetrics != null) {
      return _viewportMetrics;
    }
    return _refreshViewportMetrics(syncBubblePosition: false);
  }

  Future<OverlayViewportMetrics?> _refreshViewportMetrics({
    required bool syncBubblePosition,
  }) async {
    final viewport = await FlutterOverlayWindow.getOverlayViewportMetrics();
    if (!mounted) {
      return viewport;
    }

    setState(() {
      _viewportMetrics = viewport;
      if (_bubbleVisualOffset != null) {
        final bubbleSize = _bubbleSizeForScene(_payload.scene);
        _bubbleVisualOffset = OverlayWindowGeometry.clampBubbleVisualOffset(
          _bubbleVisualOffset!,
          viewport: viewport,
          bubbleSize: bubbleSize,
        );
      }
    });

    if (syncBubblePosition && _payload.isBubble) {
      await _syncBubbleVisualOffsetFromHost();
    }
    return viewport;
  }

  Future<void> _syncBubbleVisualOffsetFromHost() async {
    final viewport = await _ensureViewportMetrics();
    if (!mounted || viewport == null) {
      return;
    }

    final bubbleSize = _bubbleSizeForScene(_payload.scene);
    final hostPosition = await FlutterOverlayWindow.getOverlayPosition();
    final visualOffset = OverlayWindowGeometry.clampBubbleVisualOffset(
      OverlayWindowGeometry.visualOffsetFromHostPosition(hostPosition),
      viewport: viewport,
      bubbleSize: bubbleSize,
    );
    if (!mounted) {
      return;
    }

    setState(() {
      _bubbleVisualOffset = visualOffset;
    });
  }

  Future<void> _moveBubbleHostToVisualOffset(Offset bubbleVisualOffset) async {
    await FlutterOverlayWindow.moveOverlay(
      OverlayWindowGeometry.hostPositionFromVisualOffset(bubbleVisualOffset),
    );
  }

  Widget _buildScene(int scene) {
    switch (scene) {
      case OverlaySceneEnum.memoryTool:
        return const MemoryToolOverlay();
      default:
        return const SizedBox.shrink();
    }
  }

  double _bubbleSizeForScene(int scene) {
    switch (scene) {
      case OverlaySceneEnum.memoryTool:
        return OverlayWindowController.defaultBubbleSize;
      default:
        return OverlayWindowController.defaultBubbleSize;
    }
  }

  String _resolveTitle(int scene) {
    switch (scene) {
      case OverlaySceneEnum.memoryTool:
        return 'Memory Tool';
      default:
        return 'Overlay Window';
    }
  }
}

class _OverlayBubble extends StatelessWidget {
  const _OverlayBubble({required this.size});

  final double size;

  static const LinearGradient _bubbleGradient = LinearGradient(
    colors: <Color>[Color(0xFF70D7F9), Color(0xFFAD98FF), Color(0xFFFFB385)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: _bubbleGradient,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: const Color(
                0xFF70D7F9,
              ).withValues(alpha: isDark ? 0.34 : 0.30),
              blurRadius: 15,
              spreadRadius: 2,
            ),
            BoxShadow(
              color: const Color(
                0xFFAD98FF,
              ).withValues(alpha: isDark ? 0.32 : 0.30),
              blurRadius: 20,
              offset: const Offset(5, 5),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.14 : 0.08),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: SizedBox(
          width: size,
          height: size,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              ),
              child: Padding(
                padding: const EdgeInsets.all(1),
                child: ClipOval(
                  child: CacheImage(
                    imageUrl: AssetsConstants.logo,
                    width: size,
                    height: size,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
