import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:JsxposedX/features/ai/application/chat/ai_chat_orchestrator.dart';
import 'package:JsxposedX/features/ai/application/chat/ai_chat_session_environment.dart';
import 'package:JsxposedX/features/ai/application/chat/ai_chat_session_controller.dart';
import 'package:JsxposedX/features/ai/application/chat/ai_chat_session_state.dart';
import 'package:JsxposedX/features/ai/application/chat/ai_transport_trace.dart';
import 'package:JsxposedX/features/ai/data/repositories/drift_ai_catalog_repository.dart';
import 'package:JsxposedX/features/ai/data/repositories/drift_ai_conversation_repository.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_system_models.dart';
import 'package:JsxposedX/features/ai/domain/ports/ai_credential_store.dart';
import 'package:JsxposedX/features/ai/domain/ports/ai_protocol_adapter.dart';
import 'package:JsxposedX/features/ai/domain/ports/ai_tool_executor.dart';
import 'package:JsxposedX/features/ai/domain/registries/protocol_adapter_registry.dart';
import 'package:JsxposedX/features/ai/domain/registries/provider_definition_registry.dart';
import 'package:JsxposedX/features/ai/infrastructure/adapters/openai_chat_adapter.dart';
import 'package:JsxposedX/features/ai/infrastructure/persistence/ai_database.dart'
    hide
        AiAssistantProfile,
        AiConversation,
        AiModelDefinition,
        AiProviderConnection;

