import 'dart:math' as math;
import 'dart:ui';

import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_session_init_state.dart';
import 'package:JsxposedX/features/ai/presentation/providers/runtime/ai_chat_runtime_provider.dart';
import 'package:JsxposedX/features/ai/presentation/runtime/ai_chat_environment_initializer.dart';
import 'package:JsxposedX/features/ai/presentation/states/ai_chat_runtime_state.dart';
import 'package:JsxposedX/features/ai/presentation/widgets/ai_chat_input.dart';
import 'package:JsxposedX/features/ai/presentation/widgets/ai_chat_list.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/providers/ai_overlay_ui_state_provider.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/providers/memory_ai_overlay_environment_provider.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/providers/memory_query_provider.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/widgets/ai_overlay_collapsed_ball.dart';
import 'package:JsxposedX/features/overlay_window/presentation/providers/overlay_window_host_runtime_provider.dart';
import 'package:JsxposedX/generated/memory_tool.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class AiOverlay extends HookConsumerWidget {
  const AiOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedProcess = ref.watch(memoryToolSelectedProcessProvider);
    final isPanelVisible = ref.watch(
      overlayWindowHostRuntimeProvider.select(
        (state) => state.payload.isPanel && !state.isTransitioningToPanel,
      ),
    );

    if (!isPanelVisible || selectedProcess == null) {
      return const SizedBox.shrink();
    }

    final mediaQuery = MediaQuery.of(context);
    final portraitTopInset = mediaQuery.orientation == Orientation.portrait
        ? mediaQuery.padding.top
        : 0.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportSize = Size(
          constraints.hasBoundedWidth ? constraints.maxWidth : mediaQuery.size.width,
          constraints.hasBoundedHeight
              ? constraints.maxHeight
              : mediaQuery.size.height,
        );
        return _AiOverlayViewport(
          selectedProcess: selectedProcess,
          viewportSize: viewportSize,
          portraitTopInset: portraitTopInset,
        );
      },
    );
  }
}

class _AiOverlayViewport extends HookConsumerWidget {
  const _AiOverlayViewport({
    required this.selectedProcess,
    required this.viewportSize,
    required this.portraitTopInset,
  });

  final ProcessInfo selectedProcess;
  final Size viewportSize;
  final double portraitTopInset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overlayState = ref.watch(aiOverlayUiStateControllerProvider);
    final overlayStateNotifier = ref.read(aiOverlayUiStateControllerProvider.notifier);
    final isExpanded = overlayState.isExpanded;
    final offset = overlayState.offset;
    final persistedPanelSize = overlayState.panelSize;
    final dragStartGlobal = useRef<Offset?>(null);
    final dragStartOffset = useRef<Offset?>(null);
    final resizeStartGlobal = useRef<Offset?>(null);
    final resizeStartSize = useRef<Size?>(null);
    final isResizing = useRef(false);
    final pendingBoundPid = useRef<int?>(null);
    final pendingLayoutKey = useRef<String?>(null);
    final environment = ref.watch(
      memoryAiOverlayEnvironmentProvider(
        MemoryAiOverlayEnvironmentArgs(
          processInfo: selectedProcess,
          isZh: context.isZh,
        ),
      ),
    );
    final chatScopeId = environment.scopeId;
    final chatNotifier = ref.read(
      aiChatRuntimeProvider(packageName: chatScopeId).notifier,
    );
    final chatState = ref.watch(
      aiChatRuntimeProvider(packageName: chatScopeId),
    );
    final scrollController = useScrollController();
    final collapsedDiameter = 44.r;
    final defaultExpandedSize = Size(320.r, 420.r);
    final minExpandedSize = Size(260.r, 280.r);
    final safePadding = 12.r;
    final expandedBorderRadius = 20.r;
    final collapsedBorderRadius = 14.r;
    final resizeHandleHighlightExtent = 28.r;
    final resizeHandleHitExtent = 34.r;
    final displayTitle = selectedProcess.name.trim().isEmpty
        ? selectedProcess.packageName
        : selectedProcess.name;
    final displaySubtitle =
        '${selectedProcess.packageName} · PID ${selectedProcess.pid}';

