import 'package:JsxposedX/features/ai/domain/contracts/ai_chat_tool_executor_contract.dart';
import 'package:JsxposedX/features/ai/domain/contracts/ai_chat_tool_handler.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_tool_call.dart';

class ToolExecutor implements AiChatToolExecutorContract {
  ToolExecutor({
    required Iterable<AiChatToolHandler> handlers,
  }) : _handlers = {
         for (final handler in handlers) handler.toolName: handler,
       };

  final Map<String, AiChatToolHandler> _handlers;

  @override
  Future<AiToolResult> execute(
    AiToolCall call, {
    AiToolProgressCallback? onProgress,
  }) async {
    final handler = _handlers[call.name];
    if (handler == null) {
      return AiToolResult.error(call.id, call.name, '未知工具: ${call.name}');
    }

    try {
      final result = await handler.handle(call, onProgress: onProgress);
      return AiToolResult.ok(call.id, call.name, result);
    } catch (error) {
      return AiToolResult.error(call.id, call.name, error.toString());
    }
  }

  Future<List<AiToolResult>> executeAll(List<AiToolCall> calls) async {
    final results = <AiToolResult>[];
    for (final call in calls) {
      results.add(await execute(call));
    }
    return results;
  }
}