void main() {
  late AiDatabase database;
  late DriftAiCatalogRepository catalog;
  late DriftAiConversationRepository conversations;

  setUp(() async {
    database = AiDatabase.forTesting(NativeDatabase.memory());
    catalog = DriftAiCatalogRepository(database);
    conversations = DriftAiConversationRepository(database);
    await _seedCatalog(catalog);
    await conversations.saveConversation(
      AiConversation(
        id: 'conversation',
        title: 'Chat',
        assistantId: 'assistant',
        createdAt: _epoch,
        updatedAt: _epoch,
      ),
    );
  });

  tearDown(() => database.close());

  test(
    'publishes real stream snapshots and persists the final message',
    () async {
      final transport = _ControlledTransport();
      final controller = _controller(catalog, conversations, transport);
      await controller.initialize();

      final sending = controller.sendText('hello');
      await transport.sent.future;
      transport.addChatDelta('Hel');
      await _waitUntil(() => controller.state.runSnapshot?.text == 'Hel');

      expect(controller.state.phase, AiChatSessionPhase.streaming);
      expect(controller.state.runSnapshot?.text, 'Hel');
      expect(controller.state.messages, hasLength(2));
      expect(controller.state.messages.last.parts, isEmpty);

      transport.addChatDelta('lo');
      await transport.complete();
      await sending;

      final assistantMessage = controller.state.messages.last;
      expect(controller.state.phase, AiChatSessionPhase.ready);
      expect(assistantMessage.status, AiMessageStatus.completed);
      expect(
        assistantMessage.parts.whereType<AiTextPart>().single.text,
        'Hello',
      );
      final stored = await conversations.getMessages('conversation');
      expect(stored, hasLength(2));
      expect(stored.last.id, assistantMessage.id);
      await controller.close();
    },
  );

  test('rejects a second run in the same conversation', () async {
    final transport = _ControlledTransport();
    final controller = _controller(catalog, conversations, transport);
    await controller.initialize();

    final sending = controller.sendText('first');
    await transport.sent.future;

    await expectLater(controller.sendText('second'), throwsStateError);

    await transport.complete();
    await sending;
    expect(await conversations.getMessages('conversation'), hasLength(2));
    await controller.close();
  });

  test('cancels the transport and keeps partial output', () async {
    final transport = _ControlledTransport();
    final controller = _controller(catalog, conversations, transport);
    await controller.initialize();

    final sending = controller.sendText('hello');
    await transport.sent.future;
    transport.addChatDelta('partial');
    await Future<void>.delayed(const Duration(milliseconds: 80));
    controller.cancel();
    await sending;

    final assistantMessage = controller.state.messages.last;
    expect(assistantMessage.status, AiMessageStatus.cancelled);
    expect(
      assistantMessage.parts.whereType<AiTextPart>().single.text,
      'partial',
    );
    expect(controller.state.hasActiveRun, isFalse);
    await controller.close();
  });

  test('repairs a stale streaming message during initialization', () async {
    await conversations.saveMessage(
      AiMessage(
        id: 'stale',
        conversationId: 'conversation',
        role: AiMessageRole.assistant,
        parts: const [AiContentPart.text('partial')],
        status: AiMessageStatus.streaming,
        createdAt: _epoch.add(const Duration(seconds: 1)),
      ),
    );
    final controller = _controller(
      catalog,
      conversations,
      _ControlledTransport(),
    );

    await controller.initialize();

    expect(
      controller.state.messages.single.status,
      AiMessageStatus.interrupted,
    );
    expect(
      (await conversations.getMessages('conversation')).single.status,
      AiMessageStatus.interrupted,
    );
    await controller.close();
  });

  test('persists edited user content before regenerating', () async {
    final transport = _TextTransport(['first answer', 'edited answer']);
    final controller = _controller(catalog, conversations, transport);
    await controller.initialize();
    await controller.sendText('original question');

    final userMessageId = controller.state.messages.first.id;
    await controller.editUserMessageAndResend(
      messageId: userMessageId,
      updatedText: 'edited question',
    );

    final stored = await conversations.getMessages('conversation');
    expect(stored, hasLength(2));
    expect(stored.first.id, userMessageId);
    expect(
      stored.first.parts.whereType<AiTextPart>().single.text,
      'edited question',
    );
    expect(
      stored.last.parts.whereType<AiTextPart>().single.text,
      'edited answer',
    );
    await controller.close();
  });

  test('deletes a single message when idle', () async {
    final controller = _controller(
      catalog,
      conversations,
      _TextTransport(['answer']),
    );
    await controller.initialize();
    await controller.sendText('question');
    final assistantId = controller.state.messages.last.id;
    await controller.deleteMessage(assistantId);
    expect(controller.state.messages, hasLength(1));
    expect((await conversations.getMessages('conversation')), hasLength(1));
    await controller.close();
  });

  test('executes reverse tools and returns results to the model', () async {
    final transport = _ScriptedToolTransport();
    const executor = _FakeToolExecutor();
    final controller = _controller(
      catalog,
      conversations,
      transport,
      environment: const AiChatSessionEnvironment(
        id: 'apk_reverse',
        scopeId: 'com.example.app',
        version: 'v2',
        systemPrompt: 'Analyze the APK with tools.',
        tools: [
          AiToolSpec(
            name: 'get_manifest',
            description: 'Read manifest',
            inputSchema: {'type': 'object'},
          ),
        ],
        toolExecutor: executor,
      ),
    );

    await controller.initialize();
    await controller.sendText('analyze');

    expect(transport.requests, hasLength(2));
    final secondMessages = transport.requests[1].body['messages'] as List;
    expect(
      secondMessages.whereType<Map>().any(
        (message) =>
            message['role'] == 'tool' && message['content'] == 'manifest-data',
      ),
      isTrue,
    );
    final stored = await conversations.getMessages('conversation');
    expect(stored, hasLength(4));
    expect(stored[1].parts.whereType<AiToolCallPart>(), hasLength(1));
    expect(stored[2].parts.whereType<AiToolResultPart>(), hasLength(1));
    expect(
      stored.last.parts.whereType<AiTextPart>().single.text,
      'analysis complete',
    );

    await controller.regenerateLastResponse();
    expect(transport.requests, hasLength(3));
    expect(await conversations.getMessages('conversation'), hasLength(2));
    await controller.close();
  });

  test('persists a failed tool result when the executor throws', () async {
    final transport = _ScriptedToolTransport();
    final controller = _controller(
      catalog,
      conversations,
      transport,
      environment: const AiChatSessionEnvironment(
        id: 'apk_reverse',
        scopeId: 'com.example.app',
        version: 'v2',
        systemPrompt: '',
        tools: [
          AiToolSpec(
            name: 'get_manifest',
            description: 'Read manifest',
            inputSchema: {'type': 'object'},
          ),
        ],
        toolExecutor: _ThrowingToolExecutor(),
      ),
    );

    await controller.initialize();
    await controller.sendText('analyze');

    final stored = await conversations.getMessages('conversation');
    final result = stored
        .expand((message) => message.parts)
        .whereType<AiToolResultPart>()
        .single
        .toolResult;
    expect(result.success, isFalse);
    expect(result.content, contains('boom'));
    expect(controller.state.phase, AiChatSessionPhase.ready);
    await controller.close();
  });

  test(
    'retries a failed tool result and continues the assistant turn',
    () async {
      final transport = _ScriptedToolTransport();
      final executor = _FlakyToolExecutor();
      final controller = _controller(
        catalog,
        conversations,
        transport,
        environment: AiChatSessionEnvironment(
          id: 'apk_reverse',
          scopeId: 'com.example.app',
          version: 'v2',
          systemPrompt: '',
          tools: const [
            AiToolSpec(
              name: 'get_manifest',
              description: 'Read manifest',
              inputSchema: {'type': 'object'},
            ),
          ],
          toolExecutor: executor,
        ),
      );

      await controller.initialize();
      await controller.sendText('analyze');

      final failedToolMessage = controller.state.messages.singleWhere(
        (message) =>
            message.role == AiMessageRole.tool &&
            message.parts.whereType<AiToolResultPart>().any(
              (part) => !part.toolResult.success,
            ),
      );

      await controller.retryByMessageId(failedToolMessage.id);

      expect(executor.calls, 2);
      expect(transport.requests, hasLength(3));
      final stored = await conversations.getMessages('conversation');
      expect(stored, hasLength(4));
      final retriedResult = stored
          .expand((message) => message.parts)
          .whereType<AiToolResultPart>()
          .single
          .toolResult;
      expect(retriedResult.success, isTrue);
      expect(retriedResult.content, 'manifest-data-after-retry');
      expect(
        stored.last.parts.whereType<AiTextPart>().single.text,
        'analysis complete',
      );
      await controller.close();
    },
  );

  test(
    'continues from an interruption with a Chinese continue prompt',
    () async {
      final transport = _CancelThenTextTransport();
      final controller = _controller(catalog, conversations, transport);
      await controller.initialize();

      final sending = controller.sendText('analyze this app');
      await transport.sent.future;
      controller.cancel();
      await sending;
      expect(
        controller.state.messages.last.status,
        AiMessageStatus.cancelled,
      );

      await controller.retryLastResponse(isZh: true);

      // 中断历史完整保留，不回退到会话起始状态。
      final stored = await conversations.getMessages('conversation');
      expect(stored, hasLength(4));
      expect(
        stored[0].parts.whereType<AiTextPart>().single.text,
        'analyze this app',
      );
      expect(stored[1].status, AiMessageStatus.cancelled);
      expect(stored[2].role, AiMessageRole.user);
      expect(stored[2].parts.whereType<AiTextPart>().single.text, '继续');
      expect(
        stored.last.parts.whereType<AiTextPart>().single.text,
        'resumed answer',
      );
      // 接续请求基于既有上下文，包含原始问题与“继续”指令。
      expect(transport.requests, hasLength(2));
      final secondMessages = transport.requests[1].body['messages'] as List;
      final contents = secondMessages
          .whereType<Map>()
          .map((message) => message['content'])
          .toList();
      expect(contents, contains('analyze this app'));
      expect(contents, contains('继续'));
      await controller.close();
    },
  );

  test(
    'continues from an interruption with an English continue prompt',
    () async {
      final transport = _CancelThenTextTransport();
      final controller = _controller(catalog, conversations, transport);
      await controller.initialize();

      final sending = controller.sendText('analyze this app');
      await transport.sent.future;
      controller.cancel();
      await sending;

      await controller.retryLastResponse(isZh: false);

      final stored = await conversations.getMessages('conversation');
      expect(stored, hasLength(4));
      expect(stored[2].parts.whereType<AiTextPart>().single.text, 'Continue');
      expect(
        stored.last.parts.whereType<AiTextPart>().single.text,
        'resumed answer',
      );
      await controller.close();
    },
  );
}

