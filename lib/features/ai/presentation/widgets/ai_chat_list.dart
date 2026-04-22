import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/core/models/ai_message.dart';
import 'package:JsxposedX/core/utils/url_helper.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_response_issue.dart';
import 'package:JsxposedX/features/ai/presentation/providers/runtime/ai_chat_runtime_provider.dart';
import 'package:JsxposedX/features/ai/presentation/widgets/ai_chat_bubble/ai_chat_bubble.dart';
import 'package:JsxposedX/features/ai/presentation/widgets/ai_chat_compact_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

typedef AiChatBubbleBuilder = Widget Function({
  required AiMessage message,
  required String retryLabel,
  required VoidCallback onRetry,
  required String packageName,
});

typedef AiChatStreamingBubbleBuilder = Widget Function({
  required AiMessage message,
  required String retryLabel,
  required VoidCallback onRetry,
  required String packageName,
  required Stream<String> streamingContentStream,
  required Stream<bool> streamingThinkingStream,
});

class AiChatList extends HookConsumerWidget {
  const AiChatList({
    super.key,
    required this.messages,
    required this.scrollController,
    required this.packageName,
    this.isCompact = false,
    this.systemPrompt,
    this.customTitle,
    this.customSubtitle,
    this.bubbleBuilder,
    this.streamingBubbleBuilder,
  });

  final List<AiMessage> messages;
  final ScrollController scrollController;
  final String packageName;
  final bool isCompact;
  final String? systemPrompt;
  final String? customTitle;
  final String? customSubtitle;
  final AiChatBubbleBuilder? bubbleBuilder;
  final AiChatStreamingBubbleBuilder? streamingBubbleBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scopeCompact = AiChatCompactScope.of(context);
    final scopeScale = AiChatCompactScope.scaleOf(context);
    final effectiveCompact = isCompact || scopeCompact;
    if (messages.isEmpty) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final isCompactLayout =
              effectiveCompact || constraints.maxHeight < (220 * scopeScale);
          final horizontalPadding =
              (effectiveCompact ? 12 : 20) * scopeScale;
          final topPadding = (isCompactLayout ? 10 : 18) * scopeScale;
          final bottomPadding = 12 * scopeScale;
          final minHeight = constraints.maxHeight - topPadding - bottomPadding;

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
                minHeight: minHeight > 0 ? minHeight : 0,
              ),
              child: Align(
                alignment: isCompactLayout
                    ? Alignment.topLeft
                    : Alignment.centerLeft,
                child: _EmptyChatState(isCompact: isCompactLayout),
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
    final remainingCount = (totalVisibleCount - messages.length).clamp(
      0,
      totalVisibleCount,
    );
    final reversedMessages = messages.reversed.toList(growable: false);
    final retryLabel =
        chatState.lastResponseIssue == AiResponseIssue.partialResponse
        ? (chatState.sessionContext.hasPendingToolPhase
              ? context.l10n.aiResumeToolPhase
              : context.l10n.aiContinue)
        : context.l10n.retry;

    return ListView.builder(
      controller: scrollController,
      reverse: true,
      padding: EdgeInsets.symmetric(
        horizontal: (effectiveCompact ? 12 : 20) * scopeScale,
        vertical: (effectiveCompact ? 6 : 10) * scopeScale,
      ),
      itemCount: reversedMessages.length + (hasMore ? 1 : 0),
      cacheExtent: 500,
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      itemBuilder: (context, index) {
        if (index == reversedMessages.length) {
          return Padding(
            padding: EdgeInsets.symmetric(vertical: 8 * scopeScale),
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
            !message.isError &&
            !message.isToolResultBubble;

        if (shouldShowStreaming) {
          if (streamingBubbleBuilder != null) {
            return RepaintBoundary(
              child: streamingBubbleBuilder!(
                message: message,
                retryLabel: retryLabel,
                onRetry: () => chatNotifier.retryByMessageId(message.id),
                packageName: packageName,
                streamingContentStream: chatNotifier.streamingContentStream,
                streamingThinkingStream: chatNotifier.streamingThinkingStream,
              ),
            );
          }
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
          child: bubbleBuilder != null
              ? bubbleBuilder!(
                  message: message,
                  retryLabel: retryLabel,
                  onRetry: () => chatNotifier.retryByMessageId(message.id),
                  packageName: packageName,
                )
              : AiChatBubble(
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
    required this.isCompact,
  });

  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final scopeScale = AiChatCompactScope.scaleOf(context);
    final lines = context.isZh
        ? const [
            '欢迎使用',
          ]
        : const [
            'Welcome',
          ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: (isCompact ? 24 : 28) * scopeScale,
              height: (isCompact ? 24 : 28) * scopeScale,
              decoration: BoxDecoration(
                color: context.colorScheme.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.auto_awesome_rounded,
                size: (isCompact ? 14 : 16) * scopeScale,
                color: context.colorScheme.primary,
              ),
            ),
            SizedBox(width: 8 * scopeScale),
            Text(
              context.isZh ? '助手' : 'Assistant',
              style: TextStyle(
                fontSize: (isCompact ? 11 : 12) * scopeScale,
                fontWeight: FontWeight.w700,
                color: context.colorScheme.onSurface,
              ),
            ),
          ],
        ),
        SizedBox(height: (isCompact ? 8 : 10) * scopeScale),
        Container(
          constraints: BoxConstraints(
            maxWidth: (isCompact ? 240 : 320) * scopeScale,
          ),
          padding: EdgeInsets.fromLTRB(
            (isCompact ? 12 : 16) * scopeScale,
            (isCompact ? 10 : 14) * scopeScale,
            (isCompact ? 12 : 16) * scopeScale,
            (isCompact ? 10 : 14) * scopeScale,
          ),
          decoration: BoxDecoration(
            color: context.isDark
                ? context.colorScheme.surfaceContainer
                : Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20 * scopeScale),
              topRight: Radius.circular(20 * scopeScale),
              bottomLeft: Radius.circular(6 * scopeScale),
              bottomRight: Radius.circular(20 * scopeScale),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 12 * scopeScale,
                offset: Offset(0, 4 * scopeScale),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var index = 0; index < lines.length; index++) ...[
                if (index > 0) SizedBox(height: (isCompact ? 6 : 8) * scopeScale),
                Text(
                  lines[index],
                  style: TextStyle(
                    fontSize: (isCompact ? 13 : 15) * scopeScale,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                    color: context.colorScheme.onSurface,
                  ),
                ),
              ],
              SizedBox(height: (isCompact ? 10 : 12) * scopeScale),
              OutlinedButton(
                onPressed: () {
                  UrlHelper.openUrlInBrowser(
                    url: 'https://api.muxueai.pro',
                  );
                },
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.symmetric(
                    horizontal: (isCompact ? 10 : 12) * scopeScale,
                    vertical: (isCompact ? 8 : 10) * scopeScale,
                  ),
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  side: BorderSide(
                    color: context.colorScheme.primary.withValues(alpha: 0.35),
                  ),
                  foregroundColor: context.colorScheme.primary,
                  textStyle: TextStyle(
                    fontSize: (isCompact ? 11 : 12) * scopeScale,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Text('官方满血GPT接口'),
              ),
            ],
          ),
        ),
      ],
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
