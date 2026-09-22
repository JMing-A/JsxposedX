import 'package:JsxposedX/features/ai/domain/models/ai_system_models.dart';
import 'package:JsxposedX/features/ai/domain/services/ai_multimodal_message_codec.dart';

abstract interface class AiTokenEstimator {
  int estimate(AiMessage message);
}

class ConservativeAiTokenEstimator implements AiTokenEstimator {
  const ConservativeAiTokenEstimator();

  @override
  int estimate(AiMessage message) {
    var characters = 0;
    for (final part in message.parts) {
      characters += switch (part) {
        AiTextPart(:final text) => _textCost(text),
        AiReasoningPart(:final text) => text.length,
        AiImagePart() => 1024,
        AiToolCallPart(:final toolCall) =>
          toolCall.name.length + toolCall.arguments.toString().length,
        AiToolResultPart(:final toolResult) =>
          toolResult.name.length + toolResult.content.length,
      };
    }
    return 12 + (characters / 3).ceil();
  }

  static int _textCost(String text) {
    final parsed = AiMultimodalMessageCodec.parse(text);
    if (parsed == null) return text.length;
    // Base64 image data is transport bytes, not proportional text tokens.
    // Count a bounded image placeholder plus the editable caption instead.
    final imageCost = parsed.attachments
        .where((attachment) => attachment.isImage)
        .fold<int>(0, (total, _) => total + 1024);
    return parsed.text.length + imageCost;
  }
}

class AiChatContextBuilder {
  static const int _fallbackContextTokens = 8192;
  // Input tokens also include serialized tool schemas, protocol wrappers and
  // provider metadata. Keep this headroom outside the message estimator.
  static const int _protocolOverheadTokens = 2048;

  const AiChatContextBuilder({
    AiTokenEstimator tokenEstimator = const ConservativeAiTokenEstimator(),
  }) : _tokenEstimator = tokenEstimator;

  final AiTokenEstimator _tokenEstimator;

  List<AiMessage> build({
    required AiAssistantProfile assistant,
    required AiModelDefinition model,
    required List<AiMessage> messages,
    required String Function() idFactory,
    required DateTime now,
    String? environmentSystemPrompt,
  }) {
    final completedMessages = messages
        .where((message) => message.status == AiMessageStatus.completed)
        .toList(growable: false);
    // Tool results are part of the Responses protocol state. They cannot be
    // treated as optional context: removing them leaves function calls without
    // outputs and the provider rejects the next request.
    final eligible = completedMessages
        .where((message) => message.parts.isNotEmpty)
        .toList(growable: false);

    final profilePrompt = assistant.systemPrompt?.trim();
    final environmentPrompt = environmentSystemPrompt?.trim();
    final systemPrompt = [
      if (environmentPrompt != null && environmentPrompt.isNotEmpty)
        environmentPrompt,
      if (profilePrompt != null && profilePrompt.isNotEmpty) profilePrompt,
    ].join('\n\n');
    final systemPromptTokens = systemPrompt.isEmpty
        ? 0
        : _tokenEstimator.estimate(
            AiMessage(
              id: 'system-budget',
              conversationId: messages.firstOrNull?.conversationId ?? '',
              role: AiMessageRole.system,
              parts: [AiContentPart.text(systemPrompt)],
              createdAt: now,
            ),
          );
    final contextTokens = model.limits.contextTokens ?? _fallbackContextTokens;
    final selected = switch (assistant.contextPolicy.mode) {
      AiContextMode.fullHistory => eligible,
      AiContextMode.recentMessages => _recentMessages(
        eligible,
        assistant.contextPolicy.recentMessageLimit,
      ),
      AiContextMode.tokenBudget => _withinTokenBudget(
        eligible,
        assistant.contextPolicy,
        contextTokens,
        systemPromptTokens: systemPromptTokens,
      ),
    };

    final boundedSelected =
        assistant.contextPolicy.mode == AiContextMode.tokenBudget
        ? selected
        : _withinTokenBudget(
            selected,
            assistant.contextPolicy,
            contextTokens,
            systemPromptTokens: systemPromptTokens,
          );
    // 修复工具调用配对可能重新带回被预算截断的历史消息；修复后必须
    // 再次执行预算裁剪，避免“配对合法但请求超出上下文上限”。
    final pairedSelected = _repairToolCallPairs(
      boundedSelected,
      eligible,
    );
    final protocolSafeSelected = _withinTokenBudget(
      pairedSelected,
      assistant.contextPolicy,
      contextTokens,
      systemPromptTokens: systemPromptTokens,
    );
    if (systemPrompt.isEmpty) return protocolSafeSelected;
    return [
      AiMessage(
        id: idFactory(),
        conversationId: messages.firstOrNull?.conversationId ?? '',
        role: model.capabilities.systemRole
            ? AiMessageRole.system
            : AiMessageRole.user,
        parts: [AiContentPart.text(systemPrompt)],
        createdAt: now,
      ),
      ...protocolSafeSelected,
    ];
  }

