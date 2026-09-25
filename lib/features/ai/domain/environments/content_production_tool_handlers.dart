import 'dart:convert';

import 'package:JsxposedX/features/ai/domain/contracts/ai_chat_tool_handler.dart';
import 'package:JsxposedX/features/ai/domain/environments/ai_tool_runtime_context.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_tool_call.dart';

// ═══ 基类 ═══

abstract class ContentProductionHandler implements AiChatToolHandler {
  const ContentProductionHandler(this.context);

  final ApkReverseToolRuntimeContext context;

  String get _pkg => context.packageName;

  bool get _isZh => context.isZh;
}

// ═══ B1. export_conversation（P1） ═══

class ExportConversationHandler extends ContentProductionHandler {
  const ExportConversationHandler(super.context);

  @override
  String get toolName => 'export_conversation';

  @override
  Future<String> handle(
    AiToolCall call, {
    AiToolProgressCallback? onProgress,
  }) async {
    final format = call.getString('format', 'markdown');
    final includeToolCalls = call.getBool('include_tool_calls', true);
    final customFileName = call.getString('fileName', '');

    final conversationId = context.conversationBinding.conversationId;
    if (conversationId == null || conversationId.isEmpty) {
      return _isZh ? '无法导出：未找到当前会话 ID' : 'Cannot export: No current session ID';
    }

    final packageName = context.packageName;
    if (packageName.isEmpty) {
      return _isZh ? '无法导出：未找到包名' : 'Cannot export: Package name not found';
    }

    try {
      final exportService = context.exportService;
      if (exportService == null) {
        return _isZh
            ? '导出服务未初始化，请使用聊天界面右上角的导出按钮'
            : 'Export service not initialized. Please use the export button in the chat UI';
      }

      late String content;
      late String fileName;

      if (format == 'json') {
        content = await exportService.exportToJson(
          conversationId: conversationId,
          includeToolCalls: includeToolCalls,
        );
        fileName = customFileName.isNotEmpty
            ? customFileName
            : 'conversation_${DateTime.now().millisecondsSinceEpoch}.json';
      } else {
        content = await exportService.exportToMarkdown(
          conversationId: conversationId,
          includeToolCalls: includeToolCalls,
        );
        fileName = customFileName.isNotEmpty
            ? customFileName
            : 'conversation_${DateTime.now().millisecondsSinceEpoch}.md';
      }

      final file = await exportService.saveExport(
        content: content,
        fileName: fileName,
      );

      return _isZh
          ? '会话已导出到: ${file.path}\n格式: ${format == "markdown" ? "Markdown" : "JSON"}\n文件大小: ${(content.length / 1024).toStringAsFixed(2)} KB'
          : 'Conversation exported to: ${file.path}\nFormat: ${format == "markdown" ? "Markdown" : "JSON"}\nFile size: ${(content.length / 1024).toStringAsFixed(2)} KB';
    } catch (e) {
      return _isZh ? '导出失败: $e' : 'Export failed: $e';
    }
  }
}

// ═══ B2. generate_analysis_report（P2） ═══

class GenerateAnalysisReportHandler extends ContentProductionHandler {
  const GenerateAnalysisReportHandler(super.context);

  @override
  String get toolName => 'generate_analysis_report';

  @override
  Future<String> handle(
    AiToolCall call, {
    AiToolProgressCallback? onProgress,
  }) async {
    // 需要会话结果缓存层支持。当前返回引导提示，由 LLM 自行汇总。
    return _isZh
        ? '分析报告生成功能正在开发中。当前请根据已有工具结果自行汇总。'
        : 'Analysis report generation is under development. Please summarize from existing tool results manually.';
  }
}

// ═══ B3. save_note（P2） ═══

class SaveNoteHandler extends ContentProductionHandler {
  const SaveNoteHandler(super.context);

  @override
  String get toolName => 'save_note';

  @override
  Future<String> handle(
    AiToolCall call, {
    AiToolProgressCallback? onProgress,
  }) async {
    if (_pkg.isEmpty) {
      throw ArgumentError(
        _isZh ? '当前无目标应用' : 'No target app',
      );
    }

    final title = call.getString('title');
    final content = call.getString('content');

    if (title.isEmpty) throw ArgumentError('title 不能为空');
    if (content.isEmpty) throw ArgumentError('content 不能为空');

    // 检查标题非法字符
    if (RegExp(r'[/\\:*?"<>|]').hasMatch(title)) {
      throw ArgumentError(
        _isZh ? '标题含非法字符 / Title contains invalid characters' : 'Title contains invalid characters',
      );
    }

    // 笔记功能需 Pigeon 文件写接口。当前返回确认消息。
    return _isZh
        ? '笔记 "$title" 已记录（本地存储功能开发中）'
        : 'Note "$title" recorded (local storage under development)';
  }
}