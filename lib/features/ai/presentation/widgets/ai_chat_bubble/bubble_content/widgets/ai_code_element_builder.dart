import 'package:JsxposedX/common/widgets/app_code_editor/app_code_editor.dart';
import 'package:JsxposedX/features/ai/presentation/widgets/ai_list_card.dart';
import 'package:JsxposedX/features/ai/presentation/widgets/ai_method_card.dart';
import 'package:JsxposedX/features/ai/presentation/widgets/ai_permission_card.dart';
import 'package:JsxposedX/features/ai/presentation/widgets/ai_steps_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:re_editor/re_editor.dart';

import '../../bubble_states/bubble_state.dart';
import '../../bubble_toolbar/bubble_toolbar.dart';

class AiCodeElementBuilder extends MarkdownElementBuilder {
  final BubbleState state;
  final BaseBubbleToolbarPart toolbarPart;

  AiCodeElementBuilder({required this.state, required this.toolbarPart});

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final language =
        element.attributes['class']?.replaceFirst('language-', '') ?? '';
    final codeContent = element.textContent.trim();

    if (!element.textContent.contains('\n') && language.isEmpty) {
      return null;
    }

    if (language == 'list') {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 4.h),
        child: AiListCard(rawContent: codeContent),
      );
    }

    if (language == 'method') {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 4.h),
        child: AiMethodCard(rawContent: codeContent),
      );
    }

    if (language == 'steps') {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 4.h),
        child: AiStepsCard(rawContent: codeContent),
      );
    }

    if (language == 'permissions') {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 4.h),
        child: AiPermissionCard(rawContent: codeContent),
      );
    }

    final controller = CodeLineEditingController.fromText(codeContent);
    final extraActions = toolbarPart.buildCodeActions(
      state: state,
      language: language,
      code: codeContent,
    );

    if (language == 'javascript' || language == 'js') {
      return AppCodeEditor(
        controller: controller,
        language: language,
        readOnly: true,
        initialFontSize: 13.sp,
        extraActions: extraActions,
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: 400.h, minHeight: 0),
      child: AppCodeEditor(
        controller: controller,
        language: language,
        readOnly: true,
        initialFontSize: 13.sp,
        extraActions: extraActions,
      ),
    );
  }
}
