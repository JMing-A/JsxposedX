import 'package:flutter/foundation.dart';

import 'package:JsxposedX/features/ai/presentation/states/ai_tool_invocation_view.dart';

@immutable
class BubbleState {
  final String content;
  final String role;
  final bool isError;
  final VoidCallback? onRetry;
  final String? packageName;
  final String? retryLabel;
  final String? loadingHint;
  final bool streaming;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onRegenerate;
  final String? rawDetails;
  final List<AiToolInvocationView> toolInvocations;
  final VoidCallback? onToolApprove;
  final VoidCallback? onToolReject;

  /// 非侵入式错误提示：气泡内容正常展示时，流式中断/失败的补充说明。
  /// 非空时不影响 isError（红边框、重试按钮）等既有样式。
  final String? errorHint;

  const BubbleState({
    required this.content,
    required this.role,
    required this.isError,
    required this.onRetry,
    required this.packageName,
    this.retryLabel,
    this.loadingHint,
    this.streaming = false,
    this.onEdit,
    this.onDelete,
    this.onRegenerate,
    this.rawDetails,
    this.toolInvocations = const <AiToolInvocationView>[],
    this.onToolApprove,
    this.onToolReject,
    this.errorHint,
  });

  bool get isUser => role == 'user';

  bool get isLoading =>
      !isUser &&
      content.isEmpty &&
      !isError &&
      toolInvocations.isEmpty;

  bool get isToolResult {
    return !isUser &&
        (toolInvocations.isNotEmpty ||
            content.startsWith('✅') ||
            content.startsWith('❌'));
  }
}
