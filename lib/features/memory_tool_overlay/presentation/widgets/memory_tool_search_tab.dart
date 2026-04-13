import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/widgets/memory_tool_overlay_l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class MemoryToolSearchTab extends StatelessWidget {
  const MemoryToolSearchTab({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;

    return ListView(
      padding: EdgeInsets.all(12.r),
      children: <Widget>[
        _SectionCard(
          title: context.l10n.memoryToolSearchTabTitle,
          subtitle: context.l10n.memoryToolSearchTabSubtitle,
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: _FieldBox(
                      label: context.l10n.memoryToolFieldValue,
                      value: context.l10n.memoryToolFieldValuePlaceholder,
                    ),
                  ),
                  SizedBox(width: 10.r),
                  Expanded(
                    child: _FieldBox(
                      label: context.l10n.memoryToolFieldType,
                      value: context.l10n.memoryToolFieldTypePlaceholder,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 10.r),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _FieldBox(
                      label: context.l10n.memoryToolFieldScope,
                      value: context.l10n.memoryToolFieldScopePlaceholder,
                    ),
                  ),
                  SizedBox(width: 10.r),
                  Expanded(
                    child: _FieldBox(
                      label: context.l10n.memoryToolSearchModeLabel,
                      value: context.l10n.memoryToolSearchExact,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(height: 12.r),
        _SectionCard(
          title: context.l10n.memoryToolActionPanelTitle,
          subtitle: context.l10n.memoryToolActionPanelSubtitle,
          child: Wrap(
            spacing: 10.r,
            runSpacing: 10.r,
            children: <Widget>[
              _ActionChip(
                label: context.l10n.memoryToolActionFirstScan,
                color: colorScheme.primary,
              ),
              _ActionChip(
                label: context.l10n.memoryToolActionNextScan,
                color: colorScheme.secondary,
              ),
              _ActionChip(
                label: context.l10n.memoryToolActionRead,
                color: colorScheme.tertiary,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

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
            child,
          ],
        ),
      ),
    );
  }
}

class _FieldBox extends StatelessWidget {
  const _FieldBox({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colorScheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14.r),
      ),
      child: Padding(
        padding: EdgeInsets.all(12.r),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              label,
              style: context.textTheme.labelMedium?.copyWith(
                color: context.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            SizedBox(height: 6.r),
            Text(
              value,
              style: context.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14.r),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12.r, vertical: 10.r),
        child: Text(
          label,
          style: context.textTheme.labelLarge?.copyWith(
            color: color,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
