import 'dart:math' as math;

import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/core/models/ai_message.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_response_issue.dart';
import 'package:JsxposedX/features/ai/presentation/providers/runtime/ai_chat_runtime_provider.dart';
import 'package:JsxposedX/features/ai/presentation/widgets/ai_chat_bubble/ai_chat_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class AiChatList extends HookConsumerWidget {
  const AiChatList({
    super.key,
    required this.messages,
    required this.scrollController,
    required this.packageName,
    this.systemPrompt,
    this.customTitle,
    this.customSubtitle,
  });

  final List<AiMessage> messages;
  final ScrollController scrollController;
  final String packageName;
  final String? systemPrompt;
  final String? customTitle;
  final String? customSubtitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (messages.isEmpty) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxHeight < 220.h;
          final horizontalPadding = 20.w;
          final topPadding = isCompact ? 10.h : 18.h;
          final bottomPadding = 12.h;
          final bubbleMaxWidth = math.max(
            0.0,
            constraints.maxWidth - (horizontalPadding * 2) - 22.w,
          );

          return SingleChildScrollView(
            controller: scrollController,
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              topPadding,
              horizontalPadding,
              bottomPadding,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: math.max(
                  0,
                  constraints.maxHeight - topPadding - bottomPadding,
                ),
              ),
              child: Align(
                alignment: isCompact ? Alignment.topLeft : Alignment.centerLeft,
                child: _EmptyChatState(
                  title: customTitle ?? context.l10n.aiAssistantTitle,
                  subtitle: customSubtitle ?? context.l10n.aiAssistantSubtitle,
                  maxBubbleWidth: bubbleMaxWidth,
                ),
              ),
            ),
          );
        },
      );
    }

    final chatState = ref.watch(aiChatRuntimeProvider(packageName: packageName));
    final chatNotifier = ref.read(
      aiChatRuntimeProvider(packageName: packageName).notifier,
    );
    final totalVisibleCount = chatState.totalVisibleMessagesCount;
    final hasMore = messages.length < totalVisibleCount;
    final remainingCount = (totalVisibleCount - messages.length).clamp(0, totalVisibleCount);
    final reversedMessages = messages.reversed.toList(growable: false);
    final retryLabel = chatState.lastResponseIssue == AiResponseIssue.partialResponse
        ? (chatState.sessionContext.hasPendingToolPhase
              ? context.l10n.aiResumeToolPhase
              : context.l10n.aiContinue)
        : context.l10n.retry;

    return ListView.builder(
      controller: scrollController,
      reverse: true,
      padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 10.h),
      itemCount: reversedMessages.length + (hasMore ? 1 : 0),
      cacheExtent: 500,
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      itemBuilder: (context, index) {
        if (index == reversedMessages.length) {
          return Padding(
            padding: EdgeInsets.symmetric(vertical: 8.h),
            child: TextButton(
              onPressed: chatNotifier.loadMore,
              child: Text(
                context.l10n.aiShowMoreMessages(remainingCount),
                style: TextStyle(color: context.colorScheme.primary),
              ),
            ),
          );
        }

        final message = reversedMessages[index];
        final shouldShowStreaming =
            index == 0 &&
            chatState.isStreaming &&
            message.role == 'assistant' &&
            !message.isError;

        if (shouldShowStreaming) {
          return _StreamingAiChatBubble(
            key: ValueKey(message.id),
            role: message.role,
            isError: message.isError,
            isToolCalling: message.isToolResultBubble,
            retryLabel: retryLabel,
            streamingContentStream: chatNotifier.streamingContentStream,
            streamingThinkingStream: chatNotifier.streamingThinkingStream,
            onRetry: () => chatNotifier.retryByMessageId(message.id),
            packageName: packageName,
          );
        }

        return RepaintBoundary(
          child: AiChatBubble(
            key: ValueKey(message.id),
            content: message.content,
            role: message.role,
            isError: message.isError,
            isToolCalling:
                message.isToolResultBubble &&
                !message.content.startsWith('✅') &&
                !message.content.startsWith('❌'),
            retryLabel: retryLabel,
            onRetry: () => chatNotifier.retryByMessageId(message.id),
            packageName: packageName,
          ),
        );
      },
    );
  }
}

class _EmptyChatState extends StatelessWidget {
  const _EmptyChatState({
    required this.title,
    required this.subtitle,
    required this.maxBubbleWidth,
  });

  final String title;
  final String subtitle;
  final double maxBubbleWidth;

