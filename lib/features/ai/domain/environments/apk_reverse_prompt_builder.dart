import 'package:JsxposedX/features/ai/data/prompts/system_prompts.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_context.dart';
import 'package:flutter/services.dart';

class ApkReversePromptBuilder {
  ApkReversePromptBuilder({bool isZh = true})
    : _isZh = isZh,
      _withTools = false;

  bool _isZh;
  AiApkContext? _apkContext;
  String? _apiSummary;
  bool _withTools;

  ApkReversePromptBuilder lang(bool isZh) {
    _isZh = isZh;
    return this;
  }

  ApkReversePromptBuilder withApkContext(AiApkContext context) {
    _apkContext = context;
    return this;
  }

  ApkReversePromptBuilder withApiSummary(String summary) {
    _apiSummary = summary;
    return this;
  }

  ApkReversePromptBuilder withTools() {
    _withTools = true;
    return this;
  }

  String buildSystemPrompt() {
    final buffer = StringBuffer();
    buffer.writeln(
      _isZh ? SystemPrompts.reverseRoleZh : SystemPrompts.reverseRoleEn,
    );

    if (_apkContext != null) {
      buffer
        ..writeln()
        ..writeln(_apkContext!.toPromptText(isZh: _isZh));
    }

    if (_withTools) {
      buffer.writeln(
        _isZh ? SystemPrompts.toolGuideZh : SystemPrompts.toolGuideEn,
      );
    }

    if (_apiSummary != null && _apiSummary!.isNotEmpty) {
      buffer
        ..writeln(
          _isZh
              ? SystemPrompts.apiRefHeaderZh
              : SystemPrompts.apiRefHeaderEn,
        )
        ..writeln(_apiSummary);
    }

    buffer.writeln(
      _isZh ? SystemPrompts.outputGuideZh : SystemPrompts.outputGuideEn,
    );
    return buffer.toString();
  }

  static Future<String> loadApiSummary() async {
    return rootBundle.loadString('assets/raws/api_summary.md');
  }
}
