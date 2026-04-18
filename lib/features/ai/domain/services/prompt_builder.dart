import 'package:JsxposedX/core/enums/ai_api_type.dart';
import 'package:JsxposedX/features/ai/data/prompts/system_prompts.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_context.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_tool_definition.dart';
import 'package:flutter/services.dart';

/// 提示词构建器
///
/// 混合模式：核心模板来自 [SystemPrompts]，API 摘要从 assets 加载。
/// 使用 Builder 模式组装最终的 system prompt 和 tools 列表。
class PromptBuilder {
  bool _isZh;
  AiApkContext? _apkContext;
  String? _apiSummary;
  bool _withTools;
  bool _withSoTools;

  PromptBuilder({bool isZh = true})
      : _isZh = isZh,
        _withTools = false,
        _withSoTools = false;

  /// 设置语言
  PromptBuilder lang(bool isZh) {
    _isZh = isZh;
    return this;
  }

  /// 注入 APK 上下文
  PromptBuilder withApkContext(AiApkContext context) {
    _apkContext = context;
    return this;
  }

  /// 注入 API 摘要（从 assets 加载的内容）
  PromptBuilder withApiSummary(String summary) {
    _apiSummary = summary;
    return this;
  }

  /// 启用工具调用
  PromptBuilder withTools() {
    _withTools = true;
    return this;
  }

  /// 启用 SO 分析工具
  PromptBuilder withSoTools() {
    _withSoTools = true;
    return this;
  }

  /// 构建 system prompt 文本
  String buildSystemPrompt() {
    final b = StringBuffer();

    // 1. 角色定义
    b.writeln(_isZh ? SystemPrompts.reverseRoleZh : SystemPrompts.reverseRoleEn);

    // 2. APK 上下文
    if (_apkContext != null) {
      b.writeln();
      b.writeln(_apkContext!.toPromptText(isZh: _isZh));
    }

    // 3. 工具说明
    if (_withTools) {
      b.writeln(_isZh ? SystemPrompts.toolGuideZh : SystemPrompts.toolGuideEn);
    }

    // 4. API 手册摘要
    if (_apiSummary != null && _apiSummary!.isNotEmpty) {
      b.writeln(_isZh ? SystemPrompts.apiRefHeaderZh : SystemPrompts.apiRefHeaderEn);
      b.writeln(_apiSummary);
    }

    // 5. 输出规范
    b.writeln(_isZh ? SystemPrompts.outputGuideZh : SystemPrompts.outputGuideEn);

    return b.toString();
  }

  /// 构建 Function Calling 工具定义列表
  List<Map<String, dynamic>> buildToolsJson({
    AiApiType apiType = AiApiType.openai,
  }) {
    if (!_withTools) return [];
    final tools = _withSoTools ? ApkAnalysisTools.allWithSo : ApkAnalysisTools.all;
    return tools
        .map(
          (tool) => switch (apiType) {
            AiApiType.openai => tool.toOpenAiToolJson(),
            AiApiType.openaiResponses => tool.toOpenAiToolJson(),
            AiApiType.anthropic => tool.toAnthropicToolJson(),
          },
        )
        .toList();
  }

  // ==================== 静态工具方法 ====================

  /// 加载 API 摘要文件
  static Future<String> loadApiSummary() async {
    return rootBundle.loadString('assets/raws/api_summary.md');
  }

  /// 快速构建逆向分析的完整 prompt（常用入口）
  static Future<PromptBuilder> reverseAnalysis({
    required bool isZh,
    required AiApkContext apkContext,
    bool enableSoTools = true,
  }) async {
    final summary = await loadApiSummary();
    final builder = PromptBuilder(isZh: isZh)
        .withApkContext(apkContext)
        .withApiSummary(summary)
        .withTools();
    if (enableSoTools) {
      builder.withSoTools();
    }
    return builder;
  }
}

/// APK 分析工具定义集合
class ApkAnalysisTools {
  ApkAnalysisTools._();

  static final getManifest = AiToolDefinition(
    name: 'get_manifest',
    description: '获取 APK 的完整 Manifest 信息，包括权限、四大组件、SDK 版本、debuggable 等',
    parameters: ToolParametersBuilder.empty(),
  );

  static final decompileClass = AiToolDefinition(
    name: 'decompile_class',
    description: '反编译指定类为 Java 源代码。需要提供完整类名（如 com.example.app.MainActivity）',
    parameters: (ToolParametersBuilder()
          ..addString('className', '要反编译的类的全限定名', required: true))
        .build(),
  );

  static final getSmali = AiToolDefinition(
    name: 'get_smali',
    description: '获取指定类的 Smali 字节码。适合需要查看底层实现细节的场景',
    parameters: (ToolParametersBuilder()
          ..addString('className', '要查看的类的全限定名', required: true))
        .build(),
  );

