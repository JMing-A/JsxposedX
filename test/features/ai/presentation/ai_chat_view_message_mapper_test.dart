import 'package:JsxposedX/features/ai/application/chat/ai_stream_snapshot.dart';
import 'package:JsxposedX/features/ai/application/chat/ai_transport_trace.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_system_models.dart';
import 'package:JsxposedX/features/ai/presentation/mappers/ai_chat_view_message_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const mapper = AiChatViewMessageMapper();

  test('maps standard text and reasoning without a legacy message', () {
    final result = mapper.mapHistory([
      AiMessage(
        id: 'assistant',
        conversationId: 'conversation',
        role: AiMessageRole.assistant,
        parts: const [
          AiContentPart.reasoning('inspect first'),
          AiContentPart.text('answer'),
        ],
        createdAt: _epoch,
      ),
    ]);

    expect(result, hasLength(1));
    expect(result.single.id, 'assistant');
    expect(result.single.role, 'assistant');
    expect(result.single.content, contains('inspect first'));
    expect(result.single.content, contains('answer'));
  });

  test('maps ordinary user text to a user view message', () {
    final result = mapper.mapHistory([
      AiMessage(
        id: 'user',
        conversationId: 'conversation',
        role: AiMessageRole.user,
        parts: const [AiContentPart.text('hello there')],
        createdAt: _epoch,
      ),
    ]);

    expect(result, hasLength(1));
    expect(result.single.id, 'user');
    expect(result.single.role, 'user');
    expect(result.single.content, 'hello there');
    expect(result.single.isError, isFalse);
    expect(result.single.isToolResultBubble, isFalse);
  });

  test('maps a complete tool exchange to one result view item', () {
    final result = mapper.mapHistory([
      AiMessage(
        id: 'call-message',
        conversationId: 'conversation',
        role: AiMessageRole.assistant,
        parts: const [
          AiContentPart.toolCall(
            toolCall: AiToolCall(
              id: 'call-1',
              name: 'inspect_apk',
              arguments: {},
            ),
          ),
        ],
        createdAt: _epoch,
      ),
      AiMessage(
        id: 'result-message',
        conversationId: 'conversation',
        role: AiMessageRole.tool,
        parts: const [
          AiContentPart.toolResult(
            toolResult: AiToolResult(
              toolCallId: 'call-1',
              name: 'inspect_apk',
              success: true,
              content: 'done',
            ),
          ),
        ],
        createdAt: _epoch.add(const Duration(seconds: 1)),
      ),
    ]);

    expect(result, hasLength(1));
    expect(result.single.isToolResultBubble, isTrue);
    expect(result.single.content, contains('inspect_apk'));
    expect(result.single.content, contains('done'));
    expect(result.single.toolInvocations, hasLength(1));
    expect(result.single.toolInvocations.single.callId, 'call-1');
    expect(result.single.toolInvocations.single.name, 'inspect_apk');
    expect(result.single.toolInvocations.single.resultContent, 'done');
    expect(
      result.single.toolInvocations.single.duration,
      const Duration(seconds: 1),
    );
  });

  test('renders assistant text alongside tool results without losing either', () {
    final result = mapper.mapHistory([
      AiMessage(
        id: 'assistant-turn',
        conversationId: 'conversation',
        role: AiMessageRole.assistant,
        parts: const [
          AiContentPart.reasoning('need to inspect'),
          AiContentPart.text('Let me inspect the APK first.'),
          AiContentPart.toolCall(
            toolCall: AiToolCall(
              id: 'call-1',
              name: 'inspect_apk',
              arguments: {},
            ),
          ),
        ],
        createdAt: _epoch,
      ),
      AiMessage(
        id: 'result-message',
        conversationId: 'conversation',
        role: AiMessageRole.tool,
        parts: const [
          AiContentPart.toolResult(
            toolResult: AiToolResult(
              toolCallId: 'call-1',
              name: 'inspect_apk',
              success: true,
              content: 'done',
            ),
          ),
        ],
        createdAt: _epoch.add(const Duration(seconds: 1)),
      ),
    ]);

    // 多轮工具调用中，assistant 的自然语言文本不再被工具气泡覆盖丢失。
    expect(result, hasLength(2));
    expect(result[0].id, 'assistant-turn');
    expect(result[0].isToolResultBubble, isFalse);
    expect(result[0].content, contains('need to inspect'));
    expect(result[0].content, contains('Let me inspect the APK first.'));
    expect(result[1].isToolResultBubble, isTrue);
    expect(result[1].id, 'tool-result-result-message-call-1');
    expect(result[1].toolInvocations.single.callId, 'call-1');
  });

  test('keeps tool call and result paired when multiple calls are present', () {
    final result = mapper.mapHistory([
      AiMessage(
        id: 'calls',
        conversationId: 'conversation',
        role: AiMessageRole.assistant,
        parts: const [
          AiContentPart.toolCall(
            toolCall: AiToolCall(
              id: 'call-a',
              name: 'first_tool',
              arguments: {},
            ),
          ),
          AiContentPart.toolCall(
            toolCall: AiToolCall(
              id: 'call-b',
              name: 'second_tool',
              arguments: {},
            ),
          ),
        ],
        createdAt: _epoch,
      ),
      AiMessage(
        id: 'results',
        conversationId: 'conversation',
        role: AiMessageRole.tool,
        parts: const [
          AiContentPart.toolResult(
            toolResult: AiToolResult(
              toolCallId: 'call-b',
              name: 'second_tool',
              success: true,
              content: 'second done',
            ),
          ),
          AiContentPart.toolResult(
            toolResult: AiToolResult(
              toolCallId: 'call-a',
              name: 'first_tool',
              success: true,
              content: 'first done',
            ),
          ),
        ],
        createdAt: _epoch.add(const Duration(seconds: 1)),
      ),
    ]);

    expect(result, hasLength(2));
    expect(result[0].content, contains('second_tool'));
    expect(result[0].content, contains('second done'));
    expect(result[1].content, contains('first_tool'));
    expect(result[1].content, contains('first done'));
    expect(result.every((message) => message.isToolResultBubble), isTrue);
    expect(result[0].toolInvocations.single.callId, 'call-b');
    expect(result[1].toolInvocations.single.callId, 'call-a');
  });

  test('renders failed tool results as error view messages', () {
    final result = mapper.mapHistory([
      AiMessage(
        id: 'call',
        conversationId: 'conversation',
        role: AiMessageRole.assistant,
        parts: const [
          AiContentPart.toolCall(
            toolCall: AiToolCall(
              id: 'call-failed',
              name: 'dangerous_tool',
              arguments: {},
            ),
          ),
        ],
        createdAt: _epoch,
      ),
      AiMessage(
        id: 'failed-result',
        conversationId: 'conversation',
        role: AiMessageRole.tool,
        parts: const [
          AiContentPart.toolResult(
            toolResult: AiToolResult(
              toolCallId: 'call-failed',
              name: 'dangerous_tool',
              success: false,
              content: 'permission denied',
            ),
          ),
        ],
        createdAt: _epoch.add(const Duration(seconds: 1)),
      ),
    ]);

    expect(result, hasLength(1));
    expect(result.single.isError, isTrue);
    expect(result.single.content, contains('permission denied'));
    expect(result.single.toolInvocations.single.success, isFalse);
  });

  test('keeps an unmatched tool call visible as a pending tool bubble', () {
    final result = mapper.mapHistory([
      AiMessage(
        id: 'pending-call',
        conversationId: 'conversation',
        role: AiMessageRole.assistant,
        parts: const [
          AiContentPart.toolCall(
            toolCall: AiToolCall(
              id: 'call-pending',
              name: 'long_running_tool',
              arguments: {},
            ),
          ),
        ],
        createdAt: _epoch,
      ),
    ]);

    expect(result, hasLength(1));
    expect(result.single.isToolResultBubble, isTrue);
    expect(result.single.content, contains('long_running_tool'));
    expect(result.single.toolInvocations.single.callId, 'call-pending');
    expect(result.single.toolInvocations.single.argumentsJson, '{}');
  });

  test('maps the active stream snapshot to the current assistant item', () {
    final result = mapper.mapStreaming(
      messageId: 'streaming',
      snapshot: const AiStreamSnapshot(
        requestId: 'request',
        text: 'partial',
        reasoning: 'thinking',
        status: AiStreamStatus.streaming,
      ),
    );

    expect(result.id, 'streaming');
    expect(result.role, 'assistant');
    expect(result.content, contains('partial'));
    expect(result.content, contains('thinking'));
    expect(result.isError, isFalse);
  });

  test('includes transport trace in active stream raw details', () {
    final result = mapper.mapStreaming(
      messageId: 'streaming',
      snapshot: AiStreamSnapshot(
        requestId: 'request',
        text: 'partial',
        status: AiStreamStatus.streaming,
        transportTrace: AiTransportTrace(
          requestUrl: 'https://example.test/v1/chat/completions',
          statusCode: 200,
          contentType: 'text/event-stream',
          requestStartTime: _epoch,
          requestEndTime: _epoch.add(const Duration(milliseconds: 8)),
          responseDuration: const Duration(milliseconds: 8),
          providerRequestId: 'provider-request-1',
          rawSseEvents: const ['data: {"delta":"partial"}'],
        ),
      ),
    );

    expect(result.rawDetails, contains('transport:'));
    expect(
      result.rawDetails,
      contains('url: https://example.test/v1/chat/completions'),
    );
    expect(
      result.rawDetails,
      contains('provider_request_id: provider-request-1'),
    );
    expect(result.rawDetails, contains('raw_sse:'));
    expect(result.rawDetails, contains('data: {"delta":"partial"}'));
  });

  test('maps streaming tool call snapshots to structured invocations', () {
    final result = mapper.mapStreaming(
      messageId: 'streaming-tool',
      snapshot: const AiStreamSnapshot(
        requestId: 'request',
        status: AiStreamStatus.streaming,
        toolCalls: [
          AiToolCallSnapshot(
            index: 0,
            id: 'call-live',
            name: 'search_classes',
            argumentsJson: '{"keyword":"Root"}',
          ),
        ],
      ),
    );

    expect(result.toolInvocations, hasLength(1));
    expect(result.toolInvocations.single.callId, 'call-live');
    expect(result.toolInvocations.single.name, 'search_classes');
    expect(result.toolInvocations.single.argumentsJson, '{"keyword":"Root"}');
    expect(result.toolInvocations.single.isRunning, isTrue);
  });
}

final _epoch = DateTime.utc(2026, 9, 10);
