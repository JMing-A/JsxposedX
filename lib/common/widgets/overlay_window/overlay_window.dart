import 'dart:math' as math;

import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/features/overlay_window/presentation/models/overlay_scene_definition.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class OverlayWindowPanelControls {
  const OverlayWindowPanelControls({
    required this.minimize,
    required this.close,
  });

  final VoidCallback minimize;
  final VoidCallback close;
}

class OverlayWindowPanelScope extends InheritedWidget {
  const OverlayWindowPanelScope({
    super.key,
    required this.controls,
    required super.child,
  });

  final OverlayWindowPanelControls controls;

  static OverlayWindowPanelControls? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<OverlayWindowPanelScope>()
        ?.controls;
  }

  @override
  bool updateShouldNotify(OverlayWindowPanelScope oldWidget) {
    return controls != oldWidget.controls;
  }
}

class OverlayWindow extends StatelessWidget {
  const OverlayWindow({
    super.key,
    required this.child,
    this.header,
    this.onBackdropTap,
    this.footer,
    this.margin,
    this.maxWidth,
    this.maxHeight,
    this.backdrop,
    this.decoration,
    this.contentDecoration,
    this.padding,
    this.contentPadding,
  });

  final Widget child;
  final Widget? header;
  final VoidCallback? onBackdropTap;
  final Widget? footer;
  final EdgeInsetsGeometry? margin;
  final double? maxWidth;
  final double? maxHeight;
  final Widget? backdrop;
  final Decoration? decoration;
  final Decoration? contentDecoration;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    final hasHeader = header != null;
    final resolvedMargin = margin ?? EdgeInsets.zero;
    final resolvedPadding = padding ?? EdgeInsets.zero;
    final resolvedContentPadding = contentPadding ?? EdgeInsets.zero;

    return Material(
      color: Colors.transparent,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final shouldFillWidth = maxWidth == null;
          final shouldFillHeight = maxHeight == null;
          final resolvedMaxWidth = maxWidth == null
              ? constraints.maxWidth
              : math.min(maxWidth!, constraints.maxWidth);
          final resolvedMaxHeight = maxHeight == null
              ? constraints.maxHeight
              : math.min(maxHeight!, constraints.maxHeight);

          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onBackdropTap,
                child: backdrop ?? const SizedBox.expand(),
              ),
              SafeArea(
                child: Padding(
                  padding: resolvedMargin,
                  child: Align(
                    alignment: Alignment.center,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: shouldFillWidth ? resolvedMaxWidth : 0,
                        maxWidth: resolvedMaxWidth,
                        minHeight: shouldFillHeight ? resolvedMaxHeight : 0,
                        maxHeight: resolvedMaxHeight,
                      ),
                      child: DecoratedBox(
                        decoration: decoration ?? const BoxDecoration(),
                        child: Padding(
                          padding: resolvedPadding,
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                if (hasHeader) header!,
                                if (hasHeader) const SizedBox(height: 16),
                                DecoratedBox(
                                  decoration:
                                      contentDecoration ??
                                      const BoxDecoration(),
                                  child: Padding(
                                    padding: resolvedContentPadding,
                                    child: child,
                                  ),
                                ),
                                if (footer != null) ...<Widget>[
                                  const SizedBox(height: 12),
                                  footer!,
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class OverlayWindowScaffold extends StatelessWidget {
  const OverlayWindowScaffold({
    super.key,
    this.body,
    this.overlayConfig,
    this.overlayBar,
    this.bottomBar,
    this.onBackdropTap,
    this.margin,
    this.maxWidth,
    this.maxHeight,
    this.backdrop,
    this.decoration,
    this.contentDecoration,
    this.padding,
    this.contentPadding,
    @Deprecated('Use body instead.') this.child,
    @Deprecated('Use overlayBar instead.') this.header,
    @Deprecated('Use bottomBar instead.') this.footer,
  }) : assert(body != null || child != null, 'body is required.');

  final Widget? body;
  final OverlayWindowConfig? overlayConfig;
  final Widget? overlayBar;
  final Widget? bottomBar;
  @Deprecated('Use overlayBar instead.')
  final Widget? header;
  @Deprecated('Use bottomBar instead.')
  final Widget? footer;
  @Deprecated('Use body instead.')
  final Widget? child;
  final VoidCallback? onBackdropTap;
  final EdgeInsetsGeometry? margin;
  final double? maxWidth;
  final double? maxHeight;
  final Widget? backdrop;
  final Decoration? decoration;
  final Decoration? contentDecoration;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? contentPadding;

  OverlaySceneDefinition toSceneDefinition() {
    assert(
      overlayConfig != null,
      'overlayConfig is required for overlay scene registration.',
    );
    return OverlaySceneDefinition(
      sceneId: overlayConfig!.sceneId,
      bubbleSize: overlayConfig!.bubbleSize,
      notificationTitle: overlayConfig!.notificationTitle,
      notificationContent: overlayConfig!.notificationContent,
      panelBuilder: (_) => this,
    );
  }

  int get registeredSceneId {
    assert(
      overlayConfig != null,
      'overlayConfig is required for overlay scene registration.',
    );
    return overlayConfig!.sceneId;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final controls = OverlayWindowPanelScope.maybeOf(context);
    final resolvedBody = body ?? child!;
    final resolvedOverlayBar = overlayBar ?? header;
    final resolvedBottomBar = bottomBar ?? footer;
    final resolvedBackdrop =
        backdrop ??
        DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.scrim.withValues(alpha: 0.6),
          ),
          child: const SizedBox.expand(),
        );
    final resolvedDecoration =
        decoration ??
        BoxDecoration(
          color: colorScheme.surface.withValues(alpha: 0.97),
          borderRadius: BorderRadius.circular(24.r),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.42),
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.24),
              blurRadius: 20.r,
              offset: Offset(0, 12.h),
            ),
          ],
        );
    final resolvedContentDecoration =
        contentDecoration ??
        BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.58),
          borderRadius: BorderRadius.circular(18.r),
        );

    return OverlayWindow(
      header: resolvedOverlayBar,
      onBackdropTap: onBackdropTap ?? controls?.minimize,
      footer: resolvedBottomBar,
      margin: margin,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      backdrop: resolvedBackdrop,
      decoration: resolvedDecoration,
      contentDecoration: resolvedContentDecoration,
      padding: padding ?? EdgeInsets.all(20.r),
      contentPadding: contentPadding ?? EdgeInsets.all(16.r),
      child: resolvedBody,
    );
  }
}

