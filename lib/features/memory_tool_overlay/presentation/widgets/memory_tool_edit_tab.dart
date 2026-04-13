import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/widgets/memory_tool_overlay_l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class MemoryToolEditTab extends StatelessWidget {
  const MemoryToolEditTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.all(12.r),
      children: <Widget>[
        _EditCard(
          title: context.l10n.memoryToolEditTabTitle,
          subtitle: context.l10n.memoryToolEditTabSubtitle,
          items: <String>[
            context.l10n.memoryToolEditActionWriteValue,
            context.l10n.memoryToolEditActionFreezeValue,
            context.l10n.memoryToolEditActionBatchWrite,
          ],
        ),
        SizedBox(height: 12.r),
        _EditCard(
          title: context.l10n.memoryToolPatchTabTitle,
          subtitle: context.l10n.memoryToolPatchTabSubtitle,
          items: <String>[
            context.l10n.memoryToolPatchActionHex,
            context.l10n.memoryToolPatchActionAsm,
            context.l10n.memoryToolPatchActionRestore,
          ],
        ),
      ],
    );
  }
}

class _EditCard extends StatelessWidget {
  const _EditCard({
    required this.title,
    required this.subtitle,
    required this.items,
  });

  final String title;
  final String subtitle;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.42,
        ),
        borderRadius: BorderRadius.circular(18.r),
      ),
      child: Padding(
        padding: EdgeInsets.all(14.r),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: context.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 4.r),
            Text(
              subtitle,
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colorScheme.onSurface.withValues(alpha: 0.66),
              ),
            ),
            SizedBox(height: 12.r),
            for (final item in items) ...<Widget>[
              _BulletRow(label: item),
              SizedBox(height: 8.r),
            ],
          ],
        ),
      ),
    );
  }
}

class _BulletRow extends StatelessWidget {
  const _BulletRow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 8.r,
          height: 8.r,
          decoration: BoxDecoration(
            color: context.colorScheme.primary,
            shape: BoxShape.circle,
          ),
        ),
        SizedBox(width: 10.r),
        Expanded(
          child: Text(
            label,
            style: context.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
