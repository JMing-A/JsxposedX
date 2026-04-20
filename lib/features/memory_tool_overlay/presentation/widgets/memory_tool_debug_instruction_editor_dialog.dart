import 'dart:async';

import 'package:JsxposedX/common/widgets/custom_text_field.dart';
import 'package:JsxposedX/common/widgets/overlay_window/overlay_panel_dialog.dart';
import 'package:JsxposedX/common/widgets/overlay_window/overlay_text_input_context_menu.dart';
import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/core/models/ai_message.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_thinking_markup.dart';
import 'package:JsxposedX/features/ai/presentation/providers/config/ai_config_query_provider.dart';
import 'package:JsxposedX/features/ai/presentation/providers/runtime/ai_chat_runtime_provider.dart';
import 'package:JsxposedX/features/ai/presentation/widgets/ai_chat_bubble/ai_chat_bubble.dart';
import 'package:JsxposedX/features/ai/presentation/widgets/ai_chat_bubble/bubble_container.dart';
import 'package:JsxposedX/features/ai/presentation/widgets/ai_chat_bubble/bubble_content/bubble_content.dart';
import 'package:JsxposedX/features/ai/presentation/widgets/ai_chat_bubble/bubble_content/widgets/ai_code_element_builder.dart';
import 'package:JsxposedX/features/ai/presentation/widgets/ai_chat_bubble/bubble_states/bubble_state.dart';
import 'package:JsxposedX/features/ai/presentation/widgets/ai_chat_bubble/bubble_toolbar/bubble_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:uuid/uuid.dart';

class MemoryToolDebugInstructionEditorDialog extends HookConsumerWidget {
  const MemoryToolDebugInstructionEditorDialog({
    super.key,
    required this.initialValue,
    required this.onSave,
    required this.onClose,
  });

  final String initialValue;
  final Future<String?> Function(String value) onSave;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = useTextEditingController(text: initialValue);
    useEffect(() {
      controller
        ..text = initialValue
        ..selection = TextSelection.collapsed(offset: initialValue.length);
      return null;
    }, [controller, initialValue]);
    useListenable(controller);
    final isSaving = useState(false);
    final errorText = useState<String?>(null);
    final rawValue = controller.text;
    final normalizedValue = rawValue.trim();
    final normalizedInitialValue = initialValue.trim();
    final lineCount = '\n'.allMatches(rawValue).length + 1;
    final visibleMaxLines = lineCount.clamp(1, 4);
    final pseudocodePreviewValue = useState<String?>(null);
    final canSave =
        !isSaving.value &&
        normalizedValue.isNotEmpty &&
        normalizedValue != normalizedInitialValue;
    final canPreview = !isSaving.value && normalizedValue.isNotEmpty;

    useEffect(() {
      errorText.value = null;
      return null;
    }, [rawValue]);

    return Stack(
      children: <Widget>[
        OverlayPanelDialog.card(
          onClose: onClose,
          maxWidthPortrait: 420.r,
          maxWidthLandscape: 520.r,
          maxHeightPortrait: 252.r,
          maxHeightLandscape: 252.r,
          cardBorderRadius: 18.r,
          childBuilder: (context, viewport, layout) {
            return SingleChildScrollView(
              padding: EdgeInsets.all(14.r),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    context.isZh ? '编辑指令' : 'Edit Instruction',
                    style: context.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 12.r),
                  CustomTextField(
                    controller: controller,
                    labelText: context.isZh ? '指令' : 'Instruction',
                    contextMenuBuilder: buildOverlayTextInputContextMenu,
                    maxLines: visibleMaxLines,
                    fillColor: context.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.22),
                    focusedBorderColor: context.colorScheme.primary,
                    enabledBorderColor: context.colorScheme.outlineVariant
                        .withValues(alpha: 0.34),
                  ),
                  if (errorText.value case final message?) ...<Widget>[
                    SizedBox(height: 8.r),
                    Text(
                      message,
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
                          onPressed: onClose,
                          child: Text(context.l10n.close),
                        ),
                      ),
                      SizedBox(width: 10.r),
                      Expanded(
                        child: FilledButton.tonal(
                          onPressed: canPreview
                              ? () {
                                  pseudocodePreviewValue.value = rawValue.trim();
                                }
                              : null,
                          child: Text(
                            context.isZh ? '解析' : 'Parse',
                          ),
                        ),
                      ),
                      SizedBox(width: 10.r),
                      Expanded(
                        child: FilledButton(
                          onPressed: canSave
                              ? () async {
                                  isSaving.value = true;
                                  try {
                                    errorText.value = await onSave(rawValue);
                                  } finally {
                                    if (context.mounted) {
                                      isSaving.value = false;
                                    }
                                  }
                                }
                              : null,
                          child: isSaving.value
                              ? SizedBox(
                                  width: 16.r,
                                  height: 16.r,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: context.colorScheme.onPrimary,
                                  ),
                                )
                              : Text(context.l10n.save),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
        if (pseudocodePreviewValue.value case final instructionText?)
          Positioned.fill(
            child: _MemoryToolInstructionPseudocodeDialog(
              instructionText: instructionText,
              onClose: () {
                pseudocodePreviewValue.value = null;
              },
            ),
          ),
      ],
    );
  }
}

class _MemoryToolInstructionPseudocodeDialog extends HookConsumerWidget {
  const _MemoryToolInstructionPseudocodeDialog({
    required this.instructionText,
    required this.onClose,
  });

