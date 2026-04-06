import 'dart:async';

import 'package:JsxposedX/common/widgets/overlay_window/overlay_scene.dart';
import 'package:JsxposedX/common/widgets/overlay_window/overlay_window.dart';
import 'package:JsxposedX/common/widgets/overlay_window/overlay_window_scope.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/pages/memory_tool_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

class OverlayWindowRenderer extends StatefulWidget {
  const OverlayWindowRenderer({super.key});

  @override
  State<OverlayWindowRenderer> createState() => _OverlayWindowRendererState();
}

class _OverlayWindowRendererState extends State<OverlayWindowRenderer> {
  StreamSubscription<dynamic>? _subscription;
  int? _scene;

  @override
  void initState() {
    super.initState();
    _subscription = FlutterOverlayWindow.overlayListener.listen(_handleScene);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scene = _scene;
    if (scene == null) {
      return const SizedBox.shrink();
    }

    return OverlayWindow(
      onClose: () {
        unawaited(OverlayWindowScope.of(context).hide());
      },
      child: _buildScene(scene),
    );
  }

  void _handleScene(dynamic rawScene) {
    final nextScene = switch (rawScene) {
      int value => value,
      String value => int.tryParse(value),
      _ => null,
    };
    if (nextScene == null || !mounted || nextScene == _scene) {
      return;
    }

    setState(() {
      _scene = nextScene;
    });
  }

  Widget _buildScene(int scene) {
    switch (scene) {
      case OverlayScene.memoryTool:
        return const MemoryToolOverlay();
      default:
        return const SizedBox.shrink();
    }
  }
}
