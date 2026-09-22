import 'dart:convert';

import 'package:JsxposedX/features/ai/application/chat/ai_chat_session_state.dart';
import 'package:JsxposedX/features/ai/application/chat/ai_stream_snapshot.dart';
import 'package:JsxposedX/features/ai/application/chat/ai_transport_trace.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_system_models.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_thinking_markup.dart';
import 'package:JsxposedX/features/ai/presentation/states/ai_chat_view_message.dart';
import 'package:JsxposedX/features/ai/presentation/states/ai_tool_invocation_view.dart';

class AiChatViewMessageMapper {
  const AiChatViewMessageMapper();

  List<AiChatViewMessage> mapHistory(
    List<AiMessage> messages, {
    AiChatSessionPhase phase = AiChatSessionPhase.ready,
  }) {
    final isAwaitingApproval = phase == AiChatSessionPhase.awaitingToolApproval;
    final display = <AiChatViewMessage>[];
    final pendingCalls = <String, _PendingToolCall>{};
    final pendingOrder = <String>[];

    void flushPending() {
      for (final id in pendingOrder) {
        final pending = pendingCalls[id];
        if (pending == null) continue;
        final status = isAwaitingApproval
            ? AiToolInvocationViewStatus.awaitingApproval
            : AiToolInvocationViewStatus.running;
        final invocation = AiToolInvocationView(
          callId: id,
          name: pending.call.name,
          argumentsJson: _encodeToolArguments(pending.call.arguments),
          status: status,
          requestedAt: pending.requestedAt,
        );
        display.add(
          AiChatViewMessage(
            id: 'tool-pending-$id',
            role: AiMessageRole.assistant.name,
            content: '`${pending.call.name}`',
            isToolResultBubble: true,
            toolInvocations: [invocation],
          ),
        );
      }
      pendingCalls.clear();
      pendingOrder.clear();
    }

    for (final message in messages) {
      if (message.role == AiMessageRole.system) continue;
      final calls = message.parts.whereType<AiToolCallPart>();
      if (message.role == AiMessageRole.assistant && calls.isNotEmpty) {
        flushPending();
        // 先渲染该 assistant 消息自身的文本/思考内容，
        // 保证多轮工具调用中每轮的自然语言回复不会丢失。
        final text = message.parts
            .whereType<AiTextPart>()
            .map((part) => part.text)
            .join();
        final reasoning = message.parts
            .whereType<AiReasoningPart>()
            .map((part) => part.text)
            .join();
        final assistantContent = AiThinkingMarkup.compose(
          thinking: reasoning,
          answer: text,
          duration: null,
        );
        if (assistantContent.isNotEmpty) {
          display.add(
            AiChatViewMessage(
              id: message.id,
              sourceMessageId: message.id,
              role: message.role.name,
              content: assistantContent,
              rawDetails: _historyDetails(message),
              transportTrace: message.transportTrace,
            ),
          );
        }
        for (final part in calls) {
          final id = part.toolCall.id;
          if (id.isEmpty) continue;
          pendingCalls[id] = _PendingToolCall(
            call: part.toolCall,
            requestedAt: message.completedAt ?? message.createdAt,
          );
          pendingOrder.add(id);
        }
        continue;
      }

      final results = message.parts.whereType<AiToolResultPart>();
      if (message.role == AiMessageRole.tool && results.isNotEmpty) {
        for (final part in results) {
          final result = part.toolResult;
          final pending = pendingCalls.remove(result.toolCallId);
          pendingOrder.remove(result.toolCallId);
          final name = pending?.call.name.isNotEmpty == true
              ? pending!.call.name
              : result.name;
          final invocation = AiToolInvocationView(
            callId: result.toolCallId,
            name: name,
            argumentsJson: pending == null
                ? ''
                : _encodeToolArguments(pending.call.arguments),
            status: result.success
                ? AiToolInvocationViewStatus.succeeded
                : AiToolInvocationViewStatus.failed,
            resultContent: result.content,
            requestedAt: pending?.requestedAt,
            completedAt: message.completedAt ?? message.createdAt,
          );
          display.add(
            AiChatViewMessage(
              id: 'tool-result-${message.id}-${result.toolCallId}',
              sourceMessageId: message.id,
              role: AiMessageRole.assistant.name,
              content:
                  '${result.success ? '✅' : '❌'} `$name`:\n\n${result.content}',
              isError: !result.success,
              isToolResultBubble: true,
              toolInvocations: [invocation],
            ),
          );
        }
        continue;
      }

      flushPending();
      final text = message.parts
          .whereType<AiTextPart>()
          .map((part) => part.text)
          .join();
      final reasoning = message.parts
          .whereType<AiReasoningPart>()
          .map((part) => part.text)
          .join();
      final content = message.role == AiMessageRole.assistant
          ? AiThinkingMarkup.compose(
              thinking: reasoning,
              answer: text,
              duration: null, // Note: persisted messages don't yet store duration directly
            )
          : text;
      if (content.isEmpty && message.status != AiMessageStatus.failed) continue;
      display.add(
        AiChatViewMessage(
          id: message.id,
          sourceMessageId: message.id,
          role: message.role.name,
          content: content.isNotEmpty
              ? content
              : _failureDetail(message.failure),
          isError: message.status == AiMessageStatus.failed,
          rawDetails: _historyDetails(message),
          transportTrace: message.transportTrace,
        ),
      );
    }
    flushPending();
    return List<AiChatViewMessage>.unmodifiable(display);
  }

