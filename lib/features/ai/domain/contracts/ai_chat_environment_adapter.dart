import 'package:JsxposedX/features/ai/domain/models/ai_chat_environment_snapshot.dart';

abstract class AiChatEnvironmentAdapter {
  String get scopeId;

  Future<AiChatEnvironmentSnapshot> initialize();

  Future<void> dispose();
}
