import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:JsxposedX/features/ai/application/chat/ai_transport_trace.dart';

part 'ai_system_models.freezed.dart';

enum AiMessageRole { system, user, assistant, tool }

enum AiMessageStatus {
  draft,
  queued,
  streaming,
  completed,
  failed,
  cancelled,
  interrupted,
}

enum AiContextMode { tokenBudget, recentMessages, fullHistory }

enum AiToolApprovalMode { never, riskyOnly, always }

enum AiFinishReason {
  stop,
  length,
  toolCall,
  contentFilter,
  cancelled,
  unknown,
}

enum AiEndpointKind { chatCompletions, responses, messages, models }

enum AiAuthScheme { bearer, apiKeyHeader, queryParameter, oauth, none }

enum AiFailureCode {
  invalidConfiguration,
  credentialMissing,
  authenticationFailed,
  permissionDenied,
  modelNotFound,
  unsupportedCapability,
  contextLimitExceeded,
  rateLimited,
  quotaExceeded,
  networkUnavailable,
  connectTimeout,
  receiveTimeout,
  protocolMalformed,
  protocolTruncated,
  serverFailure,
  toolRejected,
  toolFailed,
  cancelled,
  unknown,
}

@freezed
sealed class AiContentPart with _$AiContentPart {
  const factory AiContentPart.text(String text) = AiTextPart;
  const factory AiContentPart.reasoning(String text) = AiReasoningPart;
  const factory AiContentPart.image({required String attachmentId}) =
      AiImagePart;
  const factory AiContentPart.toolCall({required AiToolCall toolCall}) =
      AiToolCallPart;
  const factory AiContentPart.toolResult({required AiToolResult toolResult}) =
      AiToolResultPart;
}

@freezed
abstract class AiToolCall with _$AiToolCall {
  const factory AiToolCall({
    required String id,
    required String name,
    required Map<String, Object?> arguments,
  }) = _AiToolCall;
}

@freezed
abstract class AiToolResult with _$AiToolResult {
  const factory AiToolResult({
    required String toolCallId,
    required String name,
    required bool success,
    required String content,
  }) = _AiToolResult;
}

@freezed
abstract class AiToolSpec with _$AiToolSpec {
  const factory AiToolSpec({
    required String name,
    required String description,
    required Map<String, Object?> inputSchema,
  }) = _AiToolSpec;
}

@freezed
abstract class AiMessage with _$AiMessage {
  const factory AiMessage({
    required String id,
    required String conversationId,
    required AiMessageRole role,
    required List<AiContentPart> parts,
    @Default(AiMessageStatus.completed) AiMessageStatus status,
    AiUsage? usage,
    AiFailure? failure,
    AiTransportTrace? transportTrace,
    String? parentId,
    required DateTime createdAt,
    DateTime? completedAt,
  }) = _AiMessage;
}

@freezed
abstract class AiGenerationOptions with _$AiGenerationOptions {
  const factory AiGenerationOptions({
    int? maxOutputTokens,
    double? temperature,
    double? topP,
    double? presencePenalty,
    double? frequencyPenalty,
    String? reasoningEffort,
    @Default(true) bool stream,
  }) = _AiGenerationOptions;
}

@freezed
abstract class AiModelCapabilities with _$AiModelCapabilities {
  const factory AiModelCapabilities({
    @Default(false) bool streaming,
    @Default(false) bool visionInput,
    @Default(false) bool fileInput,
    @Default(false) bool reasoning,
    @Default(false) bool toolCalling,
    @Default(false) bool parallelToolCalling,
    @Default(false) bool structuredOutput,
    @Default(true) bool systemRole,
  }) = _AiModelCapabilities;
}

@freezed
abstract class AiModelLimits with _$AiModelLimits {
  const factory AiModelLimits({
    int? contextTokens,
    int? maxOutputTokens,
    int? maxImages,
    int? maxTools,
    int? maxToolResultBytes,
  }) = _AiModelLimits;
}

@freezed
abstract class AiModelDefinition with _$AiModelDefinition {
  const factory AiModelDefinition({
    required String id,
    required String connectionId,
    required String displayName,
    required AiModelCapabilities capabilities,
    required AiModelLimits limits,
    @Default('discovered') String source,
  }) = _AiModelDefinition;
}

@freezed
abstract class AiProviderDefinition with _$AiProviderDefinition {
  const factory AiProviderDefinition({
    required String id,
    required String displayName,
    required String adapterId,
    @Default(AiAuthScheme.bearer) AiAuthScheme authScheme,
    String? authParameterName,
  }) = _AiProviderDefinition;
}

