import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_thinking_markup.dart';
import 'package:JsxposedX/features/ai/domain/services/ai_multimodal_message_codec.dart';
import 'package:JsxposedX/features/ai/presentation/widgets/ai_chat_compact_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import 'package:JsxposedX/features/ai/presentation/widgets/ai_chat_bubble/bubble_states/bubble_state.dart';
import 'package:JsxposedX/features/ai/presentation/widgets/ai_chat_bubble/bubble_toolbar/bubble_toolbar.dart';
import 'package:JsxposedX/features/ai/presentation/widgets/ai_chat_bubble/bubble_content/widgets/ai_code_element_builder.dart';
import 'package:JsxposedX/features/ai/presentation/widgets/ai_chat_bubble/bubble_content/widgets/dot_loading_indicator.dart';
import 'package:JsxposedX/features/ai/presentation/widgets/ai_chat_bubble/bubble_content/widgets/tool_calling_indicator.dart';
import 'package:JsxposedX/features/ai/presentation/widgets/ai_chat_bubble/bubble_content/widgets/tool_result_card.dart';

abstract class BaseBubbleContentPart {
  const BaseBubbleContentPart();

  Widget build(
    BuildContext context,
    BubbleState state, {
    required BaseBubbleToolbarPart toolbarPart,
  }) {
    if (state.isUser && AiMultimodalMessageCodec.isEncoded(state.content)) {
      return buildUserAttachments(
        context,
        state,
        toolbarPart: toolbarPart,
      );
    }
    if (state.isLoading) {
      return buildLoading(context, state);
    }
    if (state.isToolResult) {
      return buildToolResult(context, state);
    }
    if (state.isToolCalling) {
      return buildToolCalling(context, state);
    }
    return buildMarkdown(context, state, toolbarPart: toolbarPart);
  }

  @protected
  Widget buildLoading(BuildContext context, BubbleState state) {
    return DotLoadingIndicator(statusText: state.loadingHint);
  }

  @protected
  Widget buildToolResult(BuildContext context, BubbleState state) {
    return ToolResultCard(content: state.content);
  }

  @protected
  Widget buildToolCalling(BuildContext context, BubbleState state) {
    return ToolCallingIndicator(content: state.content);
  }

