import 'dart:async';
import 'dart:convert';

import 'package:JsxposedX/features/ai/domain/events/ai_stream_event.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_system_models.dart';
import 'package:JsxposedX/features/ai/domain/ports/ai_protocol_adapter.dart';
import 'package:JsxposedX/features/ai/domain/services/ai_multimodal_message_codec.dart';
import 'package:JsxposedX/features/ai/infrastructure/adapters/protocol_adapter_support.dart';
import 'package:JsxposedX/features/ai/infrastructure/transport/sse_decoder.dart';

class OpenAiChatAdapter implements AiProtocolAdapter {
  const OpenAiChatAdapter({this.maxSseEventBytes = 1024 * 1024});

  final int maxSseEventBytes;

  @override
  String get id => 'openai.chat.v1';

  @override
  PreparedAiRequest prepare(
    AiRequest request, {
    required AiAdapterContext context,
  }) {
    var endpoint = resolveAiEndpoint(
      request.connection,
      AiEndpointKind.chatCompletions,
      'chat/completions',
    );
    final headers = <String, String>{
      'Accept': 'text/event-stream',
      'Content-Type': 'application/json',
      ...request.connection.customHeaders,
    };
    endpoint = applyAiAuthentication(
      endpoint: endpoint,
      headers: headers,
      context: context,
    );

    final body = <String, Object?>{
      'model': request.model.id,
      'messages': request.messages.map(_messageJson).toList(growable: false),
      'stream': request.options.stream,
    };
    final options = request.options;
    if (options.maxOutputTokens != null) {
      body['max_tokens'] = options.maxOutputTokens;
    }
    if (options.temperature != null) body['temperature'] = options.temperature;
    if (options.topP != null) body['top_p'] = options.topP;
    if (options.presencePenalty != null) {
      body['presence_penalty'] = options.presencePenalty;
    }
    if (options.frequencyPenalty != null) {
      body['frequency_penalty'] = options.frequencyPenalty;
    }
    if (options.reasoningEffort != null) {
      body['reasoning_effort'] = options.reasoningEffort;
    }
    if (request.tools.isNotEmpty) {
      body['tools'] = request.tools.map(_toolJson).toList(growable: false);
    }
    return PreparedAiRequest(uri: endpoint, headers: headers, body: body);
  }