  final String instructionText;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestSeed = useState(0);
    final isLoading = useState(true);
    final errorText = useState<String?>(null);
    final responseText = useState('');

    useEffect(() {
      var disposed = false;
      StreamSubscription<AiMessage>? subscription;

      Future<void> startRequest() async {
        isLoading.value = true;
        errorText.value = null;
        responseText.value = '';
        try {
          final config = await ref.read(aiConfigProvider.future);
          if (config.apiUrl.isEmpty) {
            throw StateError(context.l10n.aiNotActivated);
          }

          final systemPrompt = context.isZh
              ? '你是一个逆向分析助手。你的目标是让人看懂，而不是机械逐条翻译。'
                  '请使用中文 Markdown 输出，并善用标题、列表、加粗、引用和代码块来解释汇编语义。'
                  '伪代码部分必须使用 C++ 风格代码块。'
              : 'You are a reverse engineering assistant. Your goal is readability, not literal line-by-line translation. '
                  'Reply in clear English Markdown and use headings, lists, emphasis, quotes, and code blocks when helpful. '
                  'The pseudocode section must use a C++-style fenced code block.';
          final userPromptPrefix = context.isZh
              ? '把下面的汇编指令转换成更容易理解的说明型 Markdown。\n'
                  '输出结构：\n'
                  '## 作用概览\n'
                  '用 1 到 3 句话说明这段汇编大概在做什么。\n'
                  '## 执行流程\n'
                  '用条目按顺序解释关键步骤。\n'
                  '## 伪代码\n'
                  '使用 ```cpp 代码块输出 C++ 风格伪代码。\n'
                  '## 关键寄存器或内存\n'
                  '列出关键寄存器、内存写入或关键条件。\n'
                  '## 不确定项\n'
                  '列出你不确定的架构细节、寄存器语义或推断点。\n'
                  '规则：\n'
                  '- 以“人能看懂”为第一目标。\n'
                  '- 保持原始执行顺序。\n'
                  '- 保留分支、跳转、比较、写内存等控制流语义。\n'
                  '- 可以合并重复的机械细节，但不要丢掉关键逻辑。\n'
                  '- 如果语义不确定，必须明确写在“不确定项”里。\n'
                  '汇编：\n'
              : 'Convert the following assembly instructions into explanation-first Markdown.\n'
                  'Output structure:\n'
                  '## Overview\n'
                  'Explain in 1-3 sentences what this code is doing.\n'
                  '## Execution Flow\n'
                  'Describe the important steps in order.\n'
                  '## Pseudocode\n'
                  'Use a ```cpp fenced block with C++-style pseudocode.\n'
                  '## Key Registers or Memory\n'
                  'List important registers, memory writes, and conditions.\n'
                  '## Uncertainties\n'
                  'List uncertain architecture details or semantic guesses.\n'
                  'Rules:\n'
                  '- Prioritize human readability.\n'
                  '- Keep the original execution order.\n'
                  '- Preserve branch, jump, compare, memory write, and other control-flow semantics.\n'
                  '- You may merge repetitive mechanical details, but do not lose core logic.\n'
                  '- If anything is uncertain, state it explicitly in the Uncertainties section.\n'
                  'Assembly:\n';

          final messages = <AiMessage>[
            AiMessage(
              id: const Uuid().v4(),
              role: 'system',
              content: systemPrompt,
            ),
            AiMessage(
              id: const Uuid().v4(),
              role: 'user',
              content: '$userPromptPrefix$instructionText',
            ),
          ];

          final stream = ref.read(aiChatRuntimeRepositoryProvider).getChatStream(
            config: config,
            messages: messages,
          );

          subscription = stream.listen(
            (chunk) {
              if (disposed || chunk.content.isEmpty) {
                return;
              }
              responseText.value = '${responseText.value}${chunk.content}';
            },
            onError: (Object error, StackTrace _) {
              if (disposed) {
                return;
              }
              errorText.value = error
                  .toString()
                  .replaceFirst('Exception: ', '')
                  .trim();
              isLoading.value = false;
            },
            onDone: () {
              if (disposed) {
                return;
              }
              isLoading.value = false;
            },
            cancelOnError: true,
          );
        } catch (error) {
          if (disposed) {
            return;
          }
          errorText.value = error.toString().replaceFirst('Exception: ', '').trim();
          isLoading.value = false;
        }
      }

      unawaited(startRequest());
      return () {
        disposed = true;
        if (subscription != null) {
          unawaited(subscription!.cancel());
        }
      };
    }, [instructionText, requestSeed.value]);

