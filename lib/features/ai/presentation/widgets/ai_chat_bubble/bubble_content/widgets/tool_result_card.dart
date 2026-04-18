import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class ToolResultCard extends HookWidget {
  final String content;

  const ToolResultCard({super.key, required this.content});

  @override
  Widget build(BuildContext context) {
    final expanded = useState(false);
    final isSuccess = content.startsWith('✅');
    final lines = content.split('\n');
    final summary = lines.first;
    final detail = lines.length > 1 ? lines.skip(1).join('\n').trim() : '';
    final color = isSuccess ? const Color(0xFF4CAF50) : const Color(0xFFF44336);
    final bgColor = isSuccess
        ? (context.isDark ? const Color(0xFF1B2E1B) : const Color(0xFFF1F8F1))
        : (context.isDark ? const Color(0xFF2E1B1B) : const Color(0xFFFFF1F1));

    return Container(
      margin: EdgeInsets.only(bottom: 20.h),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: detail.isNotEmpty ? () => expanded.value = !expanded.value : null,
            borderRadius: BorderRadius.circular(12.r),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
              child: Row(
                children: [
                  Icon(
                    isSuccess ? Icons.check_circle_outline : Icons.error_outline,
                    color: color,
                    size: 16.sp,
                  ),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: Text(
                      summary,
                      style: TextStyle(
                        fontSize: 12.5.sp,
                        color: color,
                        fontFamily: 'monospace',
                      ),
                      maxLines: expanded.value ? null : 2,
                      overflow: expanded.value ? null : TextOverflow.ellipsis,
                    ),
                  ),
                  if (detail.isNotEmpty) ...[
                    SizedBox(width: 4.w),
                    Icon(
                      expanded.value ? Icons.expand_less : Icons.expand_more,
                      size: 16.sp,
                      color: color.withValues(alpha: 0.7),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (expanded.value && detail.isNotEmpty)
            Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(12.w, 0, 12.w, 10.h),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: color.withValues(alpha: 0.15)),
                ),
              ),
              child: Text(
                detail,
                style: TextStyle(
                  fontSize: 11.5.sp,
                  color: context.isDark
                      ? Colors.white.withValues(alpha: 0.7)
                      : Colors.black54,
                  fontFamily: 'monospace',
                  height: 1.5,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