AiChatSessionController _controller(
  DriftAiCatalogRepository catalog,
  DriftAiConversationRepository conversations,
  AiTransport transport, {
  AiChatSessionEnvironment? environment,
}) {
  final ids = _IdFactory();
  final orchestrator = AiChatOrchestrator(
    providerRegistry: ProviderDefinitionRegistry(const [
      AiProviderDefinition(
        id: 'openai',
        displayName: 'OpenAI',
        adapterId: 'openai.chat.v1',
      ),
    ]),
    adapterRegistry: ProtocolAdapterRegistry(const [OpenAiChatAdapter()]),
    transport: transport,
    credentialStore: const _CredentialStore(),
  );
  return AiChatSessionController(
    conversationId: 'conversation',
    catalogRepository: catalog,
    conversationRepository: conversations,
    startRun: orchestrator.start,
    idFactory: ids.next,
    now: () => _epoch.add(const Duration(minutes: 1)),
    checkpointInterval: const Duration(milliseconds: 20),
    environment: environment,
  );
}

Future<void> _seedCatalog(DriftAiCatalogRepository catalog) {
  return catalog.saveConnectionBundle(
    connection: AiProviderConnection(
      id: 'connection',
      providerId: 'openai',
      displayName: 'OpenAI',
      baseUri: Uri.parse('https://example.test/v1/'),
      credentialRef: 'credential',
    ),
    models: const [
      AiModelDefinition(
        id: 'model',
        connectionId: 'connection',
        displayName: 'Model',
        capabilities: AiModelCapabilities(streaming: true, toolCalling: true),
        limits: AiModelLimits(contextTokens: 4096),
      ),
    ],
    assistants: [
      AiAssistantProfile(
        id: 'assistant',
        name: 'Assistant',
        connectionId: 'connection',
        modelId: 'model',
        createdAt: _epoch,
        updatedAt: _epoch,
      ),
    ],
  );
}