    Future<void> initializeOverlayChat() async {
      await initializeAiChatEnvironment(
        notifier: chatNotifier,
        environment: environment,
        initErrorPrefix: context.isZh ? '内存会话初始化失败' : 'Memory session init failed',
      );
    }

    final availableExpandedWidth = math.max(
      viewportSize.width - (safePadding * 2),
      collapsedDiameter,
    );
    final availableExpandedHeight = math.max(
      viewportSize.height - portraitTopInset - (safePadding * 2),
      collapsedDiameter,
    );
    final effectiveMinExpandedWidth = math.min(
      minExpandedSize.width,
      availableExpandedWidth,
    );
    final effectiveMinExpandedHeight = math.min(
      minExpandedSize.height,
      availableExpandedHeight,
    );

    Size clampExpandedSize(Size size) {
      return Size(
        size.width.clamp(effectiveMinExpandedWidth, availableExpandedWidth),
        size.height.clamp(
          effectiveMinExpandedHeight,
          availableExpandedHeight,
        ),
      );
    }

    final expandedSize = clampExpandedSize(
      persistedPanelSize ?? defaultExpandedSize,
    );

    Size currentSize() => isExpanded
        ? expandedSize
        : Size(collapsedDiameter, collapsedDiameter);

    Offset defaultOffset(Size size) => Offset(
      viewportSize.width - size.width - 20.r,
      portraitTopInset + 88.r,
    );

    Offset clampOffset(Offset value, Size size) {
      final minX = safePadding;
      final maxX = math.max(
        minX,
        viewportSize.width - size.width - safePadding,
      );
      final minY = portraitTopInset + safePadding;
      final maxY = math.max(
        minY,
        viewportSize.height - size.height - safePadding,
      );
      return Offset(value.dx.clamp(minX, maxX), value.dy.clamp(minY, maxY));
    }

