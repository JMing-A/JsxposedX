import 'dart:convert';

/// AI 发起的工具调用请求
class AiToolCall {
  final String id;
  final String name;
  final Map<String, dynamic> arguments;

  const AiToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  factory AiToolCall.fromJson(Map<String, dynamic> json) => AiToolCall(
    id: json['id'] as String? ?? '',
    name: json['function']?['name'] as String? ?? json['name'] as String? ?? '',
    arguments: _parseArguments(json),
  );

  static Map<String, dynamic> _parseArguments(Map<String, dynamic> json) {
    final args = json['function']?['arguments'] ?? json['arguments'];
    if (args is String) {
      try {
        return Map<String, dynamic>.from(jsonDecode(args) as Map);
      } catch (_) {
        return {};
      }
    }
    if (args is Map) return Map<String, dynamic>.from(args);
    return {};
  }

  /// 取参数值的便捷方法
  String getString(String key, [String defaultValue = '']) =>
      arguments[key]?.toString() ?? defaultValue;

  int getInt(String key, [int defaultValue = 0]) =>
      int.tryParse(arguments[key]?.toString() ?? '') ?? defaultValue;

  List<String> getStringList(String key) {
    final val = arguments[key];
    if (val is List) return val.map((e) => e.toString()).toList();
    return [];
  }
}

/// 工具执行结果
class AiToolResult {
  final String toolCallId;
  final String toolName;
  final bool success;
  final String content;

  const AiToolResult({
    required this.toolCallId,
    required this.toolName,
    required this.success,
    required this.content,
  });

  /// 成功结果
  factory AiToolResult.ok(String toolCallId, String toolName, String content) =>
      AiToolResult(
        toolCallId: toolCallId,
        toolName: toolName,
        success: true,
        content: content,
        // content: _truncate(content, maxLength: 16000),
      );

  /// 失败结果
  factory AiToolResult.error(
    String toolCallId,
    String toolName,
    String error,
  ) => AiToolResult(
    toolCallId: toolCallId,
    toolName: toolName,
    success: false,
    content: error,
  );

  /// 截断过长的结果
  // static String _truncate(String text, {required int maxLength}) {
  //   if (text.length <= maxLength) return text;
  //   return '${text.substring(0, maxLength)}\n\n... [结果已截断，共 ${text.length} 字符，如需更多细节请指定具体方法或类名]';
  // }

  /// 转为 OpenAI tool message 格式
  Map<String, dynamic> toMessageJson() => {
    'role': 'tool',
    'tool_call_id': toolCallId,
    'content': content,
  };
}