    final hasContent = responseText.value.trim().isNotEmpty;

    return OverlayPanelDialog.card(
      onClose: onClose,
      maxWidthPortrait: 460.r,
      maxWidthLandscape: 560.r,
      maxHeightPortrait: 560.r,
      maxHeightLandscape: 460.r,
      cardBorderRadius: 18.r,
      childBuilder: (context, viewport, layout) {
        return Padding(
          padding: EdgeInsets.all(14.r),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                context.isZh ? '伪代码预览' : 'Pseudocode Preview',
                style: context.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 12.r),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: context.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(14.r),
                    border: Border.all(
                      color: context.colorScheme.outlineVariant.withValues(
                        alpha: 0.34,
                      ),
                    ),
                  ),
                  child: Builder(
                    builder: (context) {
                      if (!hasContent &&
                          !isLoading.value &&
                          errorText.value == null) {
                        return Center(
                          child: Padding(
                            padding: EdgeInsets.all(16.r),
                            child: Text(
                              context.isZh
                                  ? '未生成可预览的伪代码'
                                  : 'No pseudocode was generated',
                              textAlign: TextAlign.center,
                              style: context.textTheme.bodyMedium?.copyWith(
                                color: context.colorScheme.onSurface.withValues(
                                  alpha: 0.62,
                                ),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        );
                      }
                      return SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(8.r, 8.r, 8.r, 4.r),
                        child: _MemoryToolPseudocodeBubble(
                          content: errorText.value ?? responseText.value,
                          role: 'assistant',
                          isError: errorText.value != null,
                          onRetry: errorText.value != null
                              ? () {
                                  requestSeed.value += 1;
                                }
                              : null,
                          loadingHint: context.isZh
                              ? '正在转换伪代码...'
                              : 'Converting to pseudocode...',
                        ),
                      );
                    },
                  ),
                ),
              ),
              SizedBox(height: 12.r),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: onClose,
                  child: Text(context.l10n.close),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MemoryToolPseudocodeBubble extends BaseAiChatBubble {
  const _MemoryToolPseudocodeBubble({
    required super.content,
    required super.role,
    super.isError,
    super.onRetry,
    super.loadingHint,
  });

  @override
  BaseBubbleContainerPart createContainerPart() {
    return const _MemoryToolPseudocodeBubbleContainerPart();
  }

  @override
  BaseBubbleContentPart createContentPart() {
    return const _MemoryToolPseudocodeBubbleContentPart();
  }

  @override
  BaseBubbleToolbarPart createToolbarPart() {
    return const _MemoryToolPseudocodeBubbleToolbarPart();
  }
}

class _MemoryToolPseudocodeBubbleContainerPart
    extends DefaultBubbleContainerPart {
  const _MemoryToolPseudocodeBubbleContainerPart();

  @override
  EdgeInsetsGeometry resolveBubbleMargin(BubbleState state) {
    return EdgeInsets.zero;
  }
}

class _MemoryToolPseudocodeBubbleToolbarPart extends BaseBubbleToolbarPart {
  const _MemoryToolPseudocodeBubbleToolbarPart();
}

class _MemoryToolPseudocodeBubbleContentPart extends BaseBubbleContentPart {
  const _MemoryToolPseudocodeBubbleContentPart();

  @override
  MarkdownStyleSheet buildMarkdownTheme(BuildContext context, BubbleState state) {
    return super.buildMarkdownTheme(context, state).copyWith(
      p: TextStyle(
        color: context.isDark
            ? Colors.white.withValues(alpha: 0.9)
            : context.textTheme.bodyLarge?.color,
        fontSize: 14.sp,
        height: 1.55,
      ),
      h2: TextStyle(
        fontSize: 15.sp,
        height: 1.35,
        fontWeight: FontWeight.w800,
        color: context.colorScheme.primary,
      ),
      listBullet: TextStyle(
        color: context.colorScheme.primary,
        fontSize: 13.sp,
      ),
      code: TextStyle(
        fontSize: 12.sp,
        fontFamily: 'monospace',
        backgroundColor: context.isDark
            ? Colors.black26
            : Colors.black.withValues(alpha: 0.05),
        color: context.isDark
            ? context.colorScheme.secondaryContainer
            : Colors.deepOrange,
      ),
    );
  }

  @override
  Widget buildMarkdown(
    BuildContext context,
    BubbleState state, {
    required BaseBubbleToolbarPart toolbarPart,
  }) {
    final parts = AiThinkingMarkup.split(resolveMarkdownData(context, state));
    final markdown = parts.answer.trim().isEmpty ? parts.thinking : parts.answer;
    return GestureDetector(
      onLongPress: () => toolbarPart.showTextActionsSheet(
        context,
        title: context.isZh ? '伪代码预览' : 'Pseudocode Preview',
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
            initialFontSize: 10.sp,
          ),
        },
        shrinkWrap: true,
        fitContent: true,
      ),
    );
  }
}