@freezed
abstract class AiProviderConnection with _$AiProviderConnection {
  const factory AiProviderConnection({
    required String id,
    required String providerId,
    required String displayName,
    required Uri baseUri,
    String? credentialRef,
    @Default(<AiEndpointKind, Uri>{})
    Map<AiEndpointKind, Uri> endpointOverrides,
    @Default(<String, String>{}) Map<String, String> customHeaders,
    @Default(<String, Object?>{}) Map<String, Object?> adapterOptions,
    @Default(true) bool enabled,
  }) = _AiProviderConnection;
}

@freezed
abstract class AiContextPolicy with _$AiContextPolicy {
  const factory AiContextPolicy({
    @Default(AiContextMode.tokenBudget) AiContextMode mode,
    @Default(1024) int reservedOutputTokens,
    @Default(4) int recentMessageMinimum,
    int? recentMessageLimit,
    @Default(true) bool includeToolResults,
    @Default(false) bool enableSummarization,
  }) = _AiContextPolicy;
}

/// 每轮用户消息可用的工具调用轮数预算。
///
/// 逆向场景单轮任务常需要 10 次以上工具调用（检索类名 → 反编译 → 生成
/// Hook → 校验脚本），历史默认值 8 偏小，会在任务中途触发上限终止。
/// 因此上调默认值，同时限定上限避免配置异常导致无限调用。
const int kDefaultMaxToolRounds = 24;

/// 合法区间下界：至少允许一轮工具调用，否则所有工具调用都会立即被判为
/// 超限，等于静默禁用工具调用。
const int kMinMaxToolRounds = 1;
const int kMaxMaxToolRounds = 32;

/// 历史默认值：早期版本 toolPolicy.maxRounds 默认为 8。读取配置时把仍然
/// 停留在该值的项视为“未调整过”，解析为新默认值，让存量配置无需手动修改
/// 即可获得修复；用户显式配置的其他数值保持原样。
const int kLegacyDefaultMaxToolRounds = 8;

/// 解析工具调用轮数配置：非正值与历史默认值回落到 [kDefaultMaxToolRounds]，
/// 其余取值收敛到 [kMinMaxToolRounds]~[kMaxMaxToolRounds]。
int resolveMaxToolRounds(int configured) {
  if (configured <= 0 || configured == kLegacyDefaultMaxToolRounds) {
    return kDefaultMaxToolRounds;
  }
  return configured.clamp(kMinMaxToolRounds, kMaxMaxToolRounds);
}

@freezed
abstract class AiToolPolicy with _$AiToolPolicy {
  const factory AiToolPolicy({
    @Default(AiToolApprovalMode.riskyOnly) AiToolApprovalMode approvalMode,
    @Default(kDefaultMaxToolRounds) int maxRounds,
    @Default(1024 * 1024) int maxResultBytes,
  }) = _AiToolPolicy;
}

@freezed
abstract class AiAssistantProfile with _$AiAssistantProfile {
  const factory AiAssistantProfile({
    required String id,
    required String name,
    required String connectionId,
    required String modelId,
    String? systemPrompt,
    @Default(AiGenerationOptions()) AiGenerationOptions generation,
    @Default(AiContextPolicy()) AiContextPolicy contextPolicy,
    @Default(AiToolPolicy()) AiToolPolicy toolPolicy,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _AiAssistantProfile;
}

@freezed
abstract class AiConversation with _$AiConversation {
  const factory AiConversation({
    required String id,
    required String title,
    required String assistantId,
    @Default('general') String environmentId,
    String? scopeId,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? archivedAt,
  }) = _AiConversation;
}

@freezed
abstract class AiRequest with _$AiRequest {
  const factory AiRequest({
    required String requestId,
    required AiProviderConnection connection,
    required AiModelDefinition model,
    required List<AiMessage> messages,
    @Default(AiGenerationOptions()) AiGenerationOptions options,
    @Default(<AiToolSpec>[]) List<AiToolSpec> tools,
  }) = _AiRequest;
}

@freezed
abstract class AiUsage with _$AiUsage {
  const factory AiUsage({
    @Default(0) int inputTokens,
    @Default(0) int outputTokens,
    @Default(0) int totalTokens,
  }) = _AiUsage;
}

@freezed
abstract class AiFailure with _$AiFailure {
  const factory AiFailure({
    required AiFailureCode code,
    required String messageKey,
    @Default(false) bool retryable,
    int? httpStatus,
    String? providerRequestId,
    String? detail,
  }) = _AiFailure;
}
