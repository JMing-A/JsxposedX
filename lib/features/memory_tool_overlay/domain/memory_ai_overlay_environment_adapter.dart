import 'package:JsxposedX/features/ai/domain/contracts/ai_chat_environment_adapter.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_chat_environment_snapshot.dart';
import 'package:JsxposedX/generated/memory_tool.g.dart';

class MemoryAiOverlayEnvironmentAdapter implements AiChatEnvironmentAdapter {
  const MemoryAiOverlayEnvironmentAdapter({
    required this.processInfo,
    required this.isZh,
  });

  final ProcessInfo processInfo;
  final bool isZh;

  @override
  String get scopeId => 'memory_overlay_${processInfo.packageName}_${processInfo.pid}';

  @override
  Future<AiChatEnvironmentSnapshot> initialize() async {
    final systemPrompt = isZh
        ? '你是内存调试助手。当前目标进程如下：\n'
              '- 进程名：${processInfo.name}\n'
              '- 包名：${processInfo.packageName}\n'
              '- PID：${processInfo.pid}\n\n'
              '你的职责是帮助用户理解当前进程内存搜索、结果筛选、断点调试和地址分析流程。'
              '第一阶段你只做解释、建议和步骤整理，不主动假设你拥有读写内存或自动执行工具的能力。'
        : 'You are a memory debugging assistant.\n'
              'Current target process:\n'
              '- Process: ${processInfo.name}\n'
              '- Package: ${processInfo.packageName}\n'
              '- PID: ${processInfo.pid}\n\n'
              'Help the user understand memory search, narrowing, breakpoint debugging, and address analysis. '
              'In phase one, focus on explanation and next-step guidance without assuming tool execution ability.';

    return AiChatEnvironmentSnapshot.ready(
      scopeId: scopeId,
      systemPrompt: systemPrompt,
    );
  }

  @override
  Future<void> dispose() async {}
}