  @override
  Widget build(BuildContext context) {
    final promptHints = context.isZh
        ? const [
            '描述一下你现在想解决的问题',
            '把现象或报错直接贴给我',
            '让我先帮你拆排查步骤',
          ]
        : const [
            'Describe what you want to solve',
            'Paste the symptom or error directly',
            'Ask me to break down the next steps',
          ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 28.w,
              height: 28.w,
              decoration: BoxDecoration(
                color: context.colorScheme.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.auto_awesome_rounded,
                size: 16.sp,
                color: context.colorScheme.primary,
              ),
            ),
            SizedBox(width: 8.w),
            Text(
              context.isZh ? '助手' : 'Assistant',
              style: TextStyle(
                fontSize: 12.sp,
                fontWeight: FontWeight.w700,
                color: context.colorScheme.onSurface,
              ),
            ),
          ],
        ),
        SizedBox(height: 10.h),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxBubbleWidth),
          child: Container(
            padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 14.h),
            decoration: BoxDecoration(
              color: context.isDark
                  ? context.colorScheme.surfaceContainer
                  : Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20.r),
                topRight: Radius.circular(20.r),
                bottomLeft: Radius.circular(6.r),
                bottomRight: Radius.circular(20.r),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 12.r,
                  offset: Offset(0, 4.h),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w700,
                    color: context.colorScheme.onSurface,
                  ),
                ),
                SizedBox(height: 6.h),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12.5.sp,
                    height: 1.45,
                    color: context.colorScheme.onSurfaceVariant,
                  ),
                ),
                SizedBox(height: 10.h),
                Text(
                  context.isZh
                      ? '直接输入目标、现象或假设，我会按当前环境继续对话。'
                      : 'Describe your goal, symptom, or hypothesis and I will continue from the current environment.',
                  style: TextStyle(
                    fontSize: 12.5.sp,
                    height: 1.5,
                    color: context.colorScheme.onSurface.withValues(alpha: 0.86),
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: 12.h),
        Wrap(
          spacing: 8.w,
          runSpacing: 8.h,
          children: [
            for (final hint in promptHints) _EmptyPromptChip(label: hint),
          ],
        ),
      ],
    );
  }
}

class _EmptyPromptChip extends StatelessWidget {
  const _EmptyPromptChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 7.h),
      decoration: BoxDecoration(
        color: context.colorScheme.surfaceContainerHighest.withValues(
          alpha: context.isDark ? 0.4 : 0.72,
        ),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(
          color: context.colorScheme.outlineVariant.withValues(alpha: 0.72),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5.sp,
          height: 1.35,
          color: context.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _StreamingAiChatBubble extends HookWidget {
  const _StreamingAiChatBubble({
    super.key,
    required this.role,
    required this.isError,
    required this.isToolCalling,
    required this.retryLabel,
    required this.streamingContentStream,
    required this.streamingThinkingStream,
    this.onRetry,
    this.packageName,
  });

  final String role;
  final bool isError;
  final bool isToolCalling;
  final String retryLabel;
  final Stream<String> streamingContentStream;
  final Stream<bool> streamingThinkingStream;
  final VoidCallback? onRetry;
  final String? packageName;

  @override
  Widget build(BuildContext context) {
    final content = useState('');
    final lastUpdateTime = useState<DateTime?>(null);
    final isThinking = useState(false);

    useEffect(() {
      final subscription = streamingContentStream.listen((data) {
        if (!context.mounted) {
          return;
        }

        final now = DateTime.now();
        final lastUpdate = lastUpdateTime.value;
        if (data.isEmpty ||
            lastUpdate == null ||
            now.difference(lastUpdate).inMilliseconds >= 50) {
          lastUpdateTime.value = now;
          if (data != content.value) {
            content.value = data;
          }
        }
      });

      return subscription.cancel;
    }, [streamingContentStream]);

    useEffect(() {
      final subscription = streamingThinkingStream.listen((value) {
        if (!context.mounted) {
          return;
        }
        isThinking.value = value;
      });

      return subscription.cancel;
    }, [streamingThinkingStream]);

    return RepaintBoundary(
      child: AiChatBubble(
        content: content.value,
        role: role,
        isError: isError,
        isToolCalling: isToolCalling,
        retryLabel: retryLabel,
        onRetry: onRetry,
        packageName: packageName,
        loadingHint: isThinking.value
            ? (context.isZh ? 'AI 正在深度思考...' : 'AI is thinking deeply...')
            : null,
      ),
    );
  }
}