final _epoch = DateTime.utc(2026, 9, 5);

class _IdFactory {
  var _value = 0;

  String next() => 'id-${_value++}';
}

class _CredentialStore implements AiCredentialStore {
  const _CredentialStore();

  @override
  Future<AiSecret?> read(String credentialRef) async => const AiSecret('key');

  @override
  Future<String> put(AiSecret secret, {String? credentialRef}) {
    throw UnimplementedError();
  }

  @override
  Future<void> delete(String credentialRef) async {}
}

class _ControlledTransport implements AiTransport {
  final StreamController<List<int>> _body = StreamController<List<int>>();
  final Completer<void> sent = Completer<void>();
  bool _closed = false;

  @override
  Future<AiTransportResponse> send(
    PreparedAiRequest request, {
    required AiCancellationToken cancellation,
  }) async {
    if (!sent.isCompleted) sent.complete();
    unawaited(
      cancellation.cancelled.then((_) async {
        if (_closed) return;
        _closed = true;
        _body.addError(
          const AiTransportException(
            AiFailure(
              code: AiFailureCode.cancelled,
              messageKey: 'ai.error.cancelled',
            ),
          ),
        );
        await _body.close();
      }),
    );
    return AiTransportResponse(
      statusCode: 200,
      headers: const {},
      body: _body.stream,
    );
  }

  void addChatDelta(String text) {
    final payload = jsonEncode({
      'choices': [
        {
          'delta': {'content': text},
          'finish_reason': null,
        },
      ],
    });
    _body.add(utf8.encode('data: $payload\n\n'));
  }

  Future<void> complete() async {
    if (_closed) return;
    _closed = true;
    _body.add(utf8.encode('data: [DONE]\n\n'));
    await _body.close();
  }
}

class _ScriptedToolTransport implements AiTransport {
  final List<PreparedAiRequest> requests = [];