  AiChatViewMessage mapStreaming({
    required String messageId,
    required AiStreamSnapshot snapshot,
  }) {
    return AiChatViewMessage(
      id: messageId,
      sourceMessageId: messageId,
      role: AiMessageRole.assistant.name,
      content: AiThinkingMarkup.compose(
        thinking: snapshot.reasoning,
        answer: snapshot.text,
        duration: snapshot.reasoningDuration,
      ),
      isError: snapshot.status == AiStreamStatus.failed,
      rawDetails: _snapshotDetails(snapshot),
      transportTrace: snapshot.transportTrace,
      toolInvocations: snapshot.toolCalls
          .map(
            (call) => AiToolInvocationView(
              callId: call.id ?? 'pending-${call.index}',
              name: call.name.isEmpty ? 'tool #${call.index + 1}' : call.name,
              argumentsJson: call.argumentsJson,
              status: call.argumentsJson.trim().isEmpty
                  ? AiToolInvocationViewStatus.preparing
                  : AiToolInvocationViewStatus.running,
            ),
          )
          .toList(growable: false),
    );
  }

  static String _snapshotDetails(AiStreamSnapshot snapshot) {
    final buffer = StringBuffer()
      ..writeln('request_id: ${snapshot.requestId}')
      ..writeln('sequence: ${snapshot.sequence}')
      ..writeln('status: ${snapshot.status.name}');
    if (snapshot.finishReason != null) {
      buffer.writeln('finish_reason: ${snapshot.finishReason!.name}');
    }
    if (snapshot.usage != null) {
      buffer.writeln('usage: ${snapshot.usage}');
    }
    for (final call in snapshot.toolCalls) {
      buffer.writeln('tool: ${call.name} (${call.id ?? 'pending'})');
      if (call.argumentsJson.isNotEmpty) {
        buffer.writeln('arguments: ${call.argumentsJson}');
      }
    }
    if (snapshot.failure != null) {
      buffer.writeln('failure: ${snapshot.failure}');
    }
    if (snapshot.transportTrace case final trace?) {
      buffer
        ..writeln()
        ..writeln(_transportTraceDetails(trace));
    } else {
      buffer.writeln('transport: server did not provide metadata');
    }
    return buffer.toString().trim();
  }

  static String _historyDetails(AiMessage message) {
    final buffer = StringBuffer()
      ..writeln('message_id: ${message.id}')
      ..writeln('conversation_id: ${message.conversationId}')
      ..writeln('role: ${message.role.name}')
      ..writeln('status: ${message.status.name}')
      ..writeln('created_at: ${message.createdAt.toIso8601String()}');
    if (message.completedAt != null) {
      buffer.writeln('completed_at: ${message.completedAt!.toIso8601String()}');
    }
    if (message.usage != null) buffer.writeln('usage: ${message.usage}');
    if (message.failure != null) buffer.writeln('failure: ${message.failure}');
    buffer.writeln('transport: metadata unavailable for persisted message');
    return buffer.toString().trim();
  }

  static String _transportTraceDetails(AiTransportTrace trace) {
    final buffer = StringBuffer()
      ..writeln('transport:')
      ..writeln('  url: ${trace.requestUrl}')
      ..writeln(
        '  status: ${trace.statusCode?.toString() ?? 'server did not provide'}',
      )
      ..writeln(
        '  content_type: ${trace.contentType ?? 'server did not provide'}',
      )
      ..writeln(
        '  request_start: ${trace.requestStartTime?.toIso8601String() ?? 'server did not provide'}',
      )
      ..writeln(
        '  request_end: ${trace.requestEndTime?.toIso8601String() ?? 'server did not provide'}',
      )
      ..writeln(
        '  duration_ms: ${trace.responseDuration?.inMilliseconds.toString() ?? 'server did not provide'}',
      )
      ..writeln(
        '  provider_request_id: ${trace.providerRequestId ?? 'server did not provide'}',
      );
    if (trace.rawSseEvents.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('raw_sse:')
        ..writeln(trace.rawSseEvents.join('\n'));
    } else if (trace.rawResponseText != null &&
        trace.rawResponseText!.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('raw_response:')
        ..writeln(trace.rawResponseText!.trim());
    }
    if (trace.rawErrorJson != null && trace.rawErrorJson!.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('raw_error:')
        ..writeln(trace.rawErrorJson!.trim());
    }
    return buffer.toString().trimRight();
  }

  static String _failureDetail(AiFailure? failure) {
    if (failure == null) return '';
    final codeName = failure.code.name;
    final prefix = failure.messageKey.startsWith('ai.error.')
        ? codeName
        : failure.messageKey;
    if (failure.detail != null && failure.detail!.isNotEmpty) {
      return '$prefix\n\n${failure.detail}';
    }
    return prefix;
  }

  static String _encodeToolArguments(Map<String, Object?> arguments) {
    return const JsonEncoder.withIndent('  ').convert(arguments);
  }
}

class _PendingToolCall {
  const _PendingToolCall({required this.call, required this.requestedAt});

  final AiToolCall call;
  final DateTime? requestedAt;
}