  @protected
  Widget buildUserAttachments(
    BuildContext context,
    BubbleState state, {
    required BaseBubbleToolbarPart toolbarPart,
  }) {
    final scale = AiChatCompactScope.scaleOf(context);
    final parsed = AiMultimodalMessageCodec.parse(state.content);
    if (parsed == null) {
      return buildMarkdown(context, state, toolbarPart: toolbarPart);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (parsed.hasText)
          _buildMarkdownBody(
            context,
            state,
            toolbarPart: toolbarPart,
            markdown: parsed.text,
            actionTitle: context.l10n.aiBubbleUserTextTitle,
          ),
        for (final attachment in parsed.attachments) ...[
          if (parsed.hasText || attachment != parsed.attachments.first)
            SizedBox(height: 10 * scale),
          if (attachment.isImage)
            _UserImageAttachmentCard(attachment: attachment)
          else
            _UserFileAttachmentCard(attachment: attachment),
        ],
      ],
    );
  }

  @protected
  Widget buildMarkdown(
    BuildContext context,
    BubbleState state, {
    required BaseBubbleToolbarPart toolbarPart,
  }) {
    final parts = AiThinkingMarkup.split(resolveMarkdownData(context, state));
    if (parts.hasThinking) {
      return _ThinkingMarkdownContent(
        state: state,
        toolbarPart: toolbarPart,
        thinkingContent: parts.thinking,
        answerContent: parts.answer,
        theme: buildMarkdownTheme(context, state),
      );
    }

    return _buildMarkdownBody(
      context,
      state,
      toolbarPart: toolbarPart,
      markdown: parts.answer,
      actionTitle: state.isUser
          ? context.l10n.aiBubbleUserTextTitle
          : context.l10n.aiBubbleAssistantTextTitle,
    );
  }

  @protected
  String resolveMarkdownData(BuildContext context, BubbleState state) {
    if (state.isError && state.content.isEmpty) {
      return context.l10n.aiMessageSendFailed;
    }
    return state.content;
  }

  @protected
  MarkdownStyleSheet buildMarkdownTheme(BuildContext context, BubbleState state) {
    final isCompact = AiChatCompactScope.of(context);
    final scale = AiChatCompactScope.scaleOf(context);
    return MarkdownStyleSheet.fromTheme(context.theme).copyWith(
      p: TextStyle(
        color: state.isUser
            ? Colors.white
            : (context.isDark
                  ? Colors.white.withValues(alpha: 0.9)
                  : context.textTheme.bodyLarge?.color),
        fontSize: (isCompact ? 13 : 15) * scale,
        height: 1.5,
      ),
      code: TextStyle(
        fontSize: (isCompact ? 12 : 14) * scale,
        fontFamily: 'monospace',
        backgroundColor: context.isDark
            ? Colors.black26
            : Colors.black.withValues(alpha: 0.05),
        color: state.isUser
            ? Colors.white
            : (context.isDark
                  ? context.colorScheme.secondaryContainer
                  : Colors.deepOrange),
      ),
      codeblockDecoration: const BoxDecoration(),
      blockquoteDecoration: BoxDecoration(
        color: context.isDark ? Colors.white10 : Colors.grey[200],
        borderRadius: BorderRadius.circular(4),
      ),
      listBullet: TextStyle(
        color: state.isUser ? Colors.white : context.colorScheme.primary,
      ),
    );
  }

  Widget _buildMarkdownBody(
    BuildContext context,
    BubbleState state, {
    required BaseBubbleToolbarPart toolbarPart,
    required String markdown,
    String? actionTitle,
  }) {
    return GestureDetector(
      onLongPress: () => toolbarPart.showTextActionsSheet(
        context,
        title: actionTitle ?? context.l10n.aiBubbleAssistantTextTitle,
        text: markdown,
      ),
      child: MarkdownBody(
        data: markdown,
        styleSheet: buildMarkdownTheme(context, state),
        selectable: false,
        builders: {
          'code': AiCodeElementBuilder(
            state: state,
            toolbarPart: toolbarPart,
            uiScale: AiChatCompactScope.scaleOf(context),
          ),
        },
        shrinkWrap: true,
        fitContent: true,
      ),
    );
  }
}

class DefaultBubbleContentPart extends BaseBubbleContentPart {
  const DefaultBubbleContentPart();
}

class _ThinkingMarkdownContent extends HookWidget {
  const _ThinkingMarkdownContent({
    required this.state,
    required this.toolbarPart,
    required this.thinkingContent,
    required this.answerContent,
    required this.theme,
  });

  final BubbleState state;
  final BaseBubbleToolbarPart toolbarPart;
  final String thinkingContent;
  final String answerContent;
  final MarkdownStyleSheet theme;

