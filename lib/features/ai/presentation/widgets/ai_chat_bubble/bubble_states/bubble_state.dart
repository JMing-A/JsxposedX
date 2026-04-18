import 'package:flutter/foundation.dart';

@immutable
class BubbleState {
  final String content;
  final String role;
  final bool isError;
  final VoidCallback? onRetry;
  final bool isToolCalling;
  final String? packageName;
  final String? retryLabel;
  final String? loadingHint;

  const BubbleState({
    required this.content,
    required this.role,
    required this.isError,
    required this.onRetry,
    required this.isToolCalling,
    required this.packageName,
    this.retryLabel,
    this.loadingHint,
  });

  bool get isUser => role == 'user';

  bool get isLoading => !isUser && content.isEmpty && !isError && !isToolCalling;

  bool get isToolResult {
    return !isUser && (content.startsWith('✅') || content.startsWith('❌'));
  }
}