  @override
  Stream<AiStreamEvent> decodeStream(
    Stream<List<int>> bytes, {
    required String requestId,
  }) async* {
    var sequence = 0;
    // Tool call fragments are grouped by call id first: some gateways omit
    // the index field (or reuse 0) while streaming parallel tool calls.
    // Grouping by id keeps arguments of different calls from interleaving
    // into one buffer, which would corrupt the assembled JSON.
    final toolCallIndexById = <String, int>{};
    var nextToolCallIndex = 0;
    yield AiStreamEvent.started(requestId: requestId, sequence: sequence++);
    var completed = false;
    try {
      await for (final event in AiSseDecoder(
        maxEventBytes: maxSseEventBytes,
      ).decode(bytes)) {
        if (event.data == '[DONE]') {
          if (!completed) {
            completed = true;
            yield AiStreamEvent.completed(
              requestId: requestId,
              sequence: sequence++,
              reason: AiFinishReason.stop,
            );
          }
          continue;
        }
        final raw = jsonDecode(event.data);
        if (raw is! Map) {
          throw const FormatException('OpenAI stream event is not an object');
        }
        final map = Map<String, Object?>.from(raw);
        if (aiPayloadIsError(map)) {
          yield AiStreamEvent.failed(
            requestId: requestId,
            sequence: sequence++,
            failure: aiProviderPayloadFailure(map),
          );
          return;
        }
        final usage = _usage(map['usage']);
        if (usage != null) {
          yield AiStreamEvent.usage(
            requestId: requestId,
            sequence: sequence++,
            value: usage,
          );
        }
        final choices = map['choices'];
        if (choices is! List || choices.isEmpty || choices.first is! Map) {
          continue;
        }
        final choice = Map<String, Object?>.from(choices.first as Map);
        final delta = choice['delta'];
        if (delta is Map) {
          final deltaMap = Map<String, Object?>.from(delta);
          final text = deltaMap['content'];
          if (text is String && text.isNotEmpty) {
            yield AiStreamEvent.textDelta(
              requestId: requestId,
              sequence: sequence++,
              itemId: requestId,
              delta: text,
            );
          }
          final reasoning = deltaMap['reasoning_content'];
          if (reasoning is String && reasoning.isNotEmpty) {
            yield AiStreamEvent.reasoningDelta(
              requestId: requestId,
              sequence: sequence++,
              itemId: requestId,
              delta: reasoning,
            );
          }
          final toolCalls = deltaMap['tool_calls'];
          if (toolCalls is List) {
            for (final rawCall in toolCalls) {
              if (rawCall is! Map) continue;
              final call = Map<String, Object?>.from(rawCall);
              final function = call['function'];
              final functionMap = function is Map
                  ? Map<String, Object?>.from(function)
                  : const <String, Object?>{};
              final deltaId = call['id']?.toString();
              var index = aiIntValue(call['index']);
              if (deltaId != null && deltaId.isNotEmpty) {
                final knownIndex = toolCallIndexById[deltaId];
                if (knownIndex != null) {
                  // 后续分块 id 为 null 时由 index 归组；这里以 id 归组，
                  // 防止网关省略/复用 index 时不同工具的参数被拼进同一缓冲区。
                  index = knownIndex;
                } else {
                  index ??= nextToolCallIndex++;
                  toolCallIndexById[deltaId] = index;
                }
              }
              yield AiStreamEvent.toolCallDelta(
                requestId: requestId,
                sequence: sequence++,
                index: index ?? 0,
                toolCallId: deltaId,
                name: functionMap['name']?.toString(),
                argumentsDelta: functionMap['arguments']?.toString(),
              );
            }
          }
        }
        final finish = _finishReason(choice['finish_reason']);
        if (finish != null && !completed) {
          completed = true;
          yield AiStreamEvent.completed(
            requestId: requestId,
            sequence: sequence++,
            reason: finish,
          );
        }
      }
      if (!completed) {
        yield AiStreamEvent.failed(
          requestId: requestId,
          sequence: sequence++,
          failure: const AiFailure(
            code: AiFailureCode.protocolTruncated,
            messageKey: 'ai.error.protocolTruncated',
          ),
        );
      }
    } on FormatException {
      yield AiStreamEvent.failed(
        requestId: requestId,
        sequence: sequence++,
        failure: const AiFailure(
          code: AiFailureCode.protocolMalformed,
          messageKey: 'ai.error.protocolMalformed',
        ),
      );
    }
  }

