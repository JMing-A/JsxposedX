import 'package:JsxposedX/features/ai/domain/contracts/ai_chat_tool_handler.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_context.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_tool_call.dart';
import 'package:JsxposedX/features/apk_analysis/domain/repositories/apk_analysis_query_repository.dart';
import 'package:JsxposedX/features/so_analysis/data/datasources/so_analysis_datasource.dart';

class ApkReverseToolRuntimeContext {
  const ApkReverseToolRuntimeContext({
    required this.repo,
    required this.soDataSource,
    required this.sessionId,
    required this.dexPaths,
  });

  final ApkAnalysisQueryRepository repo;
  final SoAnalysisDatasource soDataSource;
  final String sessionId;
  final List<String> dexPaths;
}

Iterable<AiChatToolHandler> buildApkReverseToolHandlers({
  required ApkReverseToolRuntimeContext context,
  bool includeSoTools = true,
}) sync* {
  yield _GetManifestToolHandler(context);
  yield _DecompileClassToolHandler(context);
  yield _GetSmaliToolHandler(context);
  yield _ListPackagesToolHandler(context);
  yield _ListClassesToolHandler(context);
  yield _SearchClassesToolHandler(context);
  yield _ListApkFilesToolHandler(context);
  if (!includeSoTools) {
    return;
  }
  yield _GetSoInfoToolHandler(context);
  yield _SearchSoSymbolsToolHandler(context);
  yield _GetJniFunctionsToolHandler(context);
  yield _SearchSoStringsToolHandler(context);
  yield _GenerateSoHookToolHandler(context);
}

abstract class _ApkReverseToolHandlerBase implements AiChatToolHandler {
  const _ApkReverseToolHandlerBase(this.context);

  final ApkReverseToolRuntimeContext context;
}

class _GetManifestToolHandler extends _ApkReverseToolHandlerBase {
  const _GetManifestToolHandler(super.context);

  @override
  String get toolName => 'get_manifest';

  @override
  Future<String> handle(
    AiToolCall call, {
    AiToolProgressCallback? onProgress,
  }) async {
    final manifest = await context.repo.parseManifest(context.sessionId);
    final apkContext = AiApkContext.fromManifest(manifest);
    return apkContext.toPromptText(isZh: true);
  }
}

class _DecompileClassToolHandler extends _ApkReverseToolHandlerBase {
  const _DecompileClassToolHandler(super.context);

  @override
  String get toolName => 'decompile_class';

  @override
  Future<String> handle(
    AiToolCall call, {
    AiToolProgressCallback? onProgress,
  }) async {
    final className = call.getString('className');
    if (className.isEmpty) {
      throw ArgumentError('className 不能为空');
    }
    return context.repo.decompileClass(
      context.sessionId,
      context.dexPaths,
      className,
    );
  }
}

class _GetSmaliToolHandler extends _ApkReverseToolHandlerBase {
  const _GetSmaliToolHandler(super.context);

  @override
  String get toolName => 'get_smali';

  @override
  Future<String> handle(
    AiToolCall call, {
    AiToolProgressCallback? onProgress,
  }) async {
    final className = call.getString('className');
    if (className.isEmpty) {
      throw ArgumentError('className 不能为空');
    }
    return context.repo.getClassSmali(
      context.sessionId,
      context.dexPaths,
      className,
    );
  }
}

class _ListPackagesToolHandler extends _ApkReverseToolHandlerBase {
  const _ListPackagesToolHandler(super.context);

  @override
  String get toolName => 'list_packages';

  @override
  Future<String> handle(
    AiToolCall call, {
    AiToolProgressCallback? onProgress,
  }) async {
    final prefix = call.getString('prefix');
    final packages = await context.repo.getDexPackages(
      context.sessionId,
      context.dexPaths,
      prefix,
    );
    if (packages.isEmpty) {
      return '未找到子包 (prefix: "$prefix")';
    }
    return packages.join('\n');
  }
}

