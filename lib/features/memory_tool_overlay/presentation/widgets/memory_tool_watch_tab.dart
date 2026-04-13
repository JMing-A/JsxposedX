import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/widgets/memory_tool_overlay_l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class MemoryToolWatchTab extends StatelessWidget {
  const MemoryToolWatchTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.all(12.r),
      children: <Widget>[
        _WatchCard(
          title: context.l10n.memoryToolWatchTabTitle,
          subtitle: context.l10n.memoryToolWatchTabSubtitle,
          rows: <_WatchRowData>[
            _WatchRowData('HP', '100.0', 'Float'),
            _WatchRowData('Coins', '289', 'Dword'),
            _WatchRowData('Speed', '1.000', 'Double'),
          ],
        ),
      ],
    );
  }
}

class _WatchCard extends StatelessWidget {
  const _WatchCard({
    required this.title,
    required this.subtitle,
    required this.rows,
  });

  final String title;
  final String subtitle;
  final List<_WatchRowData> rows;

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
            for (final row in rows) ...<Widget>[
              _WatchRow(row: row),
              SizedBox(height: 8.r),
            ],
          ],
        ),
      ),
    );
  }
}

class _WatchRowData {
  const _WatchRowData(this.label, this.value, this.type);

  final String label;
  final String value;
  final String type;
}

class _WatchRow extends StatelessWidget {
  const _WatchRow({required this.row});

  final _WatchRowData row;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colorScheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14.r),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12.r, vertical: 12.r),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                row.label,
                style: context.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              row.value,
              style: context.textTheme.titleSmall?.copyWith(
                color: context.colorScheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(width: 10.r),
            Text(
              row.type,
              style: context.textTheme.labelLarge?.copyWith(
                color: context.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
