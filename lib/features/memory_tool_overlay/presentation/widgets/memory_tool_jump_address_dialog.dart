import 'package:JsxposedX/common/widgets/custom_text_field.dart';
import 'package:JsxposedX/common/widgets/overlay_window/overlay_text_input_context_menu.dart';
import 'package:JsxposedX/common/widgets/overlay_window/overlay_panel_dialog.dart';
import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class MemoryToolJumpAddressDialog extends HookWidget {
  const MemoryToolJumpAddressDialog({
    super.key,
    required this.onConfirm,
    required this.onClose,
  });

  final Future<void> Function(int targetAddress) onConfirm;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final addressController = useTextEditingController();
    final isHex = useState(true);
    final isSubmitting = useState(false);
    useListenable(addressController);

    final rawInput = addressController.text.trim();
    final resolvedAddress = _tryParseJumpAddress(rawInput, isHex: isHex.value);
    final errorText = rawInput.isEmpty || resolvedAddress != null
        ? null
        : context.l10n.memoryToolJumpAddressInvalid;
    final canConfirm = !isSubmitting.value && resolvedAddress != null;

    return OverlayPanelDialog.card(
      onClose: isSubmitting.value ? null : onClose,
      maxWidthPortrait: 360.r,
      maxWidthLandscape: 400.r,
      maxHeightPortrait: 280.r,
      maxHeightLandscape: 280.r,
      cardBorderRadius: 18.r,
      childBuilder: (context, viewport, layout) {
        return SingleChildScrollView(
          padding: EdgeInsets.all(14.r),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                context.l10n.memoryToolJumpAddressTitle,
                style: context.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 12.r),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: CustomTextField(
                      controller: addressController,
                      keyboardType: TextInputType.visiblePassword,
                      labelText: context.l10n.memoryToolJumpAddressFieldLabel,
                      contextMenuBuilder: buildOverlayTextInputContextMenu,
                      fillColor: context.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.22),
                      focusedBorderColor: context.colorScheme.primary,
                      enabledBorderColor: context.colorScheme.outlineVariant
                          .withValues(alpha: 0.34),
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.allow(
                          isHex.value
                              ? RegExp(r'[0-9a-fA-FxX]')
                              : RegExp(r'\d'),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 10.r),
                  SizedBox(
                    height: 56.r,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12.r),
                        onTap: isSubmitting.value
                            ? null
                            : () {
                                isHex.value = !isHex.value;
                              },
                        child: Ink(
                          padding: EdgeInsets.symmetric(horizontal: 14.r),
                          decoration: BoxDecoration(
                            color: context.colorScheme.surfaceContainerHighest
                                .withValues(alpha: isHex.value ? 0.56 : 0.32),
                            borderRadius: BorderRadius.circular(12.r),
                            border: Border.all(
                              color: isHex.value
                                  ? context.colorScheme.primary
                                  : context.colorScheme.outlineVariant
                                        .withValues(alpha: 0.34),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(
                                isHex.value
                                    ? Icons.check_box_rounded
                                    : Icons.check_box_outline_blank_rounded,
                                size: 18.r,
                                color: isHex.value
                                    ? context.colorScheme.primary
                                    : context.colorScheme.onSurfaceVariant
                                          .withValues(alpha: 0.72),
                              ),
                              SizedBox(width: 8.r),
                              Text(
                                context.l10n.memoryToolOffsetPreviewHexLabel,
                                style: context.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (errorText != null) ...<Widget>[
                SizedBox(height: 8.r),
                Text(
                  errorText,
                  style: context.textTheme.bodySmall?.copyWith(
                    color: context.colorScheme.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              SizedBox(height: 14.r),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: isSubmitting.value ? null : onClose,
                      child: Text(context.l10n.close),
                    ),
                  ),
                  SizedBox(width: 10.r),
                  Expanded(
                    child: FilledButton(
                      onPressed: canConfirm
                          ? () async {
                              isSubmitting.value = true;
                              try {
                                await onConfirm(resolvedAddress!);
                              } finally {
                                if (context.mounted) {
                                  isSubmitting.value = false;
                                }
                              }
                            }
                          : null,
                      child: Text(context.l10n.confirm),
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

int? _tryParseJumpAddress(String input, {required bool isHex}) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    return null;
  }

  if (isHex) {
    final normalized = trimmed.replaceFirst(
      RegExp(r'^0x', caseSensitive: false),
      '',
    );
    if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(normalized)) {
      return null;
    }
    return int.tryParse(normalized, radix: 16);
  }

  if (!RegExp(r'^\d+$').hasMatch(trimmed)) {
    return null;
  }
  return int.tryParse(trimmed);
}
