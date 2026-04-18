import 'package:JsxposedX/common/widgets/overlay_window/overlay_panel_dialog.dart';
import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class MemoryToolResultSelectionDialog extends HookWidget {
  const MemoryToolResultSelectionDialog({
    super.key,
    required this.initialLimit,
    required this.onClose,
    required this.onConfirm,
  });

  final int initialLimit;
  final VoidCallback onClose;
  final ValueChanged<int> onConfirm;

  @override
  Widget build(BuildContext context) {
    final controller = useTextEditingController(text: initialLimit.toString());

    return OverlayPanelDialog.card(
      onClose: onClose,
      barrierOpacity: 0.32,
      maxWidthPortrait: 280.r,
      maxWidthLandscape: 280.r,
      maxHeightPortrait: 220.r,
      maxHeightLandscape: 220.r,
      landscapeHeightFactor: 1.0,
      cardMinWidth: 220.r,
      cardMaxWidth: 280.r,
      cardBorderRadius: 16.r,
      childBuilder: (context, viewport, layout) {
        return Padding(
          padding: EdgeInsets.all(12.r),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: initialLimit.toString(),
                  filled: true,
                  fillColor: context.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.42),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.r),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12.r,
                    vertical: 12.r,
                  ),
                ),
              ),
              SizedBox(height: 10.r),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onClose,
                      child: Text(context.l10n.cancel),
                    ),
                  ),
                  SizedBox(width: 10.r),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        final parsed = int.tryParse(controller.text.trim());
                        if (parsed == null || parsed <= 0) {
                          return;
                        }
                        onConfirm(parsed);
                      },
                      child: Text(context.l10n.save),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
