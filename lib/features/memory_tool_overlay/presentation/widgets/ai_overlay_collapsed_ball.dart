import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/core/themes/ai_activation_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class AiOverlayCollapsedBall extends StatelessWidget {
  const AiOverlayCollapsedBall({
    required this.onTap,
    this.isHighlighted = false,
    super.key,
  });

  static const Key highlightRingKey = ValueKey<String>(
    'ai_overlay_collapsed_ball_highlight_ring',
  );
  static const Key innerBallKey = ValueKey<String>(
    'ai_overlay_collapsed_ball_inner',
  );

  final VoidCallback onTap;
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(14.r);
    final innerRadius = BorderRadius.circular(12.r);
    final innerBall = Container(
      key: innerBallKey,
      decoration: BoxDecoration(
        gradient: RadialGradient(
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
        borderRadius: innerRadius,
        border: Border.all(
          color: context.colorScheme.onPrimary.withValues(alpha: 0.22),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: context.colorScheme.primary.withValues(alpha: 0.18),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: context.colorScheme.primary.withValues(alpha: 0.32),
            blurRadius: 14,
            spreadRadius: 1.2,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: innerRadius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: innerRadius,
          onTap: onTap,
          child: Center(
            child: Icon(
              Icons.auto_awesome_rounded,
              size: 20.r,
              color: context.colorScheme.onPrimary,
            ),
          ),
        ),
      ),
    );

    if (!isHighlighted) {
      return innerBall;
    }

    return Container(
      key: highlightRingKey,
      decoration: BoxDecoration(
        gradient: aiActivationGradient,
        borderRadius: borderRadius,
        boxShadow: buildAiActivationGlowShadows(compact: true),
      ),
      padding: EdgeInsets.all(2.w),
      child: innerBall,
    );
  }
}