    useEffect(() {
      final size = Size(collapsedDiameter, collapsedDiameter);
      final nextOffset = clampOffset(defaultOffset(size), size);
      if (pendingBoundPid.value == selectedProcess.pid) {
        return null;
      }
      pendingBoundPid.value = selectedProcess.pid;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        pendingBoundPid.value = null;
        if (!context.mounted) {
          return;
        }
        overlayStateNotifier.bindProcess(
          pid: selectedProcess.pid,
          initialOffset: nextOffset,
          initialPanelSize: clampExpandedSize(defaultExpandedSize),
        );
      });
      return null;
    }, [selectedProcess.pid]);

    useEffect(() {
      Future.microtask(() async {
        await initializeOverlayChat();
      });
      return null;
    }, [environment, chatScopeId]);

    useEffect(
      () {
        final nextPanelSize = clampExpandedSize(
          persistedPanelSize ?? defaultExpandedSize,
        );
        final panelSizeChanged = persistedPanelSize != nextPanelSize;
        final size = isExpanded
            ? nextPanelSize
            : Size(collapsedDiameter, collapsedDiameter);
        final nextOffset = clampOffset(offset ?? defaultOffset(size), size);
        final layoutKey =
            '${viewportSize.width}:${viewportSize.height}:$portraitTopInset:$isExpanded:${nextPanelSize.width}:${nextPanelSize.height}:${nextOffset.dx}:${nextOffset.dy}:${panelSizeChanged ? 1 : 0}';
        if (pendingLayoutKey.value == layoutKey) {
          return null;
        }
        pendingLayoutKey.value = layoutKey;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          pendingLayoutKey.value = null;
          if (!context.mounted) {
            return;
          }
          if (panelSizeChanged) {
            overlayStateNotifier.setPanelSize(nextPanelSize);
          }
          overlayStateNotifier.setOffset(nextOffset);
        });
        return null;
      },
      [
        viewportSize.width,
        viewportSize.height,
        portraitTopInset,
        isExpanded,
        persistedPanelSize?.width,
        persistedPanelSize?.height,
      ],
    );

    final lastMessageId = useRef<String?>(null);
    useEffect(() {
      final visibleMessages = chatState.visibleMessages;
      if (visibleMessages.isEmpty) {
        return null;
      }

      final currentLastId = visibleMessages.last.id;
      final isNewMessage = lastMessageId.value != currentLastId;
      lastMessageId.value = currentLastId;
      if (!scrollController.hasClients || !isNewMessage) {
        return null;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!scrollController.hasClients) {
          return;
        }
        scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      });
      return null;
    }, [chatState.visibleMessages.length]);

    useEffect(() {
      const followThreshold = 80.0;
      final subscription = chatNotifier.streamingContentStream.listen((content) {
        if (content.isEmpty || !scrollController.hasClients) {
          return;
        }
        if (scrollController.offset > followThreshold) {
          return;
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!scrollController.hasClients) {
            return;
          }
          if (scrollController.offset > followThreshold) {
            return;
          }
          scrollController.jumpTo(0);
        });
      });
      return subscription.cancel;
    }, [chatNotifier, scrollController]);

    final resolvedSize = currentSize();
    final resolvedOffset = clampOffset(
      offset ?? defaultOffset(resolvedSize),
      resolvedSize,
    );
    final showExpandedPanel =
        isExpanded &&
        resolvedSize.width > (collapsedDiameter + 4.r) &&
        resolvedSize.height > (collapsedDiameter + 4.r);

    void startDragging(Offset globalPosition) {
      if (isResizing.value) {
        return;
      }
      dragStartGlobal.value = globalPosition;
      dragStartOffset.value = resolvedOffset;
    }

    void updateDragging(Offset globalPosition, Size size) {
      if (isResizing.value) {
        return;
      }
      final startGlobal = dragStartGlobal.value;
      final startOffset = dragStartOffset.value;
      if (startGlobal == null || startOffset == null) {
        return;
      }
      final delta = globalPosition - startGlobal;
      overlayStateNotifier.setOffset(clampOffset(startOffset + delta, size));
    }

    void stopDragging() {
      dragStartGlobal.value = null;
      dragStartOffset.value = null;
    }

    return Stack(
      children: [
        Positioned(
          left: resolvedOffset.dx,
          top: resolvedOffset.dy,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: showExpandedPanel
                ? null
                : (details) => startDragging(details.globalPosition),
            onPanUpdate: showExpandedPanel
                ? null
                : (details) =>
                      updateDragging(details.globalPosition, resolvedSize),
            onPanEnd: showExpandedPanel ? null : (_) => stopDragging(),
            onPanCancel: showExpandedPanel ? null : stopDragging,
            child: CustomPaint(
              foregroundPainter: showExpandedPanel
                  ? _AiOverlayResizeBorderHighlightPainter(
                      color: context.colorScheme.primary.withValues(alpha: 0.94),
                      borderRadius: expandedBorderRadius,
                      clipExtent: resizeHandleHighlightExtent,
                    )
                  : null,
              child: Container(
                width: resolvedSize.width,
                height: resolvedSize.height,
                decoration: BoxDecoration(
                  color: showExpandedPanel
                      ? context.colorScheme.surfaceContainerHighest.withValues(
                          alpha: 0.76,
                        )
                      : null,
                  gradient: showExpandedPanel
                      ? null
                      : RadialGradient(
                          center: Alignment.center,
                          radius: 0.95,
                          colors: <Color>[
                            context.colorScheme.primary,
                            Color.lerp(
                                  context.colorScheme.primary,
                                  context.colorScheme.primaryContainer,
                                  0.58,
                                ) ??
                                context.colorScheme.primaryContainer,
                          ],
                          stops: const <double>[0.38, 1],
                        ),
                  borderRadius: BorderRadius.circular(
                    showExpandedPanel
                        ? expandedBorderRadius
                        : collapsedBorderRadius,
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color:
                          (showExpandedPanel
                                  ? Colors.black
                                  : context.colorScheme.primary)
                              .withValues(alpha: showExpandedPanel ? 0.1 : 0.18),
                      blurRadius: showExpandedPanel ? 16.r : 10.r,
                      offset: Offset(0, showExpandedPanel ? 6.r : 4.r),
                    ),
                    if (!showExpandedPanel)
                      BoxShadow(
                        color: context.colorScheme.primary.withValues(alpha: 0.32),
                        blurRadius: 14.r,
                        spreadRadius: 1.2.r,
                      ),
                  ],
                  border: Border.all(
                    color: showExpandedPanel
                        ? context.colorScheme.outlineVariant.withValues(
                            alpha: 0.34,
                          )
                        : context.colorScheme.onPrimary.withValues(alpha: 0.22),
                    width: 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: showExpandedPanel
                    ? Stack(
                        children: <Widget>[
                          Positioned.fill(
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                              child: ColoredBox(
                                color: context.colorScheme.surface.withValues(
                                  alpha: 0.08,
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 0,
                            top: 0,
                            right: resizeHandleHitExtent,
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onPanStart: (details) {
                                startDragging(details.globalPosition);
                              },
                              onPanUpdate: (details) {
                                updateDragging(
                                  details.globalPosition,
                                  resolvedSize,
                                );
                              },
                              onPanEnd: (_) {
                                stopDragging();
                              },
                              onPanCancel: stopDragging,
                              child: Padding(
                                padding: EdgeInsets.fromLTRB(
                                  14.r,
                                  12.r,
                                  12.r,
                                  0,
                                ),
                                child: Row(
                                  children: [
                                    Material(
                                      color: context.colorScheme.surface
                                          .withValues(alpha: 0.28),
                                      borderRadius: BorderRadius.circular(12.r),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(
                                          12.r,
                                        ),
                                        onTap: () {
                                          overlayStateNotifier.setExpanded(
                                            false,
                                          );
                                        },
                                        child: Padding(
                                          padding: EdgeInsets.all(4.r),
                                          child: Icon(
                                            Icons.remove_rounded,
                                            size: 16.r,
                                            color: context.colorScheme.onSurface
                                                .withValues(alpha: 0.82),
                                          ),
                                        ),
                                      ),
                                    ),
                                    SizedBox(width: 10.r),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            displayTitle,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 13.sp,
                                              fontWeight: FontWeight.w700,
                                              color:
                                                  context.colorScheme.onSurface,
                                            ),
                                          ),
                                          SizedBox(height: 2.r),
                                          Text(
                                            displaySubtitle,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 11.sp,
                                              color: context
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 8.r,
                                        vertical: 4.r,
                                      ),
                                      decoration: BoxDecoration(
                                        color: context.colorScheme.primary
                                            .withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(
                                          999.r,
                                        ),
                                      ),
                                      child: Text(
                                        context.isZh ? 'AI 对话' : 'AI Chat',
                                        style: TextStyle(
                                          fontSize: 10.5.sp,
                                          fontWeight: FontWeight.w700,
                                          color: context.colorScheme.primary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              10.r,
                              56.r,
                              10.r,
                              6.r,
                            ),
                            child: Column(
                              children: [
                                _AiOverlayInitBanner(
                                  chatState: chatState,
                                  onRetry: initializeOverlayChat,
                                ),
                                Expanded(
                                  child: AiChatList(
                                    messages: chatState.visibleMessages,
                                    scrollController: scrollController,
                                    packageName: chatScopeId,
                                    customTitle: context.isZh
                                        ? '内存调试助手'
                                        : 'Memory Assistant',
                                    customSubtitle: displaySubtitle,
                                  ),
                                ),
                                AiChatInput(
                                  packageName: chatScopeId,
                                  showQuickActions: false,
                                  onRetryInitialization: initializeOverlayChat,
                                ),
                              ],
                            ),
                          ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onPanStart: (details) {
                                isResizing.value = true;
                                resizeStartGlobal.value = details.globalPosition;
                                resizeStartSize.value = expandedSize;
                              },
                              onPanUpdate: (details) {
                                final startGlobal = resizeStartGlobal.value;
                                final startSize = resizeStartSize.value;
                                if (startGlobal == null || startSize == null) {
                                  return;
                                }
                                final delta =
                                    details.globalPosition - startGlobal;
                                final nextSize = clampExpandedSize(
                                  Size(
                                    startSize.width + delta.dx,
                                    startSize.height + delta.dy,
                                  ),
                                );
                                overlayStateNotifier.setPanelSize(nextSize);
                                overlayStateNotifier.setOffset(
                                  clampOffset(resolvedOffset, nextSize),
                                );
                              },
                              onPanEnd: (_) {
                                resizeStartGlobal.value = null;
                                resizeStartSize.value = null;
                                isResizing.value = false;
                              },
                              onPanCancel: () {
                                resizeStartGlobal.value = null;
                                resizeStartSize.value = null;
                                isResizing.value = false;
                              },
                              child: SizedBox(
                                width: resizeHandleHitExtent,
                                height: resizeHandleHitExtent,
                              ),
                            ),
                          ),
                        ],
                      )
                    : AiOverlayCollapsedBall(
                        onTap: () {
                          overlayStateNotifier.setExpanded(true);
                        },
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AiOverlayInitBanner extends StatelessWidget {
  const _AiOverlayInitBanner({
    required this.chatState,
    required this.onRetry,
  });

  final AiChatRuntimeState chatState;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    if (chatState.sessionInitState == AiSessionInitState.ready) {
      return const SizedBox.shrink();
    }

    final isInitializing =
        chatState.sessionInitState == AiSessionInitState.initializing;
    final backgroundColor = isInitializing
        ? context.colorScheme.primaryContainer.withValues(alpha: 0.78)
        : context.colorScheme.errorContainer.withValues(alpha: 0.84);
    final foregroundColor = isInitializing
        ? context.colorScheme.onPrimaryContainer
        : context.colorScheme.onErrorContainer;
    final message = isInitializing
        ? (context.isZh ? '正在准备当前进程的 AI 会话…' : 'Preparing AI session…')
        : (chatState.error ??
              (context.isZh
                  ? '当前进程的 AI 会话初始化失败'
                  : 'AI session init failed'));

    return Container(
      width: double.infinity,
      margin: EdgeInsets.fromLTRB(6.r, 0, 6.r, 8.r),
      padding: EdgeInsets.symmetric(horizontal: 12.r, vertical: 10.r),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(14.r),
      ),
      child: Row(
        children: [
          Icon(
            isInitializing
                ? Icons.hourglass_top_rounded
                : Icons.error_outline_rounded,
            size: 16.r,
            color: foregroundColor,
          ),
          SizedBox(width: 8.r),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5.sp,
                color: foregroundColor,
              ),
            ),
          ),
          if (!isInitializing)
            TextButton(
              onPressed: () async {
                await onRetry();
              },
              child: Text(
                context.l10n.retry,
                style: TextStyle(color: foregroundColor),
              ),
            ),
        ],
      ),
    );
  }
}

class _AiOverlayResizeBorderHighlightPainter extends CustomPainter {
  const _AiOverlayResizeBorderHighlightPainter({
    required this.color,
    required this.borderRadius,
    required this.clipExtent,
  });

  final Color color;
  final double borderRadius;
  final double clipExtent;

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 2.2;
    const glowStrokeWidth = 4.2;
    final clipPadding = 6.0;
    final glowStroke = Paint()
      ..color = color.withValues(alpha: 0.34)
      ..style = PaintingStyle.stroke
      ..strokeWidth = glowStrokeWidth
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.5);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final outerRRect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(borderRadius),
    );
    final glowRRect = outerRRect.deflate(glowStrokeWidth / 2);
    final rRect = outerRRect.deflate(strokeWidth / 2);

    canvas.save();
    canvas.clipRect(
      Rect.fromLTWH(
        size.width - clipExtent - clipPadding,
        size.height - clipExtent - clipPadding,
        clipExtent + clipPadding,
        clipExtent + clipPadding,
      ),
    );
    canvas.drawRRect(glowRRect, glowStroke);
    canvas.drawRRect(rRect, stroke);
    canvas.restore();
  }

  @override
  bool shouldRepaint(
    covariant _AiOverlayResizeBorderHighlightPainter oldDelegate,
  ) {
    return oldDelegate.color != color ||
        oldDelegate.borderRadius != borderRadius ||
        oldDelegate.clipExtent != clipExtent;
  }
}