class _ListClassesToolHandler extends _ApkReverseToolHandlerBase {
  const _ListClassesToolHandler(super.context);

  @override
  String get toolName => 'list_classes';

  @override
  Future<String> handle(
    AiToolCall call, {
    AiToolProgressCallback? onProgress,
  }) async {
    final packageName = call.getString('packageName');
    final classes = await context.repo.getDexClasses(
      context.sessionId,
      context.dexPaths,
      packageName,
    );
    if (classes.isEmpty) {
      return '未找到类 (package: "$packageName")';
    }

    final buffer = StringBuffer();
    for (final cls in classes) {
      final tags = <String>[];
      if (cls.isAbstract) tags.add('abstract');
      if (cls.isInterface) tags.add('interface');
      if (cls.isEnum) tags.add('enum');
      final tagStr = tags.isNotEmpty ? ' [${tags.join(", ")}]' : '';
      buffer.writeln(
        '${cls.className}$tagStr — ${cls.methodCount} methods, ${cls.fieldCount} fields',
      );
      if (cls.superClass != null && cls.superClass != 'java.lang.Object') {
        buffer.writeln('  extends ${cls.superClass}');
      }
      if (cls.interfaces.isNotEmpty) {
        final interfaces = cls.interfaces.whereType<String>().toList();
        if (interfaces.isNotEmpty) {
          buffer.writeln('  implements ${interfaces.join(", ")}');
        }
      }
    }
    return buffer.toString();
  }
}

class _SearchClassesToolHandler extends _ApkReverseToolHandlerBase {
  const _SearchClassesToolHandler(super.context);

  @override
  String get toolName => 'search_classes';

  @override
  Future<String> handle(
    AiToolCall call, {
    AiToolProgressCallback? onProgress,
  }) async {
    final keyword = call.getString('keyword');
    if (keyword.isEmpty) {
      throw ArgumentError('keyword 不能为空');
    }
    final results = await context.repo.searchDexClasses(
      context.sessionId,
      context.dexPaths,
      keyword,
    );
    if (results.isEmpty) {
      return '未找到包含关键词 "$keyword" 的类';
    }
    return '共找到 ${results.length} 个匹配类：\n${results.join('\n')}';
  }
}

class _ListApkFilesToolHandler extends _ApkReverseToolHandlerBase {
  const _ListApkFilesToolHandler(super.context);

  @override
  String get toolName => 'list_apk_files';

  @override
  Future<String> handle(
    AiToolCall call, {
    AiToolProgressCallback? onProgress,
  }) async {
    final path = call.getString('path');
    try {
      final items = await context.repo.getApkAssetsAt(context.sessionId, path);
      if (items.isEmpty) {
        return '目录为空: "$path"';
      }

      final buffer = StringBuffer();
      buffer.writeln('路径: "$path" 下共 ${items.length} 个条目：\n');
      for (final item in items) {
        if (item.isDirectory) {
          buffer.writeln('[DIR]  ${item.path}');
          continue;
        }
        final kb = item.size > 0
            ? ' (${(item.size / 1024).toStringAsFixed(1)}KB)'
            : '';
        buffer.writeln('[FILE] ${item.path}$kb');
      }
      return buffer.toString();
    } catch (error) {
      return '列出文件失败: $error';
    }
  }
}

class _GetSoInfoToolHandler extends _ApkReverseToolHandlerBase {
  const _GetSoInfoToolHandler(super.context);

  @override
  String get toolName => 'get_so_info';

