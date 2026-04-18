import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'dart:async';

class DotLoadingIndicator extends HookWidget {
  const DotLoadingIndicator({
    super.key,
    this.statusText,
  });

  final String? statusText;

  @override
  Widget build(BuildContext context) {
    final animationController = useAnimationController(
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    final startedAt = useMemoized(DateTime.now);
    final elapsedSeconds = useState(0);

    useEffect(() {
      final timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!context.mounted) {
          return;
        }
        elapsedSeconds.value = DateTime.now().difference(startedAt).inSeconds;
      });
      return timer.cancel;
    }, [startedAt]);

    final waitingSeconds = elapsedSeconds.value;
    final defaultStatusText = switch (waitingSeconds) {
      >= 12 => context.isZh ? 'AI 正在思考，已等待 ${waitingSeconds}s' : 'Thinking... ${waitingSeconds}s',
      >= 4 => context.isZh ? 'AI 正在思考中...' : 'Thinking...',
      _ => null,
    };
    final effectiveStatusText = statusText ?? defaultStatusText;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            return AnimatedBuilder(
              animation: animationController,
              builder: (context, child) {
                final delay = index * 0.2;
                var value = (animationController.value - delay) % 1.0;
                if (value < 0) {
                  value = 0;
                }

                final opacity = value < 0.5 ? value * 2 : 1.0 - (value - 0.5) * 2;
                final translation =
                    (value < 0.5 ? value * 2 : 1.0 - (value - 0.5) * 2) * -4;

                return Opacity(
                  opacity: opacity.clamp(0.4, 1.0),
                  child: Transform.translate(
                    offset: Offset(0, translation),
                    child: Container(
                      width: 6.w,
                      height: 6.w,
                      margin: EdgeInsets.symmetric(horizontal: 2.w),
                      decoration: BoxDecoration(
                        color: context.isDark ? Colors.white70 : Colors.grey[400],
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                );
              },
            );
          }),
        ),
        if (effectiveStatusText != null) ...[
          SizedBox(height: 8.h),
          Text(
            effectiveStatusText,
            style: TextStyle(
              fontSize: 12.sp,
              color: context.isDark ? Colors.white60 : Colors.black54,
              height: 1.3,
            ),
          ),
        ],
      ],
    );
  }
}
