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

    return Material(
      color: Colors.black.withValues(alpha: 0.32),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onClose,
        child: Center(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: Material(
              color: context.colorScheme.surface,
              borderRadius: BorderRadius.circular(16.r),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: 220.r, maxWidth: 280.r),
                child: Padding(
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
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