  @override
  Future<AiTransportResponse> send(
    PreparedAiRequest request, {
    required AiCancellationToken cancellation,
  }) async {
    requests.add(request);
    final event = requests.length == 1
        ? {
            'choices': [
              {
                'delta': {
                  'tool_calls': [
                    {
                      'index': 0,
                      'id': 'call-1',
                      'function': {'name': 'get_manifest', 'arguments': '{}'},
                    },
                  ],
                },
                'finish_reason': 'tool_calls',
              },
            ],
          }
        : {
            'choices': [
              {
                'delta': {'content': 'analysis complete'},
                'finish_reason': 'stop',
              },
            ],
          };
    final body = utf8.encode('data: ${jsonEncode(event)}\n\ndata: [DONE]\n\n');
    return AiTransportResponse(
      statusCode: 200,
      headers: const {},
      body: Stream.value(body),
    );
  }
}

class _CancelThenTextTransport implements AiTransport {
  final List<PreparedAiRequest> requests = [];
  final StreamController<List<int>> _firstBody = StreamController<List<int>>();
  final Completer<void> sent = Completer<void>();

  @override
  Future<AiTransportResponse> send(
    PreparedAiRequest request, {
    required AiCancellationToken cancellation,
  }) async {
    requests.add(request);
    if (requests.length == 1) {
      if (!sent.isCompleted) sent.complete();
      unawaited(
        cancellation.cancelled.then((_) {
          _firstBody.addError(
            const AiTransportException(
              AiFailure(
                code: AiFailureCode.cancelled,
                messageKey: 'ai.error.cancelled',
              ),
            ),
          );
          _firstBody.close();
        }),
      );
      return AiTransportResponse(
        statusCode: 200,
        headers: const {},
        body: _firstBody.stream,
      );
    }
    // 第二轮起：模拟模型基于“继续”指令返回接续内容。
    final event = {
      'choices': [
        {
          'delta': {'content': 'resumed answer'},
          'finish_reason': 'stop',
        },
      ],
    };
    return AiTransportResponse(
      statusCode: 200,
      headers: const {},
      body: Stream.value(
        utf8.encode('data: ${jsonEncode(event)}\n\ndata: [DONE]\n\n'),
      ),
    );
  }
}

class _TextTransport implements AiTransport {
  _TextTransport(this.responses);

  final List<String> responses;
  var _index = 0;

  @override
  Future<AiTransportResponse> send(
    PreparedAiRequest request, {
    required AiCancellationToken cancellation,
  }) async {
    final text = responses[_index++];
    final event = {
      'choices': [
        {
          'delta': {'content': text},
          'finish_reason': 'stop',
        },
      ],
    };
    return AiTransportResponse(
      statusCode: 200,
      headers: const {},
      body: Stream.value(
        utf8.encode('data: ${jsonEncode(event)}\n\ndata: [DONE]\n\n'),
      ),
    );
  }
}

class _FakeToolExecutor implements AiToolExecutor {
  const _FakeToolExecutor();

  @override
  Future<AiToolResult> execute(
    AiToolCall call, {
    AiToolProgress? onProgress,
  }) async {
    return AiToolResult(
      toolCallId: call.id,
      name: call.name,
      success: true,
      content: 'manifest-data',
    );
  }
}

class _ThrowingToolExecutor implements AiToolExecutor {
  const _ThrowingToolExecutor();

  @override
  Future<AiToolResult> execute(
    AiToolCall call, {
    AiToolProgress? onProgress,
  }) async {
    throw StateError('boom');
  }
}

class _FlakyToolExecutor implements AiToolExecutor {
  var calls = 0;

  @override
  Future<AiToolResult> execute(
    AiToolCall call, {
    AiToolProgress? onProgress,
  }) async {
    calls++;
    if (calls == 1) {
      throw StateError('temporary boom');
    }
    return AiToolResult(
      toolCallId: call.id,
      name: call.name,
      success: true,
      content: 'manifest-data-after-retry',
    );
  }
}

Future<void> _waitUntil(bool Function() predicate) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Condition was not reached before timeout');
}