  /// Responses requires every function_call_output to have its preceding
  /// function_call in the same input history. Context trimming is allowed to
  /// remove old turns, but never one half of a tool exchange.
  static List<AiMessage> _repairToolCallPairs(
    List<AiMessage> selected,
    List<AiMessage> source,
  ) {
    final callIds = {
      for (final message in source)
        for (final part in message.parts.whereType<AiToolCallPart>())
          part.toolCall.id,
    };
    final resultIds = {
      for (final message in source)
        for (final part in message.parts.whereType<AiToolResultPart>())
          part.toolResult.toolCallId,
    };
    final pairedIds = callIds.intersection(resultIds);
    final normalized = <String, AiMessage>{
      for (final message in source)
        message.id: message.copyWith(
          parts: message.parts
              .where(
                (part) =>
                    part is! AiToolCallPart && part is! AiToolResultPart ||
                    part is AiToolCallPart &&
                        pairedIds.contains(part.toolCall.id) ||
                    part is AiToolResultPart &&
                        pairedIds.contains(part.toolResult.toolCallId),
              )
              .toList(growable: false),
        ),
    };
    final selectedIds = selected.map((message) => message.id).toSet();
    var changed = true;
    while (changed) {
      changed = false;
      final selectedCalls = {
        for (final id in selectedIds)
          for (final part in normalized[id]!.parts.whereType<AiToolCallPart>())
            part.toolCall.id,
        for (final id in selectedIds)
          for (final part
              in normalized[id]!.parts.whereType<AiToolResultPart>())
            part.toolResult.toolCallId,
      };
      for (final message in normalized.values) {
        final related = message.parts.any(
          (part) =>
              part is AiToolCallPart &&
                  selectedCalls.contains(part.toolCall.id) ||
              part is AiToolResultPart &&
                  selectedCalls.contains(part.toolResult.toolCallId),
        );
        if (related && selectedIds.add(message.id)) changed = true;
      }
    }
    return source
        .where((message) => selectedIds.contains(message.id))
        .map((message) => normalized[message.id]!)
        .where((message) => message.parts.isNotEmpty)
        .toList(growable: false);
  }

  static List<AiMessage> _recentMessages(
    List<AiMessage> messages,
    int? configuredLimit,
  ) {
    if (messages.isEmpty) return messages;
    if (configuredLimit == null || configuredLimit <= 0) return messages;
    final limit = configuredLimit.clamp(1, messages.length);
    return messages.sublist(messages.length - limit);
  }

  List<AiMessage> _withinTokenBudget(
    List<AiMessage> messages,
    AiContextPolicy policy,
    int contextTokens, {
    int systemPromptTokens = 0,
  }) {
    if (contextTokens <= 0) return messages;
    final budget =
        (contextTokens -
                policy.reservedOutputTokens -
                systemPromptTokens -
                _protocolOverheadTokens)
            .clamp(1, contextTokens);
    final selected = <AiMessage>[];
    var used = 0;
    for (final message in messages.reversed) {
      final estimated = _tokenEstimator.estimate(message);
      // 上下文硬预算优先于“至少保留 N 条消息”。否则一条超大的
      // 工具结果或代码消息会让最终请求必然超过模型上下文限制。
      if (used > 0 && used + estimated > budget) break;
      selected.add(message);
      used += estimated;
    }
    return selected.reversed.toList(growable: false);
  }
}
