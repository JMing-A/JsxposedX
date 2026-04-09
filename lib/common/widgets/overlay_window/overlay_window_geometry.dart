import 'package:flutter/widgets.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

class OverlayWindowGeometry {
  const OverlayWindowGeometry._();

  static const double bubbleEdgePadding = 16;
  static const double bubbleHostPadding = 16;

  static double bubbleHostExtent(double bubbleSize) {
    return bubbleSize + (bubbleHostPadding * 2);
  }

  static OverlayPosition hostPositionFromVisualOffset(Offset visualOffset) {
    return OverlayPosition(
      visualOffset.dx - bubbleHostPadding,
      visualOffset.dy - bubbleHostPadding,
    );
  }

  static Offset visualOffsetFromHostPosition(OverlayPosition hostPosition) {
    return Offset(
      hostPosition.x + bubbleHostPadding,
      hostPosition.y + bubbleHostPadding,
    );
  }

  static Offset defaultBubbleVisualOffset({
    required OverlayViewportMetrics viewport,
    required double bubbleSize,
  }) {
    final bounds = bubbleBounds(viewport: viewport, bubbleSize: bubbleSize);
    final centerY = bounds.top + (bounds.height / 2);
    return Offset(bounds.right, centerY);
  }

  static Offset clampBubbleVisualOffset(
    Offset offset, {
    required OverlayViewportMetrics viewport,
    required double bubbleSize,
  }) {
    final bounds = bubbleBounds(viewport: viewport, bubbleSize: bubbleSize);
    return Offset(
      offset.dx.clamp(bounds.left, bounds.right).toDouble(),
      offset.dy.clamp(bounds.top, bounds.bottom).toDouble(),
    );
  }

  static Offset snapBubbleVisualOffset(
    Offset offset, {
    required OverlayViewportMetrics viewport,
    required double bubbleSize,
  }) {
    final bounds = bubbleBounds(viewport: viewport, bubbleSize: bubbleSize);
    final bubbleCenterX = offset.dx + (bubbleSize / 2);
    final targetX = bubbleCenterX < (viewport.width / 2)
        ? bounds.left
        : bounds.right;
    return Offset(
      targetX,
      offset.dy.clamp(bounds.top, bounds.bottom).toDouble(),
    );
  }

  static OverlayBubbleBounds bubbleBounds({
    required OverlayViewportMetrics viewport,
    required double bubbleSize,
  }) {
    final safePadding = viewport.safePadding;
    final left = safePadding.left + bubbleEdgePadding;
    final top = safePadding.top + bubbleEdgePadding;
    final right =
        (viewport.width - bubbleSize - safePadding.right - bubbleEdgePadding)
            .clamp(left, double.infinity)
            .toDouble();
    final bottom =
        (viewport.height - bubbleSize - safePadding.bottom - bubbleEdgePadding)
            .clamp(top, double.infinity)
            .toDouble();
    return OverlayBubbleBounds(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
    );
  }
}

class OverlayBubbleBounds {
  const OverlayBubbleBounds({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get height => bottom - top;
}
