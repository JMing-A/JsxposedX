import 'package:JsxposedX/features/ai/presentation/widgets/ai_chat_bubble/bubble_states/bubble_state.dart';

class MemoryAiBubbleState extends BubbleState {
  const MemoryAiBubbleState({
    required super.content,
    required super.role,
    required super.isError,
    required super.onRetry,
    required super.isToolCalling,
    required super.packageName,
    required this.isToolResultBubble,
    super.retryLabel,
    super.loadingHint,
  });

  final bool isToolResultBubble;

  @override
  bool get isToolResult => isToolResultBubble || super.isToolResult;

  bool get isSystem => role == 'system';
}
