import 'dart:async';
import 'dart:convert';

import 'package:JsxposedX/features/ai/application/chat/ai_chat_context_builder.dart';
import 'package:JsxposedX/features/ai/application/chat/ai_chat_session_environment.dart';
import 'package:JsxposedX/features/ai/application/chat/ai_chat_orchestrator.dart';
import 'package:JsxposedX/features/ai/application/chat/ai_chat_session_state.dart';
import 'package:JsxposedX/features/ai/application/chat/ai_stream_snapshot.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_system_models.dart';
import 'package:JsxposedX/features/ai/domain/repositories/ai_catalog_repository.dart';
import 'package:JsxposedX/features/ai/domain/repositories/ai_conversation_repository.dart';

class AiChatSessionController {
  AiChatSessionController({
    required this.conversationId,
    required AiCatalogRepository catalogRepository,
    required AiConversationRepository conversationRepository,
    required AiChatRun Function(AiRequest request) startRun,
    required String Function() idFactory,
    DateTime Function()? now,
    AiChatContextBuilder contextBuilder = const AiChatContextBuilder(),
    this.environment,
    this.pageSize = 50,
    this.checkpointInterval = const Duration(milliseconds: 300),
  }) : _catalogRepository = catalogRepository,
       _conversationRepository = conversationRepository,
       _startRun = startRun,
       _idFactory = idFactory,
       _now = now ?? DateTime.now,
       _contextBuilder = contextBuilder,
       _state = AiChatSessionState(conversationId: conversationId);

  final String conversationId;
  final int pageSize;
  final Duration checkpointInterval;
  final AiChatSessionEnvironment? environment;
  final AiCatalogRepository _catalogRepository;
  final AiConversationRepository _conversationRepository;
  final AiChatRun Function(AiRequest request) _startRun;
  final String Function() _idFactory;
  final DateTime Function() _now;
  final AiChatContextBuilder _contextBuilder;
  final StreamController<AiChatSessionState> _states =
      StreamController<AiChatSessionState>.broadcast(sync: true);

  AiChatSessionState _state;
  AiChatRun? _activeRun;
  StreamSubscription<AiStreamSnapshot>? _runSubscription;
  Timer? _checkpointTimer;
  AiStreamSnapshot? _pendingCheckpointSnapshot;
  Future<void> _checkpointTail = Future.value();
  Future<void>? _initialization;
  bool _closed = false;
  Completer<bool>? _approvalCompleter;
  AiMessage? _pendingApprovalAssistantMessage;

  AiChatSessionState get state => _state;

  Stream<AiChatSessionState> get states => _states.stream;

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    final conversation = await _conversationRepository.getConversation(
      conversationId,
    );
    if (conversation == null) {
      throw StateError('Conversation $conversationId does not exist');
    }
    final assistant = await _catalogRepository.getAssistant(
      conversation.assistantId,
    );
    if (assistant == null) {
      throw StateError(
        'Conversation $conversationId references a missing assistant',
      );
    }
    final connection = await _catalogRepository.getConnection(
      assistant.connectionId,
    );
    final model = await _catalogRepository.getModel(
      assistant.connectionId,
      assistant.modelId,
    );
    if (connection == null || model == null) {
      throw StateError('Assistant ${assistant.id} has an invalid catalog link');
    }