  static final listPackages = AiToolDefinition(
    name: 'list_packages',
    description: '列出指定前缀下的子包名。传空字符串列出顶层包。注意：此工具只用于浏览包结构，不能搜索关键词。如果需要搜索类，使用 search_classes',
    parameters: (ToolParametersBuilder()
          ..addString('prefix', '包名前缀，如 "com.example"，空字符串表示顶层',
              required: true))
        .build(),
  );

  static final listClasses = AiToolDefinition(
    name: 'list_classes',
    description: '列出指定包下的所有类，返回类名、方法数、字段数、是否抽象/接口/枚举等信息。注意：此工具需要精确的包名，不能搜索关键词。如果不知道包名，使用 search_classes',
    parameters: (ToolParametersBuilder()
          ..addString('packageName', '包名，如 "com.example.app"', required: true))
        .build(),
  );

  static final searchClasses = AiToolDefinition(
    name: 'search_classes',
    description: '在所有包中搜索类名包含指定关键词的类，返回匹配的全限定类名列表。用于查找 VIP、支付、登录、加密等功能相关的类。重要：严格使用用户提到的关键词，不要自己发明新关键词',
    parameters: (ToolParametersBuilder()
          ..addString('keyword', '搜索关键词，不区分大小写，如 "vip"、"pay"、"login"、"encrypt"', required: true))
        .build(),
  );

  static final listApkFiles = AiToolDefinition(
    name: 'list_apk_files',
    description: '列出 APK 内指定目录下的文件和子目录。传空字符串列出根目录，传 "lib/" 列出所有架构目录，传 "lib/arm64-v8a/" 列出该架构下的所有 SO 文件。分析 Native 层前先用此工具确认 SO 文件路径',
    parameters: (ToolParametersBuilder()
          ..addString('path', '目录路径，如 ""（根目录）、"lib/"、"lib/arm64-v8a/"', required: true))
        .build(),
  );

  // ==================== SO 分析工具 ====================

  static final getSoInfo = AiToolDefinition(
    name: 'get_so_info',
    description: '获取指定 SO 文件的基本信息，包括 ELF 头信息、架构、依赖库、导出/导入符号数量、JNI 函数数量等',
    parameters: (ToolParametersBuilder()
          ..addString('soPath', 'SO 文件在 APK 中的路径，如 "lib/arm64-v8a/libnative.so"', required: true))
        .build(),
  );

  static final searchSoSymbols = AiToolDefinition(
    name: 'search_so_symbols',
    description: '在 SO 文件中搜索符号（函数名），支持搜索导出和导入符号。用于查找加密、签名、校验等关键函数',
    parameters: (ToolParametersBuilder()
          ..addString('soPath', 'SO 文件路径', required: true)
          ..addString('keyword', '搜索关键词，如 "encrypt"、"sign"、"check"', required: true))
        .build(),
  );

  static final getJniFunctions = AiToolDefinition(
    name: 'get_jni_functions',
    description: '获取 SO 文件中的所有 JNI 函数列表，包括静态注册和动态注册的 JNI 函数，返回 Java 类名、方法名、地址等信息',
    parameters: (ToolParametersBuilder()
          ..addString('soPath', 'SO 文件路径', required: true))
        .build(),
  );

  static final searchSoStrings = AiToolDefinition(
    name: 'search_so_strings',
    description: '在 SO 文件中搜索字符串，用于查找加密密钥、API URL、调试信息等敏感字符串',
    parameters: (ToolParametersBuilder()
          ..addString('soPath', 'SO 文件路径', required: true)
          ..addString('keyword', '搜索关键词，如 "key"、"http"、"password"', required: true))
        .build(),
  );

  static final generateSoHook = AiToolDefinition(
    name: 'generate_so_hook',
    description: '为指定的 SO 符号生成 Frida Hook 代码模板，包括参数解析、返回值修改等',
    parameters: (ToolParametersBuilder()
          ..addString('soPath', 'SO 文件路径', required: true)
          ..addString('symbolName', '符号名称', required: true)
          ..addString('address', '符号地址（十六进制字符串，如 "0x1234"）', required: true))
        .build(),
  );

  static final List<AiToolDefinition> all = [
    getManifest,
    searchClasses,
    listApkFiles,
    decompileClass,
    getSmali,
    listPackages,
    listClasses,
  ];

  static final List<AiToolDefinition> allWithSo = [
    getManifest,
    searchClasses,
    listApkFiles,
    decompileClass,
    getSmali,
    listPackages,
    listClasses,
    getSoInfo,
    searchSoSymbols,
    getJniFunctions,
    searchSoStrings,
    generateSoHook,
  ];
}
