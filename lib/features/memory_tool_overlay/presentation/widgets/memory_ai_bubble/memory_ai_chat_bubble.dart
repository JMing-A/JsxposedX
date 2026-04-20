import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/features/ai/presentation/widgets/ai_chat_bubble/ai_chat_bubble.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/widgets/memory_ai_bubble/memory_ai_bubble_container.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/widgets/memory_ai_bubble/memory_ai_bubble_content.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/widgets/memory_ai_bubble/memory_ai_bubble_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

class MemoryAiChatBubble extends BaseAiChatBubble {
  const MemoryAiChatBubble({
    super.key,
    required super.content,
    required super.role,
    super.isError,
    super.onRetry,
    super.isToolCalling,
    super.packageName,
    super.retryLabel,
    super.loadingHint,
    this.isToolResultBubble = false,
  });

  final bool isToolResultBubble;

  @override
  MemoryAiBubbleState createBubbleState() {
    return MemoryAiBubbleState(
      content: content,
      role: role,
      isError: isError,
      onRetry: onRetry,
      isToolCalling: isToolCalling,
      packageName: packageName,
      retryLabel: retryLabel,
      loadingHint: loadingHint,
      isToolResultBubble: isToolResultBubble,
    );
  }

  @override
  MemoryAiBubbleContainerPart createContainerPart() {
    return const MemoryAiBubbleContainerPart();
  }

  @override
  MemoryAiBubbleContentPart createContentPart() {
    return const MemoryAiBubbleContentPart();
  }
}

class MemoryAiStreamingChatBubble extends HookWidget {
  const MemoryAiStreamingChatBubble({
    super.key,
    required this.role,
    required this.isError,
    required this.isToolCalling,
    required this.isToolResultBubble,
    required this.retryLabel,
    required this.streamingContentStream,
    required this.streamingThinkingStream,
    this.onRetry,
    this.packageName,
  });

  final String role;
  final bool isError;
  final bool isToolCalling;
  final bool isToolResultBubble;
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

    return MemoryAiChatBubble(
      content: content.value,
      role: role,
      isError: isError,
      isToolCalling: isToolCalling,
      isToolResultBubble: isToolResultBubble,
      retryLabel: retryLabel,
      onRetry: onRetry,
      packageName: packageName,
      loadingHint: isThinking.value ? _memoryLoadingHint(context) : null,
    );
  }
}

String _memoryLoadingHint(BuildContext context) {
  return context.isZh
      ? '正在整理当前内存上下文...'
      : 'Analyzing current memory context...';
}
