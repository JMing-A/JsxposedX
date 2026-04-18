import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class MemoryToolResultSelectionBar extends StatelessWidget {
  const MemoryToolResultSelectionBar({
    super.key,
    required this.actions,
  });

  final List<MemoryToolResultSelectionActionData> actions;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) {
      return const SizedBox.shrink();
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colorScheme.surface.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(
          color: context.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 8.r, vertical: 6.r),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: context.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.42,
              ),
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 4.r, vertical: 2.r),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (int index = 0; index < actions.length; index++) ...<Widget>[
                    if (index > 0) const _MemoryToolResultSelectionDivider(),
                    _MemoryToolResultSelectionAction(data: actions[index]),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MemoryToolResultSelectionActionData {
  const MemoryToolResultSelectionActionData({
    required this.icon,
    this.onTap,
  });

  final IconData icon;
  final VoidCallback? onTap;
}

class _MemoryToolResultSelectionDivider extends StatelessWidget {
  const _MemoryToolResultSelectionDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 18.r,
      margin: EdgeInsets.symmetric(horizontal: 2.r),
      color: context.colorScheme.outlineVariant.withValues(alpha: 0.52),
    );
  }
}

class _MemoryToolResultSelectionAction extends StatelessWidget {
  const _MemoryToolResultSelectionAction({required this.data});

  final MemoryToolResultSelectionActionData data;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8.r),
      onTap: data.onTap,
      child: SizedBox(
        width: 28.r,
        height: 28.r,
        child: Center(
          child: Icon(
            data.icon,
            size: 18.r,
            color: context.colorScheme.onSurface.withValues(
              alpha: data.onTap == null ? 0.3 : 0.76,
            ),
          ),
        ),
      ),
    );
  }
}