  @override
  Future<String> handle(
    AiToolCall call, {
    AiToolProgressCallback? onProgress,
  }) async {
    final soPath = call.getString('soPath');
    if (soPath.isEmpty) {
      throw ArgumentError('soPath 不能为空');
    }

    try {
      final header = await context.soDataSource.parseSoHeader(
        context.sessionId,
        soPath,
      );
      final deps = await context.soDataSource.getDependencies(
        context.sessionId,
        soPath,
      );
      final exportedSymbols = await context.soDataSource.getExportedSymbols(
        context.sessionId,
        soPath,
      );
      final importedSymbols = await context.soDataSource.getImportedSymbols(
        context.sessionId,
        soPath,
      );
      final jniFunctions = await context.soDataSource.getJniFunctions(
        context.sessionId,
        soPath,
      );

      final buffer = StringBuffer();
      buffer.writeln('SO 文件: $soPath');
      buffer.writeln('\n【ELF 头信息】');
      buffer.writeln('架构: ${header.machine}');
      buffer.writeln('类型: ${header.classType}');
      buffer.writeln('字节序: ${header.dataEncoding}');
      buffer.writeln('OS/ABI: ${header.osAbi}');
      buffer.writeln('文件类型: ${header.fileType}');
      buffer.writeln('入口点: 0x${header.entryPoint.toRadixString(16)}');

      if (deps.isNotEmpty) {
        buffer.writeln('\n【依赖库】(${deps.length}个)');
        for (final dep in deps) {
          buffer.writeln('  - ${dep.name}');
        }
      }

      buffer.writeln('\n【符号统计】');
      buffer.writeln('导出符号: ${exportedSymbols.length} 个');
      buffer.writeln('导入符号: ${importedSymbols.length} 个');
      buffer.writeln('JNI 函数: ${jniFunctions.length} 个');
      return buffer.toString();
    } catch (error) {
      return '获取 SO 信息失败: $error';
    }
  }
}

class _SearchSoSymbolsToolHandler extends _ApkReverseToolHandlerBase {
  const _SearchSoSymbolsToolHandler(super.context);

  @override
  String get toolName => 'search_so_symbols';

  @override
  Future<String> handle(
    AiToolCall call, {
    AiToolProgressCallback? onProgress,
  }) async {
    final soPath = call.getString('soPath');
    final keyword = call.getString('keyword');
    if (soPath.isEmpty) {
      throw ArgumentError('soPath 不能为空');
    }
    if (keyword.isEmpty) {
      throw ArgumentError('keyword 不能为空');
    }

    try {
      final exported = await context.soDataSource.getExportedSymbols(
        context.sessionId,
        soPath,
      );
      final imported = await context.soDataSource.getImportedSymbols(
        context.sessionId,
        soPath,
      );
      final lowerKeyword = keyword.toLowerCase();
      final matchedExported = exported
          .where((symbol) => symbol.name.toLowerCase().contains(lowerKeyword))
          .take(50)
          .toList(growable: false);
      final matchedImported = imported
          .where((symbol) => symbol.name.toLowerCase().contains(lowerKeyword))
          .take(50)
          .toList(growable: false);

      if (matchedExported.isEmpty && matchedImported.isEmpty) {
        return '未找到包含关键词 "$keyword" 的符号';
      }

      final buffer = StringBuffer();
      buffer.writeln('搜索关键词: "$keyword"');
      if (matchedExported.isNotEmpty) {
        buffer.writeln('\n【导出符号】(${matchedExported.length}个)');
        for (final symbol in matchedExported) {
          buffer.writeln(symbol.name);
          buffer.writeln(
            '  类型: ${symbol.type}, 绑定: ${symbol.binding}, 地址: 0x${symbol.address.toRadixString(16)}',
          );
        }
      }
      if (matchedImported.isNotEmpty) {
        buffer.writeln('\n【导入符号】(${matchedImported.length}个)');
        for (final symbol in matchedImported) {
          buffer.writeln(symbol.name);
          buffer.writeln('  类型: ${symbol.type}, 绑定: ${symbol.binding}');
        }
      }
      return buffer.toString();
    } catch (error) {
      return '搜索符号失败: $error';
    }
  }
}

class _GetJniFunctionsToolHandler extends _ApkReverseToolHandlerBase {
  const _GetJniFunctionsToolHandler(super.context);