  @override
  Stream<AiStreamEvent> decodeResponse(
    List<int> bytes, {
    required String requestId,
  }) async* {
    var sequence = 0;
    yield AiStreamEvent.started(requestId: requestId, sequence: sequence++);
    try {
      final raw = jsonDecode(utf8.decode(bytes));
      if (raw is! Map) {
        throw const FormatException('OpenAI response is not an object');
      }
      final map = Map<String, Object?>.from(raw);
      if (aiPayloadIsError(map)) {
        yield AiStreamEvent.failed(
          requestId: requestId,
          sequence: sequence++,
          failure: aiProviderPayloadFailure(map),
        );
        return;
      }
      final choices = map['choices'];
      if (choices is! List || choices.isEmpty || choices.first is! Map) {
        throw const FormatException('OpenAI response has no choices');
      }
      final choice = Map<String, Object?>.from(choices.first as Map);
      final message = choice['message'];
      if (message is! Map) {
        throw const FormatException('OpenAI response has no message');
      }
      final messageMap = Map<String, Object?>.from(message);
      final reasoning = messageMap['reasoning_content'];
      if (reasoning is String && reasoning.isNotEmpty) {
        yield AiStreamEvent.reasoningDelta(
          requestId: requestId,
          sequence: sequence++,
          itemId: requestId,
          delta: reasoning,
        );
      }
      final content = messageMap['content'];
      if (content is String && content.isNotEmpty) {
        yield AiStreamEvent.textDelta(
          requestId: requestId,
          sequence: sequence++,
          itemId: requestId,
          delta: content,
        );
      }
      final toolCalls = messageMap['tool_calls'];
      if (toolCalls is List) {
        for (var index = 0; index < toolCalls.length; index++) {
          final rawCall = toolCalls[index];
          if (rawCall is! Map) continue;
          final call = Map<String, Object?>.from(rawCall);
          final function = call['function'];
          final functionMap = function is Map
              ? Map<String, Object?>.from(function)
              : const <String, Object?>{};
          yield AiStreamEvent.toolCallDelta(
            requestId: requestId,
            sequence: sequence++,
            index: index,
            toolCallId: call['id']?.toString(),
            name: functionMap['name']?.toString(),
            argumentsDelta: functionMap['arguments']?.toString(),
          );
        }
      }
      final usage = _usage(map['usage']);
      if (usage != null) {
        yield AiStreamEvent.usage(
          requestId: requestId,
          sequence: sequence++,
          value: usage,
        );
      }
      yield AiStreamEvent.completed(
        requestId: requestId,
        sequence: sequence++,
        reason:
            _finishReason(choice['finish_reason']) ?? AiFinishReason.unknown,
      );
    } on FormatException {
      yield AiStreamEvent.failed(
        requestId: requestId,
        sequence: sequence++,
        failure: const AiFailure(
          code: AiFailureCode.protocolMalformed,
          messageKey: 'ai.error.protocolMalformed',
        ),
      );
    }
  }

  static Map<String, Object?> _messageJson(AiMessage message) {
    final content = aiTextContent(message);
    final reasoning = message.parts
        .whereType<AiReasoningPart>()
        .map((part) => part.text)
        .join();
    final toolCalls = message.parts.whereType<AiToolCallPart>().toList();
    final toolResult = message.parts.whereType<AiToolResultPart>().firstOrNull;
    if (message.role == AiMessageRole.tool && toolResult != null) {
      return {
        'role': 'tool',
        'tool_call_id': toolResult.toolResult.toolCallId,
        'content': toolResult.toolResult.content,
      };
    }
    final requestContent =
        message.role == AiMessageRole.user &&
            AiMultimodalMessageCodec.isEncoded(content)
        ? AiMultimodalMessageCodec.toOpenAiContent(content, isZh: true)
        : content;
    return {
      'role': message.role.name,
      'content': content.isEmpty && toolCalls.isNotEmpty
          ? null
          : requestContent,
      if (reasoning.isNotEmpty) 'reasoning_content': reasoning,
      if (toolCalls.isNotEmpty)
        'tool_calls': toolCalls
            .map(
              (part) => <String, Object?>{
                'id': part.toolCall.id,
                'type': 'function',
                'function': {
                  'name': part.toolCall.name,
                  'arguments': jsonEncode(part.toolCall.arguments),
                },
              },
            )
            .toList(growable: false),
    };
  }

  static Map<String, Object?> _toolJson(AiToolSpec tool) => {
    'type': 'function',
    'function': {
      'name': tool.name,
      'description': tool.description,
      'parameters': tool.inputSchema,
    },
  };

  static AiUsage? _usage(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, Object?>.from(raw);
    final input = aiIntValue(map['prompt_tokens'] ?? map['input_tokens']);
    final output = aiIntValue(map['completion_tokens'] ?? map['output_tokens']);
    final total = aiIntValue(map['total_tokens']);
    if (input == null && output == null && total == null) return null;
    return AiUsage(
      inputTokens: input ?? 0,
      outputTokens: output ?? 0,
      totalTokens: total ?? ((input ?? 0) + (output ?? 0)),
    );
  }

  static AiFinishReason? _finishReason(Object? value) =>
      switch (value?.toString()) {
        'stop' => AiFinishReason.stop,
        'length' => AiFinishReason.length,
        'tool_calls' => AiFinishReason.toolCall,
        'content_filter' => AiFinishReason.contentFilter,
        _ => null,
      };
}
