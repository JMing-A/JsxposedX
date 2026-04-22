import 'package:JsxposedX/common/pages/toast.dart';
import 'package:JsxposedX/common/widgets/app_bottom_sheet.dart';
import 'package:JsxposedX/common/widgets/overlay_window/overlay_text_input_context_menu.dart';
import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/features/ai/presentation/widgets/ai_chat_bubble/bubble_toolbar/bubble_toolbar.dart';
import 'package:JsxposedX/features/ai/presentation/widgets/ai_chat_compact_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

class MemoryAiBubbleToolbarPart extends BaseBubbleToolbarPart {
  const MemoryAiBubbleToolbarPart();

  @override
  void handleCopyToClipboard(BuildContext context, String text) async {
    final copied = await FlutterOverlayWindow.setClipboardData(text);
    await ToastOverlayMessage.show(
      copied ? context.l10n.codeCopied : context.l10n.error,
    );
  }

  @override
  Future<void> showTextSelectionSheet(
    BuildContext context, {
    required String title,
    required String text,
  }) async {
    final scale = AiChatCompactScope.scaleOf(context);
    await AppBottomSheet.show<void>(
      context: context,
      title: title,
      child: SingleChildScrollView(
        child: SelectableText(
          text,
          contextMenuBuilder: buildOverlayTextInputContextMenu,
          style: TextStyle(
            fontSize: 14 * scale,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}