    final loaded = await _conversationRepository.getMessages(
      conversationId,
      limit: pageSize + 1,
    );
    final hasOlder = loaded.length > pageSize;
    final page = hasOlder ? loaded.sublist(loaded.length - pageSize) : loaded;
    final repaired = await _repairInterruptedMessages(page);
    _emit(
      _state.copyWith(
        conversation: conversation,
        assistant: assistant,
        connection: connection,
        model: model,
        messages: repaired,
        phase: AiChatSessionPhase.ready,
        hasOlderMessages: hasOlder,
        failure: null,
      ),
    );
  }

  Future<void> loadOlderMessages() async {
    await initialize();
    if (_state.isLoadingOlderMessages || !_state.hasOlderMessages) return;
    final oldest = _state.messages.firstOrNull;
    if (oldest == null) return;
    _emit(_state.copyWith(isLoadingOlderMessages: true));
    try {
      final loaded = await _conversationRepository.getMessages(
        conversationId,
        before: AiMessageCursor(createdAt: oldest.createdAt, id: oldest.id),
        limit: pageSize + 1,
      );
      final hasOlder = loaded.length > pageSize;
      final page = hasOlder ? loaded.sublist(loaded.length - pageSize) : loaded;
      _emit(
        _state.copyWith(
          messages: [...page, ..._state.messages],
          hasOlderMessages: hasOlder,
          isLoadingOlderMessages: false,
        ),
      );
    } catch (_) {
      _emit(_state.copyWith(isLoadingOlderMessages: false));
      rethrow;
    }
  }

  Future<void> sendText(String text) async {
    await initialize();
    final content = text.trim();
    if (content.isEmpty) return;
    _ensureCanStart();
    final createdAt = _now().toUtc();
    final userMessage = AiMessage(
      id: _idFactory(),
      conversationId: conversationId,
      role: AiMessageRole.user,
      parts: [AiContentPart.text(content)],
      parentId: _state.messages.lastOrNull?.id,
      createdAt: createdAt,
    );
    await _startGeneration(userMessage, [
      ..._state.messages,
      userMessage,
    ], persistUserMessage: true);
  }

  /// 中断后的非破坏性接续：保留全部历史消息（含工具调用与部分回复），
  /// 追加一条与当前语言匹配的“继续”指令，基于中断前的上下文继续推进任务，
  /// 而不是回退到会话起始状态重新生成。
  Future<void> continueFromInterruption({required bool isZh}) async {
    await initialize();
    _ensureCanStart();
    final keyword = isZh ? '继续' : 'Continue';
    final createdAt = _now().toUtc();
    final userMessage = AiMessage(
      id: _idFactory(),
      conversationId: conversationId,
      role: AiMessageRole.user,
      parts: [AiContentPart.text(keyword)],
      parentId: _state.messages.lastOrNull?.id,
      createdAt: createdAt,
    );
    await _startGeneration(userMessage, [
      ..._state.messages,
      userMessage,
    ], persistUserMessage: true);
  }

  Future<void> retryLastResponse({bool isZh = true}) async {
    await initialize();
    _ensureCanStart();
    final hasInterrupted = _state.messages.any(
      (message) =>
          message.role == AiMessageRole.assistant && _isResumable(message),
    );
    if (!hasInterrupted) {
      throw StateError('There is no failed response to retry');
    }
    // 中断后的重试不再回退会话，改为发送“继续”指令接续推进。
    await continueFromInterruption(isZh: isZh);
  }

  Future<void> retryByMessageId(String messageId, {bool isZh = true}) async {
    await initialize();
    _ensureCanStart();
    final index = _state.messages.indexWhere(
      (message) => message.id == messageId,
    );
    if (index < 0) return;
    final target = _state.messages[index];
    if (target.role == AiMessageRole.tool &&
        target.parts.whereType<AiToolResultPart>().any(
          (part) => !part.toolResult.success,
        )) {
      await _retryFailedToolResult(index);
      return;
    }
    // 中断/取消/失败的 assistant 轮次：保留既有上下文，
    // 以“继续”指令接续推进，避免会话跳回初始消息。
    if (target.role == AiMessageRole.assistant && _isResumable(target)) {
      await continueFromInterruption(isZh: isZh);
      return;
    }
    if (target.role == AiMessageRole.user) {
      await _regenerateFrom(target);
      return;
    }
    final userMessage = _findUserMessageBefore(index);
    if (userMessage == null) {
      throw StateError('The response has no user parent');
    }
    await _regenerateFrom(userMessage);
  }

  Future<void> regenerateLastResponse() async {
    await initialize();
    _ensureCanStart();
    final assistantIndex = _state.messages.lastIndexWhere(
      (message) => message.role == AiMessageRole.assistant,
    );
    if (assistantIndex <= 0) {
      throw StateError('There is no response to regenerate');
    }
    final userMessage = _findUserMessageBefore(assistantIndex);
    if (userMessage == null) {
      throw StateError('The response has no user parent');
    }
    await _regenerateFrom(userMessage);
  }

  /// Removes one persisted message. Conversation structure is never mutated
  /// while a request is active; callers should provide a confirmation UI.
  Future<void> deleteMessage(String messageId) async {
    await initialize();
    _ensureCanStart();
    final index = _state.messages.indexWhere(
      (message) => message.id == messageId,
    );
    if (index < 0) return;
    await _conversationRepository.deleteMessagesById(conversationId, [
      messageId,
    ]);
    final messages = [..._state.messages]..removeAt(index);
    _emit(_state.copyWith(messages: messages, failure: null));
  }

  /// Clears an assistant turn without deleting its user parent.
  Future<void> clearAssistantResponse(String messageId) async {
    await initialize();
    _ensureCanStart();
    final message = _state.messages.firstWhere(
      (candidate) => candidate.id == messageId,
      orElse: () => throw StateError('Message $messageId does not exist'),
    );
    if (message.role != AiMessageRole.assistant) return;
    await deleteMessage(messageId);
  }

  /// 以非破坏性方式接续被中断的 assistant 轮次：不删除任何历史消息，
  /// 发送与当前语言匹配的“继续”指令，基于中断前的上下文继续推进任务。
  Future<void> continueGeneration(String messageId, {bool isZh = true}) async {
    await initialize();
    _ensureCanStart();
    final index = _state.messages.indexWhere(
      (message) => message.id == messageId,
    );
    if (index < 0) return;
    final target = _state.messages[index];
    if (target.role != AiMessageRole.assistant ||
        (target.status != AiMessageStatus.cancelled &&
            target.status != AiMessageStatus.interrupted)) {
      throw StateError('Message is not resumable');
    }
    await continueFromInterruption(isZh: isZh);
  }

  static bool _isResumable(AiMessage message) {
    return message.status == AiMessageStatus.failed ||
        message.status == AiMessageStatus.cancelled ||
        message.status == AiMessageStatus.interrupted;
  }

  Future<void> editUserMessageAndResend({
    required String messageId,
    required String updatedText,
  }) async {
    await initialize();
    _ensureCanStart();
    final index = _state.messages.indexWhere(
      (message) =>
          message.id == messageId && message.role == AiMessageRole.user,
    );
    if (index < 0 || updatedText.trim().isEmpty) return;
    final original = _state.messages[index];
    final updated = original.copyWith(
      parts: original.parts
          .map(
            (part) => part is AiTextPart
                ? AiContentPart.text(updatedText.trim())
                : part,
          )
          .toList(growable: false),
    );
    await _regenerateFrom(updated);
  }

  Future<void> _regenerateFrom(AiMessage userMessage) async {
    final discardedIds = _state.messages
        .skipWhile((message) => message.id != userMessage.id)
        .skip(1)
        .map((message) => message.id);
    await _conversationRepository.deleteMessagesById(
      conversationId,
      discardedIds,
    );
    // A retry writes the same record again, while an edited resend replaces
    // the persisted user content before the new assistant turn starts.
    await _conversationRepository.saveMessage(userMessage);
    final history =
        _state.messages
            .takeWhile((message) => message.id != userMessage.id)
            .toList(growable: true)
          ..add(userMessage);
    _emit(_state.copyWith(messages: history));
    await _startGeneration(userMessage, history);
  }

  AiMessage? _findUserMessageBefore(int index) {
    for (var candidate = index - 1; candidate >= 0; candidate--) {
      final message = _state.messages[candidate];
      if (message.role == AiMessageRole.user) return message;
    }
    return null;
  }

  Future<void> _startGeneration(
    AiMessage userMessage,
    List<AiMessage> history, {
    bool persistUserMessage = false,
  }) async {
    if (persistUserMessage) {
      await _conversationRepository.saveMessage(userMessage);
    }

    await _runAssistantLoop(
      initialHistory: history,
      initialParentId: userMessage.id,
    );
  }

  Future<void> _retryFailedToolResult(int resultIndex) async {
    final resultMessage = _state.messages[resultIndex];
    final failedResult = resultMessage.parts
        .whereType<AiToolResultPart>()
        .map((part) => part.toolResult)
        .firstWhere(
          (result) => !result.success,
          orElse: () => throw StateError('Message has no failed tool result'),
        );
    final toolCall = _findToolCallBefore(resultIndex, failedResult.toolCallId);
    if (toolCall == null) {
      throw StateError('The failed tool result has no matching tool call');
    }
    if (environment?.toolExecutor == null) {
      throw StateError('No tool executor is available for this conversation');
    }

    final discardedIds = _state.messages
        .skip(resultIndex)
        .map((message) => message.id);
    await _conversationRepository.deleteMessagesById(
      conversationId,
      discardedIds,
    );
    final history = _state.messages.take(resultIndex).toList(growable: true);
    _emit(
      _state.copyWith(
        messages: history,
        phase: AiChatSessionPhase.requesting,
        failure: null,
      ),
    );

    final previous = history.lastOrNull;
    final toolMessage = await _executeToolCall(
      toolCall,
      maxResultBytes: _state.assistant!.toolPolicy.maxResultBytes,
      parentId: previous?.id,
      previousTime: previous?.completedAt ?? previous?.createdAt ?? _now(),
    );
    await _runAssistantLoop(
      initialHistory: [...history, toolMessage],
      initialParentId: toolMessage.id,
      startingToolRound: _toolRoundsIn(history),
    );
  }

  AiToolCall? _findToolCallBefore(int index, String toolCallId) {
    for (var candidate = index - 1; candidate >= 0; candidate--) {
      final message = _state.messages[candidate];
      if (message.role != AiMessageRole.assistant) continue;
      for (final part in message.parts.whereType<AiToolCallPart>()) {
        if (part.toolCall.id == toolCallId) return part.toolCall;
      }
    }
    return null;
  }

  int _toolRoundsIn(List<AiMessage> messages) {
    return messages
        .where(
          (message) =>
              message.role == AiMessageRole.assistant &&
              message.parts.whereType<AiToolCallPart>().isNotEmpty,
        )
        .length;
  }

  Future<void> _runAssistantLoop({
    required List<AiMessage> initialHistory,
    required String initialParentId,
    int startingToolRound = 0,
  }) async {
    final assistant = _state.assistant!;
    final connection = _state.connection!;
    final model = _state.model!;
    var workingHistory = List<AiMessage>.from(initialHistory);
    var parentId = initialParentId;
    final tools = model.capabilities.toolCalling
        ? environment?.tools ?? const <AiToolSpec>[]
        : const <AiToolSpec>[];
    final maxToolRounds = assistant.toolPolicy.maxRounds.clamp(0, 32);

    for (var toolRound = startingToolRound; ; toolRound++) {
      final requestId = _idFactory();
      final assistantMessageId = _idFactory();
      final previousTime =
          workingHistory.lastOrNull?.createdAt ?? _now().toUtc();
      final currentTime = _now().toUtc();
      final assistantCreatedAt = currentTime.isAfter(previousTime)
          ? currentTime
          : previousTime.add(const Duration(microseconds: 1));
      final placeholder = AiMessage(
        id: assistantMessageId,
        conversationId: conversationId,
        role: AiMessageRole.assistant,
        parts: const [],
        status: AiMessageStatus.queued,
        parentId: parentId,
        createdAt: assistantCreatedAt,
      );
      await _conversationRepository.saveMessage(placeholder);
      final visibleMessages = [...workingHistory, placeholder];
      final requestMessages = _contextBuilder.build(
        assistant: assistant,
        model: model,
        messages: workingHistory,
        idFactory: _idFactory,
        now: currentTime,
        environmentSystemPrompt: environment?.systemPrompt,
      );
      final request = AiRequest(
        requestId: requestId,
        connection: connection,
        model: model,
        messages: requestMessages,
        options: assistant.generation.copyWith(
          stream: assistant.generation.stream && model.capabilities.streaming,
        ),
        tools: tools,
      );

      _emit(
        _state.copyWith(
          messages: visibleMessages,
          phase: AiChatSessionPhase.requesting,
          activeRequestId: requestId,
          activeAssistantMessageId: assistantMessageId,
          runSnapshot: AiStreamSnapshot(requestId: requestId),
          failure: null,
        ),
      );
      final run = _startRun(request);
      _activeRun = run;
      _runSubscription = run.snapshots.listen(
        (snapshot) => _handleSnapshot(snapshot, placeholder),
      );

      var finalSnapshot = await run.completed;
      await _runSubscription?.cancel();
      _runSubscription = null;
      _activeRun = null;
      if (finalSnapshot.status != AiStreamStatus.completed &&
          finalSnapshot.status != AiStreamStatus.failed) {
        finalSnapshot = finalSnapshot.copyWith(
          status: AiStreamStatus.failed,
          failure: const AiFailure(
            code: AiFailureCode.protocolTruncated,
            messageKey: 'ai.error.protocolTruncated',
            retryable: true,
          ),
        );
      }

      final hasToolCalls =
          finalSnapshot.status == AiStreamStatus.completed &&
          finalSnapshot.toolCalls.isNotEmpty;
      if (!hasToolCalls) {
        await _finishRun(finalSnapshot, placeholder);
        return;
      }
      final invalidToolCall = finalSnapshot.toolCalls.firstWhere(
        (call) =>
            call.id == null ||
            call.id!.trim().isEmpty ||
            call.name.trim().isEmpty,
        orElse: () => const AiToolCallSnapshot(index: -1),
      );
      if (invalidToolCall.index >= 0) {
        await _finishRun(
          finalSnapshot.copyWith(
            status: AiStreamStatus.failed,
            failure: AiFailure(
              code: AiFailureCode.protocolMalformed,
              messageKey:
                  'Responses tool call ${invalidToolCall.index} is missing call_id or name',
            ),
          ),
          placeholder,
        );
        return;
      }
      if (toolRound >= maxToolRounds || environment?.toolExecutor == null) {
        await _finishRun(
          finalSnapshot.copyWith(
            status: AiStreamStatus.failed,
            failure: const AiFailure(
              code: AiFailureCode.toolFailed,
              messageKey: 'ai.error.toolRoundsExceeded',
            ),
          ),
          placeholder,
        );
        return;
      }

      final assistantMessage = await _persistCompletedToolCall(
        finalSnapshot,
        placeholder,
      );
      workingHistory = [...workingHistory, assistantMessage];

      final needsApproval = _needsToolApproval(assistant.toolPolicy, assistantMessage);
      if (needsApproval) {
        _emit(
          _state.copyWith(
            messages: workingHistory,
            phase: AiChatSessionPhase.awaitingToolApproval,
            activeRequestId: null,
            activeAssistantMessageId: null,
            runSnapshot: null,
          ),
        );
        _pendingApprovalAssistantMessage = assistantMessage;
        _approvalCompleter = Completer<bool>();
        final approved = await _approvalCompleter!.future;
        _approvalCompleter = null;
        _pendingApprovalAssistantMessage = null;

        if (!approved) {
          final rejectionMessages = _createRejectedToolResults(
            assistantMessage,
            assistant.toolPolicy.maxResultBytes,
          );
          workingHistory = [...workingHistory, ...rejectionMessages];
          parentId = rejectionMessages.lastOrNull?.id ?? assistantMessage.id;
          _emit(
            _state.copyWith(
              messages: workingHistory,
              phase: AiChatSessionPhase.requesting,
              activeRequestId: null,
              activeAssistantMessageId: null,
              runSnapshot: null,
            ),
          );
          continue;
        }
      }

      _emit(
        _state.copyWith(
          messages: workingHistory,
          phase: AiChatSessionPhase.requesting,
          activeRequestId: null,
          activeAssistantMessageId: null,
          runSnapshot: null,
        ),
      );
      final toolMessages = await _executeToolCalls(
        assistantMessage,
        assistant.toolPolicy.maxResultBytes,
      );
      workingHistory = [...workingHistory, ...toolMessages];
      parentId = toolMessages.lastOrNull?.id ?? assistantMessage.id;
      _emit(
        _state.copyWith(
          messages: workingHistory,
          phase: AiChatSessionPhase.requesting,
          activeRequestId: null,
          activeAssistantMessageId: null,
          runSnapshot: null,
        ),
      );
    }
  }

  Future<AiMessage> _persistCompletedToolCall(
    AiStreamSnapshot snapshot,
    AiMessage placeholder,
  ) async {
    _checkpointTimer?.cancel();
    _checkpointTimer = null;
    _pendingCheckpointSnapshot = null;
    await _checkpointTail;
    final message = _messageFromSnapshot(
      snapshot,
      placeholder,
      completedAt: _now().toUtc(),
    );
    await _conversationRepository.saveMessage(message);
    return message;
  }

  Future<List<AiMessage>> _executeToolCalls(
    AiMessage assistantMessage,
    int maxResultBytes,
  ) async {
    final results = <AiMessage>[];
    var previousTime =
        assistantMessage.completedAt ?? assistantMessage.createdAt;
    String? parentId = assistantMessage.id;
    for (final part in assistantMessage.parts.whereType<AiToolCallPart>()) {
      final message = await _executeToolCall(
        part.toolCall,
        maxResultBytes: maxResultBytes,
        parentId: parentId,
        previousTime: previousTime,
      );
      results.add(message);
      parentId = message.id;
      previousTime = message.completedAt ?? message.createdAt;
    }
    return results;
  }

  Future<AiMessage> _executeToolCall(
    AiToolCall toolCall, {
    required int maxResultBytes,
    required String? parentId,
    required DateTime previousTime,
  }) async {
    final executor = environment!.toolExecutor!;
    AiToolResult rawResult;
    try {
      rawResult = await executor.execute(
        toolCall,
        onProgress: (progress) {
          _sendToolProgress(toolCall.id, progress);
        },
      );
    } catch (error) {
      rawResult = AiToolResult(
        toolCallId: toolCall.id,
        name: toolCall.name,
        success: false,
        content: 'Tool execution failed: $error',
      );
    }
    final content = _truncateUtf8Like(rawResult.content, maxResultBytes);
    final now = _now().toUtc();
    final createdAt = now.isAfter(previousTime)
        ? now
        : previousTime.add(const Duration(microseconds: 1));
    final message = AiMessage(
      id: _idFactory(),
      conversationId: conversationId,
      role: AiMessageRole.tool,
      parts: [
        AiContentPart.toolResult(
          toolResult: rawResult.copyWith(content: content),
        ),
      ],
      parentId: parentId,
      createdAt: createdAt,
      completedAt: createdAt,
    );
    await _conversationRepository.saveMessage(message);
    _emit(
      _state.copyWith(
        messages: [..._state.messages, message],
        phase: AiChatSessionPhase.requesting,
      ),
    );
    return message;
  }

  static String _truncateUtf8Like(String content, int maxBytes) {
    if (maxBytes <= 0 || content.length <= maxBytes) return content;
    return '${content.substring(0, maxBytes)}\n\n[tool result truncated]';
  }

  void _sendToolProgress(String toolCallId, String progress) {
    // 工具执行进度回调：可在后续版本中通过消息更新或独立进度卡片展示
    // 当前版本通过工具执行状态变更（preparing -> running -> succeeded/failed）来展示进度
  }

  bool _needsToolApproval(
    AiToolPolicy toolPolicy,
    AiMessage assistantMessage,
  ) {
    if (toolPolicy.approvalMode == AiToolApprovalMode.never) return false;
    if (toolPolicy.approvalMode == AiToolApprovalMode.always) return true;
    // riskyOnly: 仅当消息中包含危险工具时才需要审批
    // 优先使用用户自定义的危险工具列表，没有则用系统默认 isRisky 标记
    final toolDefs = environment?.toolDefinitions ?? const [];
    final riskyNames = toolDefs
        .where((d) => d.isRisky == true)
        .map((d) => d.name)
        .toSet();
    return assistantMessage.parts
        .whereType<AiToolCallPart>()
        .any((part) => riskyNames.contains(part.toolCall.name));
  }

  List<AiMessage> _createRejectedToolResults(
    AiMessage assistantMessage,
    int maxResultBytes,
  ) {
    final results = <AiMessage>[];
    var previousTime =
        assistantMessage.completedAt ?? assistantMessage.createdAt;
    String? parentId = assistantMessage.id;
    for (final part in assistantMessage.parts.whereType<AiToolCallPart>()) {
      final now = _now().toUtc();
      final createdAt = now.isAfter(previousTime)
          ? now
          : previousTime.add(const Duration(microseconds: 1));
      final message = AiMessage(
        id: _idFactory(),
        conversationId: conversationId,
        role: AiMessageRole.tool,
        parts: [
          AiContentPart.toolResult(
            toolResult: AiToolResult(
              toolCallId: part.toolCall.id,
              name: part.toolCall.name,
              success: false,
              content: '工具调用被用户拒绝',
            ),
          ),
        ],
        parentId: parentId,
        createdAt: createdAt,
        completedAt: createdAt,
      );
      results.add(message);
      parentId = message.id;
      previousTime = message.completedAt ?? message.createdAt;
    }
    return results;
  }

  /// 批准当前等待审批的所有工具调用
  void approvePendingTools() {
    final completer = _approvalCompleter;
    if (completer == null || completer.isCompleted) return;
    completer.complete(true);
  }

  /// 拒绝当前等待审批的所有工具调用
  void rejectPendingTools() {
    final completer = _approvalCompleter;
    if (completer == null || completer.isCompleted) return;
    completer.complete(false);
  }

  /// 是否有等待审批的工具调用
  bool get hasPendingToolApproval => _approvalCompleter != null && !_approvalCompleter!.isCompleted;

  void cancel() {
    // 如果有等待审批的工具，先拒绝它们
    final completer = _approvalCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete(false);
    }
    final run = _activeRun;
    if (run == null) return;
    _emit(_state.copyWith(phase: AiChatSessionPhase.cancelling));
    run.cancel();
  }

  void _handleSnapshot(AiStreamSnapshot snapshot, AiMessage placeholder) {
    if (snapshot.requestId != _state.activeRequestId || _closed) return;
    final phase = switch (snapshot.status) {
      AiStreamStatus.idle => AiChatSessionPhase.requesting,
      AiStreamStatus.streaming => AiChatSessionPhase.streaming,
      AiStreamStatus.completed => AiChatSessionPhase.streaming,
      AiStreamStatus.failed => AiChatSessionPhase.streaming,
    };
    _emit(_state.copyWith(phase: phase, runSnapshot: snapshot));
    if (snapshot.status == AiStreamStatus.streaming) {
      _scheduleCheckpoint(snapshot, placeholder);
    }
  }

  void _scheduleCheckpoint(AiStreamSnapshot snapshot, AiMessage placeholder) {
    _pendingCheckpointSnapshot = snapshot;
    if (_checkpointTimer != null) return;
    _checkpointTimer = Timer(checkpointInterval, () {
      _checkpointTimer = null;
      final pending = _pendingCheckpointSnapshot;
      _pendingCheckpointSnapshot = null;
      if (pending == null || pending.requestId != _state.activeRequestId) {
        return;
      }
      final checkpoint = _messageFromSnapshot(pending, placeholder);
      _checkpointTail = _checkpointTail
          .then((_) => _conversationRepository.saveMessage(checkpoint))
          .catchError((Object _) {});
    });
  }

  Future<void> _finishRun(
    AiStreamSnapshot snapshot,
    AiMessage placeholder,
  ) async {
    if (snapshot.requestId != _state.activeRequestId) return;
    _checkpointTimer?.cancel();
    _checkpointTimer = null;
    _pendingCheckpointSnapshot = null;
    await _checkpointTail;
    final finalMessage = _messageFromSnapshot(
      snapshot,
      placeholder,
      completedAt: _now().toUtc(),
    );
    await _conversationRepository.saveMessage(finalMessage);
    final conversation = _state.conversation!.copyWith(
      updatedAt: finalMessage.completedAt!,
    );
    await _conversationRepository.saveConversation(conversation);
    final updatedMessages = [
      for (final message in _state.messages)
        if (message.id == finalMessage.id) finalMessage else message,
    ];
    _activeRun = null;
    _emit(
      _state.copyWith(
        conversation: conversation,
        messages: updatedMessages,
        phase: finalMessage.status == AiMessageStatus.failed
            ? AiChatSessionPhase.failed
            : AiChatSessionPhase.ready,
        activeRequestId: null,
        activeAssistantMessageId: null,
        runSnapshot: null,
        failure: finalMessage.failure,
      ),
    );
  }

  AiMessage _messageFromSnapshot(
    AiStreamSnapshot snapshot,
    AiMessage placeholder, {
    DateTime? completedAt,
  }) {
    final parts = <AiContentPart>[
      if (snapshot.reasoning.isNotEmpty)
        AiContentPart.reasoning(snapshot.reasoning),
      if (snapshot.text.isNotEmpty) AiContentPart.text(snapshot.text),
      for (final call in snapshot.toolCalls)
        if (_decodeArguments(call.argumentsJson) case final arguments?)
          AiContentPart.toolCall(
            toolCall: AiToolCall(
              id: call.id ?? 'tool-${call.index}',
              name: call.name,
              arguments: arguments,
            ),
          ),
    ];
    final status = switch (snapshot.status) {
      AiStreamStatus.idle => AiMessageStatus.queued,
      AiStreamStatus.streaming => AiMessageStatus.streaming,
      AiStreamStatus.completed => AiMessageStatus.completed,
      AiStreamStatus.failed
          when snapshot.failure?.code == AiFailureCode.cancelled =>
        AiMessageStatus.cancelled,
      AiStreamStatus.failed => AiMessageStatus.failed,
    };
    return placeholder.copyWith(
      parts: parts,
      status: status,
      usage: snapshot.usage,
      failure: snapshot.failure,
      completedAt: completedAt,
    );
  }

  static Map<String, Object?>? _decodeArguments(String source) {
    if (source.isEmpty) return const {};
    try {
      final decoded = jsonDecode(source);
      return decoded is Map
          ? Map<String, Object?>.from(decoded)
          : <String, Object?>{'value': decoded};
    } on FormatException {
      return null;
    }
  }

  Future<List<AiMessage>> _repairInterruptedMessages(
    List<AiMessage> messages,
  ) async {
    final repaired = <AiMessage>[];
    final changed = <AiMessage>[];
    for (final message in messages) {
      if (message.status == AiMessageStatus.streaming ||
          message.status == AiMessageStatus.queued) {
        final replacement = message.copyWith(
          status: AiMessageStatus.interrupted,
          failure: const AiFailure(
            code: AiFailureCode.unknown,
            messageKey: 'ai.error.interrupted',
            retryable: true,
          ),
          completedAt: _now().toUtc(),
        );
        repaired.add(replacement);
        changed.add(replacement);
      } else {
        repaired.add(message);
      }
    }
    if (changed.isNotEmpty) {
      await _conversationRepository.saveMessages(changed);
    }
    return repaired;
  }

  void _ensureCanStart() {
    if (!_state.canSend || _activeRun != null) {
      throw StateError(
        'Conversation $conversationId already has an active run',
      );
    }
  }

  void _emit(AiChatSessionState next) {
    if (_closed) return;
    _state = next;
    _states.add(next);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _checkpointTimer?.cancel();
    _pendingCheckpointSnapshot = null;
    _approvalCompleter?.complete(false);
    _approvalCompleter = null;
    _pendingApprovalAssistantMessage = null;
    _activeRun?.cancel();
    await _runSubscription?.cancel();
    await _checkpointTail;
    await _states.close();
  }
}
