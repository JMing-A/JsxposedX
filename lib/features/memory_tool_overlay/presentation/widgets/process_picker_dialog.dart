import 'package:JsxposedX/common/widgets/loading.dart';
import 'package:JsxposedX/common/widgets/overlay_window/overlay_panel_dialog.dart';
import 'package:JsxposedX/common/widgets/ref_error.dart';
import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/providers/memory_query_provider.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/widgets/process_info_tile.dart';
import 'package:JsxposedX/generated/memory_tool.g.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class MemoryToolProcessPickerDialog extends HookConsumerWidget {
  const MemoryToolProcessPickerDialog({
    super.key,
    required this.onClose,
    required this.onSelected,
    required this.onRetry,
  });

  final VoidCallback onClose;
  final ValueChanged<ProcessInfo> onSelected;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final processListAsync = ref.watch(
      getProcessInfoProvider(offset: 0, limit: 20),
    );

    return OverlayPanelDialog.scaledCard(
      onClose: onClose,
      maxWidthPortrait: 360.0,
      maxWidthLandscape: 520.0,
      maxHeightPortrait: 560.0,
      maxHeightLandscape: 280.0,
      portraitBaseSize: const Size(340, 420),
      landscapeBaseSize: const Size(520, 236),
      fillCardHeight: true,
      scaledCardBorderRadiusBuilder: (scaledLayout) =>
          18.0 * scaledLayout.scale,
      childBuilder: (context, viewport, scaledLayout) {
        final isLandscapeDialog = viewport.isLandscape;
        final contentScale = scaledLayout.scale;
        final titleFontSize =
            (isLandscapeDialog ? 16.0 : 18.0) * contentScale;
        final actionFontSize =
            (isLandscapeDialog ? 10.0 : 12.0) * contentScale;
        final headerHorizontalPadding =
            (isLandscapeDialog ? 12.0 : 16.0) * contentScale;
        final headerVerticalPadding =
            (isLandscapeDialog ? 8.0 : 12.0) * contentScale;
        final listPadding =
            (isLandscapeDialog ? 6.0 : 10.0) * contentScale;
        final separatorHeight =
            (isLandscapeDialog ? 4.0 : 8.0) * contentScale;
        final tileScale = isLandscapeDialog
            ? (0.92 * contentScale).clamp(0.64, 0.94).toDouble()
            : (0.94 * contentScale).clamp(0.56, 1.0).toDouble();

        return Column(
          children: <Widget>[
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: headerHorizontalPadding,
                vertical: headerVerticalPadding,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      context.l10n.selectApp,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: titleFontSize,
                        fontWeight: FontWeight.w700,
                        height: 1.0,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: onClose,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.symmetric(
                        horizontal: 6.0 * contentScale,
                        vertical: 2.0 * contentScale,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: Text(
                      context.l10n.close,
                      style: TextStyle(fontSize: actionFontSize),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(listPadding),
                child: processListAsync.when(
                  data: (processes) {
                    if (processes.isEmpty) {
                      return Center(
                        child: Text(
                          context.l10n.noData,
                          style: TextStyle(
                            color: context.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
                          ),
                        ),
                      );
                    }

                    return ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: processes.length,
                      separatorBuilder: (_, _) =>
                          SizedBox(height: separatorHeight),
                      itemBuilder: (context, index) {
                        return ProcessInfoTile(
                          process: processes[index],
                          scale: tileScale,
                          onTap: () => onSelected(processes[index]),
                        );
                      },
                    );
                  },
                  error: (error, stack) => RefError(onRetry: onRetry),
                  loading: () => const Loading(),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