  @override
  String get toolName => 'get_jni_functions';

  @override
  Future<String> handle(
    AiToolCall call, {
    AiToolProgressCallback? onProgress,
  }) async {
    final soPath = call.getString('soPath');
    if (soPath.isEmpty) {
      throw ArgumentError('soPath 不能为空');
    }

    try {
      final jniFunctions = await context.soDataSource.getJniFunctions(
        context.sessionId,
        soPath,
      );
      if (jniFunctions.isEmpty) {
        return '未找到 JNI 函数';
      }

      final buffer = StringBuffer();
      buffer.writeln('共找到 ${jniFunctions.length} 个 JNI 函数：\n');
      for (final function in jniFunctions) {
        buffer.writeln('${function.javaClass}.${function.javaMethod}');
        buffer.writeln('  符号: ${function.symbolName}');
        buffer.writeln('  地址: 0x${function.address.toRadixString(16)}');
        buffer.writeln('  类型: ${function.isDynamic ? "动态注册" : "静态注册"}');
        if (function.signature != null) {
          buffer.writeln('  签名: ${function.signature}');
        }
        buffer.writeln();
      }
      return buffer.toString();
    } catch (error) {
      return '获取 JNI 函数失败: $error';
    }
  }
}

class _SearchSoStringsToolHandler extends _ApkReverseToolHandlerBase {
  const _SearchSoStringsToolHandler(super.context);

  @override
  String get toolName => 'search_so_strings';

  @override
  Future<String> handle(
    AiToolCall call, {
    AiToolProgressCallback? onProgress,
  }) async {
    final soPath = call.getString('soPath');
    final keyword = call.getString('keyword');
    if (soPath.isEmpty) {
      throw ArgumentError('soPath 不能为空');
    }
    if (keyword.isEmpty) {
      throw ArgumentError('keyword 不能为空');
    }

    try {
      final strings = await context.soDataSource.getSoStrings(
        context.sessionId,
        soPath,
      );
      final lowerKeyword = keyword.toLowerCase();
      final matched = strings
          .where((value) => value.value.toLowerCase().contains(lowerKeyword))
          .take(100)
          .toList(growable: false);
      if (matched.isEmpty) {
        return '未找到包含关键词 "$keyword" 的字符串';
      }

      final buffer = StringBuffer();
      buffer.writeln('搜索关键词: "$keyword"');
      buffer.writeln('共找到 ${matched.length} 个匹配字符串：\n');
      for (final value in matched) {
        buffer.writeln('"${value.value}"');
        buffer.writeln(
          '  位置: ${value.section}, 偏移: 0x${value.offset.toRadixString(16)}',
        );
        buffer.writeln();
      }
      return buffer.toString();
    } catch (error) {
      return '搜索字符串失败: $error';
    }
  }
}

class _GenerateSoHookToolHandler extends _ApkReverseToolHandlerBase {
  const _GenerateSoHookToolHandler(super.context);

  @override
  String get toolName => 'generate_so_hook';

  @override
  Future<String> handle(
    AiToolCall call, {
    AiToolProgressCallback? onProgress,
  }) async {
    final soPath = call.getString('soPath');
    final symbolName = call.getString('symbolName');
    final address = call.getString('address');
    if (soPath.isEmpty) {
      throw ArgumentError('soPath 不能为空');
    }
    if (symbolName.isEmpty) {
      throw ArgumentError('symbolName 不能为空');
    }
    if (address.isEmpty) {
      throw ArgumentError('address 不能为空');
    }

    try {
      final parsedAddress = int.parse(
        address.replaceFirst('0x', ''),
        radix: 16,
      );
      return context.soDataSource.generateFridaHook(
        context.sessionId,
        soPath,
        symbolName,
        parsedAddress,
      );
    } catch (error) {
      return '生成 Hook 代码失败: $error';
    }
  }
}