  @override
  Widget build(BuildContext context) {
    final isCompact = AiChatCompactScope.of(context);
    final scale = AiChatCompactScope.scaleOf(context);
    final expanded = useState(false);
    final cardColor = context.isDark
        ? Colors.white.withValues(alpha: 0.04)
        : Colors.black.withValues(alpha: 0.035);
    final borderColor = context.colorScheme.primary.withValues(alpha: 0.18);
    final title = context.isZh ? '思考过程' : 'Thinking';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: double.infinity,
          margin: EdgeInsets.only(
            bottom: answerContent.isNotEmpty ? 10 * scale : 0,
          ),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(
              (isCompact ? 10 : 12) * scale,
            ),
            border: Border.all(color: borderColor),
          ),
          child: InkWell(
            onTap: () => expanded.value = !expanded.value,
            borderRadius: BorderRadius.circular(
              (isCompact ? 10 : 12) * scale,
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: (isCompact ? 10 : 12) * scale,
                vertical: (isCompact ? 8 : 10) * scale,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.psychology_alt_outlined,
                        size: (isCompact ? 14 : 16) * scale,
                        color: context.colorScheme.primary,
                      ),
                      SizedBox(width: 8 * scale),
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize:
                                (isCompact ? 11 : 12.5) * scale,
                            fontWeight: FontWeight.w600,
                            color: context.colorScheme.primary,
                          ),
                        ),
                      ),
                      Icon(
                        expanded.value ? Icons.expand_less : Icons.expand_more,
                        size: (isCompact ? 14 : 16) * scale,
                        color: context.colorScheme.primary,
                      ),
                    ],
                  ),
                  if (expanded.value) ...[
                    SizedBox(
                      height: (isCompact ? 8 : 10) * scale,
                    ),
                    GestureDetector(
                      onLongPress: () => toolbarPart.showTextActionsSheet(
                        context,
                        title: context.l10n.aiBubbleThinkingTitle,
                        text: thinkingContent,
                      ),
                      child: MarkdownBody(
                        data: thinkingContent,
                        styleSheet: theme,
                        selectable: false,
                        builders: {
                          'code': AiCodeElementBuilder(
                            state: state,
                            toolbarPart: toolbarPart,
                            uiScale: scale,
                          ),
                        },
                        shrinkWrap: true,
                        fitContent: true,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (answerContent.isNotEmpty)
          GestureDetector(
            onLongPress: () => toolbarPart.showTextActionsSheet(
              context,
              title: context.l10n.aiBubbleAnswerTitle,
              text: answerContent,
            ),
            child: MarkdownBody(
              data: answerContent,
              styleSheet: theme,
              selectable: false,
              builders: {
                'code': AiCodeElementBuilder(
                  state: state,
                  toolbarPart: toolbarPart,
                  uiScale: scale,
                ),
              },
              shrinkWrap: true,
              fitContent: true,
            ),
          )
        else if (!state.isError) ...[
          SizedBox(height: 8 * scale),
          DotLoadingIndicator(
            statusText: context.isZh ? 'AI 正在深度思考...' : 'AI is thinking deeply...',
          ),
        ],
      ],
    );
  }
}

class _UserImageAttachmentCard extends StatelessWidget {
  const _UserImageAttachmentCard({
    required this.attachment,
  });

  final AiMultimodalAttachmentData attachment;

  @override
  Widget build(BuildContext context) {
    final isCompact = AiChatCompactScope.of(context);
    final scale = AiChatCompactScope.scaleOf(context);
    final bytes = attachment.imageBytes;
    if (bytes == null) {
      return _UserFileAttachmentCard(attachment: attachment);
    }

    return Container(
      constraints: BoxConstraints(
        maxWidth: (isCompact ? 220.0 : 300.0) * scale,
      ),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14 * scale),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.18),
        ),
      ),
      child: Stack(
        alignment: Alignment.bottomLeft,
        children: [
          Image.memory(
            bytes,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) {
              return AspectRatio(
                aspectRatio: 1.2,
                child: ColoredBox(
                  color: Colors.white.withValues(alpha: 0.10),
                  child: Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white.withValues(alpha: 0.90),
                      size: 28 * scale,
                    ),
                  ),
                ),
              );
            },
          ),
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(
              horizontal: 12 * scale,
              vertical: 10 * scale,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.64),
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  attachment.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12.5 * scale,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 2 * scale),
                Text(
                  attachment.formattedSize,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.86),
                    fontSize: 11 * scale,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UserFileAttachmentCard extends StatelessWidget {
  const _UserFileAttachmentCard({
    required this.attachment,
  });

  final AiMultimodalAttachmentData attachment;

  @override
  Widget build(BuildContext context) {
    final isCompact = AiChatCompactScope.of(context);
    final scale = AiChatCompactScope.scaleOf(context);
    final preview = (attachment.textContent ?? '').trim();
    final excerpt = preview.length <= 180
        ? preview
        : '${preview.substring(0, 180)}...';

    return Container(
      constraints: BoxConstraints(
        maxWidth: (isCompact ? 228.0 : 320.0) * scale,
      ),
      padding: EdgeInsets.all(12 * scale),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14 * scale),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.16),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36 * scale,
            height: 36 * scale,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10 * scale),
            ),
            child: Icon(
              Icons.description_outlined,
              color: Colors.white,
              size: 18 * scale,
            ),
          ),
          SizedBox(width: 10 * scale),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  attachment.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12.5 * scale,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 2 * scale),
                Text(
                  '${attachment.mimeType} · ${attachment.formattedSize}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: 11 * scale,
                  ),
                ),
                if (excerpt.isNotEmpty) ...[
                  SizedBox(height: 8 * scale),
                  Text(
                    excerpt,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontSize: 11.5 * scale,
                      height: 1.45,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
