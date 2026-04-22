import 'package:JsxposedX/common/pages/toast.dart';
import 'package:JsxposedX/common/widgets/app_bottom_sheet.dart';
import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/features/ai/presentation/widgets/ai_chat_compact_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:JsxposedX/features/ai/presentation/widgets/ai_chat_bubble/bubble_states/bubble_state.dart';
import 'package:JsxposedX/features/ai/presentation/widgets/ai_chat_bubble/bubble_toolbar/widgets/code_save_action.dart';

abstract class BaseBubbleToolbarPart {
  const BaseBubbleToolbarPart();

  void handleCopyToClipboard(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ToastMessage.show(context.l10n.codeCopied);
  }

  Future<void> showTextActionsSheet(
    BuildContext context, {
    required String title,
    required String text,
  }) async {
    final normalized = text.trim();
    if (normalized.isEmpty) {
      return;
    }

    await AppBottomSheet.show<void>(
      context: context,
      title: context.l10n.aiBubbleActionsTitle,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _BubbleActionTile(
            icon: Icons.copy_all_rounded,
            title: context.l10n.aiBubbleCopyCurrent,
            onTap: () {
              Navigator.of(context).pop();
              handleCopyToClipboard(context, normalized);
            },
          ),
          _BubbleActionTile(
            icon: Icons.text_fields_rounded,
            title: context.l10n.aiBubbleSelectText,
            onTap: () {
              Navigator.of(context).pop();
              showTextSelectionSheet(
                context,
                title: title,
                text: normalized,
              );
            },
          ),
        ],
      ),
    );
  }

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
          style: TextStyle(
            fontSize: 14 * scale,
            height: 1.5,
          ),
        ),
      ),
    );
  }

  List<Widget> buildCodeActions({
    required BubbleState state,
    required String language,
    required String code,
  }) {
    return const [];
  }
}

class DefaultBubbleToolbarPart extends BaseBubbleToolbarPart {
  const DefaultBubbleToolbarPart();

  @override
  List<Widget> buildCodeActions({
    required BubbleState state,
    required String language,
    required String code,
  }) {
    return [
      CodeSaveAction(
        code: code,
        packageName: state.packageName,
        language: language,
      ),
      const SizedBox(width: 4),
    ];
  }
}

class _BubbleActionTile extends StatelessWidget {
  const _BubbleActionTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scale = AiChatCompactScope.scaleOf(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, size: 20 * scale),
      title: Text(
        title,
        style: TextStyle(fontSize: 14 * scale),
      ),
      onTap: onTap,
    );
  }
}