class OverlayWindowConfig {
  const OverlayWindowConfig({
    required this.sceneId,
    required this.bubbleSize,
    required this.notificationTitle,
    required this.notificationContent,
  });

  final int sceneId;
  final double bubbleSize;
  final OverlaySceneTextBuilder notificationTitle;
  final OverlaySceneTextBuilder notificationContent;
}

class OverlayWindowBar extends StatelessWidget {
  const OverlayWindowBar({
    super.key,
    this.leading,
    this.leadingWidth,
    this.title,
    this.subtitle,
    this.actions = const <Widget>[],
    this.padding,
    this.decoration,
    this.titleSpacing,
    this.actionSpacing,
    this.showMinimizeAction = false,
    this.showCloseAction = false,
    this.onMinimize,
    this.onClose,
  });

  final Widget? leading;
  final double? leadingWidth;
  final Widget? title;
  final Widget? subtitle;
  final List<Widget> actions;
  final EdgeInsetsGeometry? padding;
  final Decoration? decoration;
  final double? titleSpacing;
  final double? actionSpacing;
  final bool showMinimizeAction;
  final bool showCloseAction;
  final VoidCallback? onMinimize;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final controls = OverlayWindowPanelScope.maybeOf(context);
    final resolvedLeadingWidth = leadingWidth ?? 48.w;
    final resolvedTitleSpacing = titleSpacing ?? 12.w;
    final resolvedActionSpacing = actionSpacing ?? 8.w;
    final resolvedPadding =
        padding ?? EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h);
    final resolvedDecoration =
        decoration ??
        BoxDecoration(
          color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(18.r),
        );
    final content = (title == null && subtitle == null)
        ? const SizedBox.shrink()
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (title != null)
                DefaultTextStyle(
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 17.sp,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  child: title!,
                ),
              if (subtitle != null) ...<Widget>[
                if (title != null) SizedBox(height: 4.h),
                DefaultTextStyle(
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  child: subtitle!,
                ),
              ],
            ],
          );
    final builtInActions = <Widget>[
      if (showMinimizeAction)
        OverlayWindowHeaderButton(
          icon: Icons.remove_rounded,
          onPressed: onMinimize ?? controls?.minimize ?? () {},
        ),
      if (showCloseAction)
        OverlayWindowHeaderButton(
          icon: Icons.close_rounded,
          onPressed: onClose ?? controls?.close ?? () {},
        ),
    ];
    final resolvedActions = <Widget>[...actions, ...builtInActions];

    if (leading == null &&
        title == null &&
        subtitle == null &&
        resolvedActions.isEmpty) {
      return const SizedBox.shrink();
    }

    return DecoratedBox(
      decoration: resolvedDecoration,
      child: Padding(
        padding: resolvedPadding,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            if (leading != null) ...<Widget>[
              ConstrainedBox(
                constraints: BoxConstraints.tightFor(width: resolvedLeadingWidth),
                child: Align(alignment: Alignment.centerLeft, child: leading),
              ),
              SizedBox(width: resolvedTitleSpacing),
            ],
            Expanded(child: content),
            if (resolvedActions.isNotEmpty) ...<Widget>[
              SizedBox(width: resolvedTitleSpacing),
              Wrap(
                spacing: resolvedActionSpacing,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: resolvedActions,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

@Deprecated('Use OverlayWindowBar instead.')
class OverlayWindowHeader extends OverlayWindowBar {
  const OverlayWindowHeader({
    super.key,
    super.leading,
    super.leadingWidth,
    super.title,
    super.subtitle,
    super.actions = const <Widget>[],
    super.padding,
    super.decoration,
    super.titleSpacing,
    super.actionSpacing,
    super.showMinimizeAction = false,
    super.showCloseAction = false,
    super.onMinimize,
    super.onClose,
  });
}

class OverlayWindowHeaderButton extends StatelessWidget {
  const OverlayWindowHeaderButton({
    super.key,
    required this.icon,
    required this.onPressed,
  });

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;

    return Material(
      color: colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(12.r),
        onTap: onPressed,
        child: SizedBox(
          width: 40.w,
          height: 40.w,
          child: Icon(icon, size: 20.sp, color: colorScheme.onSurface),
        ),
      ),
    );
  }
}
