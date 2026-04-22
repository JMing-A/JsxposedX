import 'package:JsxposedX/features/ai/domain/contracts/ai_chat_environment_adapter.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_chat_environment_snapshot.dart';
import 'package:JsxposedX/features/ai/presentation/providers/runtime/ai_chat_runtime_provider.dart';

Future<void> initializeAiChatEnvironment({
  required AiChatRuntime notifier,
  required AiChatEnvironmentAdapter environment,
  String initErrorPrefix = 'AI 会话初始化失败',
  void Function(AiChatEnvironmentSnapshot snapshot)? onSnapshotReady,
}) async {
  notifier.beginSessionInitialization();
  try {
    final snapshot = await environment.initialize();
    notifier.applyEnvironmentSnapshot(snapshot);
    onSnapshotReady?.call(snapshot);
  } catch (error) {
    notifier.markSessionInitFailed('$initErrorPrefix：$error');
  }
}
