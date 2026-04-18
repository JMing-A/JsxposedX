import 'package:JsxposedX/features/ai/domain/models/ai_context.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_tool_call.dart';
import 'package:JsxposedX/features/apk_analysis/domain/repositories/apk_analysis_query_repository.dart';
import 'package:JsxposedX/features/so_analysis/data/datasources/so_analysis_datasource.dart';

/// 工具执行器
///
/// 接收 AI 返回的 [AiToolCall]，调用对应的 APK/SO 分析方法，返回 [AiToolResult]。
/// 需要 sessionId 和 dexPaths 来执行 APK 分析操作。
class ToolExecutor {
  final ApkAnalysisQueryRepository _repo;
  final SoAnalysisDatasource _soDataSource;
  final String sessionId;
  final List<String> dexPaths;

  ToolExecutor({
    required ApkAnalysisQueryRepository repo,
    required SoAnalysisDatasource soDataSource,
    required this.sessionId,
    required this.dexPaths,
  }) : _repo = repo,
       _soDataSource = soDataSource;

  /// 执行单个工具调用
  Future<AiToolResult> execute(AiToolCall call) async {
    try {
      final result = await _dispatch(call);
      return AiToolResult.ok(call.id, call.name, result);
    } catch (e) {
      return AiToolResult.error(call.id, call.name, e.toString());
    }
  }

  /// 批量执行工具调用
  Future<List<AiToolResult>> executeAll(List<AiToolCall> calls) async {
    final results = <AiToolResult>[];
    for (final call in calls) {
      results.add(await execute(call));
    }
    return results;
  }

  /// 路由到具体的工具实现
  Future<String> _dispatch(AiToolCall call) async {
    switch (call.name) {
      case 'get_manifest':
        return _getManifest();
      case 'decompile_class':
        return _decompileClass(call.getString('className'));
      case 'get_smali':
        return _getSmali(call.getString('className'));
      case 'list_packages':
        return _listPackages(call.getString('prefix'));
      case 'list_classes':
        return _listClasses(call.getString('packageName'));
      case 'search_classes':
        return _searchClasses(call.getString('keyword'));
      case 'list_apk_files':
        return _listApkFiles(call.getString('path'));
      // SO 分析工具
      case 'get_so_info':
        return _getSoInfo(call.getString('soPath'));
      case 'search_so_symbols':
        return _searchSoSymbols(call.getString('soPath'), call.getString('keyword'));
      case 'get_jni_functions':
        return _getJniFunctions(call.getString('soPath'));
      case 'search_so_strings':
        return _searchSoStrings(call.getString('soPath'), call.getString('keyword'));
      case 'generate_so_hook':
        return _generateSoHook(
          call.getString('soPath'),
          call.getString('symbolName'),
          call.getString('address'),
        );
      default:
        throw UnsupportedError('未知工具: ${call.name}');
    }
  }

  Future<String> _getManifest() async {
    final manifest = await _repo.parseManifest(sessionId);
    final ctx = AiApkContext.fromManifest(manifest);
    // 返回完整信息（比 system prompt 中的基础信息更详细）
    return ctx.toPromptText(isZh: true);
  }

  Future<String> _decompileClass(String className) async {
    if (className.isEmpty) throw ArgumentError('className 不能为空');
    return _repo.decompileClass(sessionId, dexPaths, className);
  }

  Future<String> _getSmali(String className) async {
    if (className.isEmpty) throw ArgumentError('className 不能为空');
    return _repo.getClassSmali(sessionId, dexPaths, className);
  }

  Future<String> _listPackages(String prefix) async {
    final packages = await _repo.getDexPackages(sessionId, dexPaths, prefix);
    if (packages.isEmpty) return '未找到子包 (prefix: "$prefix")';
    return packages.join('\n');
  }

  Future<String> _searchClasses(String keyword) async {
    if (keyword.isEmpty) throw ArgumentError('keyword 不能为空');
    final results = await _repo.searchDexClasses(sessionId, dexPaths, keyword);
    if (results.isEmpty) return '未找到包含关键词 "$keyword" 的类';
    return '共找到 ${results.length} 个匹配类：\n${results.join('\n')}';
  }

  Future<String> _listClasses(String packageName) async {
    final classes = await _repo.getDexClasses(sessionId, dexPaths, packageName);
    if (classes.isEmpty) return '未找到类 (package: "$packageName")';
    final b = StringBuffer();
    for (final cls in classes) {
      final tags = <String>[];
      if (cls.isAbstract) tags.add('abstract');
      if (cls.isInterface) tags.add('interface');
      if (cls.isEnum) tags.add('enum');
      final tagStr = tags.isNotEmpty ? ' [${tags.join(", ")}]' : '';
      b.writeln(
        '${cls.className}$tagStr — ${cls.methodCount} methods, ${cls.fieldCount} fields',
      );
      if (cls.superClass != null && cls.superClass != 'java.lang.Object') {
        b.writeln('  extends ${cls.superClass}');
      }
      if (cls.interfaces.isNotEmpty) {
        final ifaces = cls.interfaces.whereType<String>().toList();
        if (ifaces.isNotEmpty) {
          b.writeln('  implements ${ifaces.join(", ")}');
        }
      }
    }
    return b.toString();
  }

  Future<String> _listApkFiles(String path) async {
    try {
      final items = await _repo.getApkAssetsAt(sessionId, path);
      if (items.isEmpty) return '目录为空: "$path"';
      final b = StringBuffer();
      b.writeln('路径: "$path" 下共 ${items.length} 个条目：\n');
      for (final item in items) {
        if (item.isDirectory) {
          b.writeln('[DIR]  ${item.path}');
        } else {
          final kb = item.size > 0 ? ' (${(item.size / 1024).toStringAsFixed(1)}KB)' : '';
          b.writeln('[FILE] ${item.path}$kb');
        }
      }
      return b.toString();
    } catch (e) {
      return '列出文件失败: $e';
    }
  }

  // ==================== SO 分析工具实现 ====================

  Future<String> _getSoInfo(String soPath) async {
    if (soPath.isEmpty) throw ArgumentError('soPath 不能为空');
    
    try {
      final header = await _soDataSource.parseSoHeader(sessionId, soPath);
      final deps = await _soDataSource.getDependencies(sessionId, soPath);
      final exportedSymbols = await _soDataSource.getExportedSymbols(sessionId, soPath);
      final importedSymbols = await _soDataSource.getImportedSymbols(sessionId, soPath);
      final jniFunctions = await _soDataSource.getJniFunctions(sessionId, soPath);
      
      final b = StringBuffer();
      b.writeln('SO 文件: $soPath');
      b.writeln('\n【ELF 头信息】');
      b.writeln('架构: ${header.machine}');
      b.writeln('类型: ${header.classType}');
      b.writeln('字节序: ${header.dataEncoding}');
      b.writeln('OS/ABI: ${header.osAbi}');
      b.writeln('文件类型: ${header.fileType}');
      b.writeln('入口点: 0x${header.entryPoint.toRadixString(16)}');
      
      if (deps.isNotEmpty) {
        b.writeln('\n【依赖库】(${deps.length}个)');
        for (final dep in deps) {
          b.writeln('  - ${dep.name}');
        }
      }
      
      b.writeln('\n【符号统计】');
      b.writeln('导出符号: ${exportedSymbols.length} 个');
      b.writeln('导入符号: ${importedSymbols.length} 个');
      b.writeln('JNI 函数: ${jniFunctions.length} 个');
      
      return b.toString();
    } catch (e) {
      return '获取 SO 信息失败: $e';
    }
  }

  Future<String> _searchSoSymbols(String soPath, String keyword) async {
    if (soPath.isEmpty) throw ArgumentError('soPath 不能为空');
    if (keyword.isEmpty) throw ArgumentError('keyword 不能为空');
    
    try {
      final exported = await _soDataSource.getExportedSymbols(sessionId, soPath);
      final imported = await _soDataSource.getImportedSymbols(sessionId, soPath);
      
      final lowerKeyword = keyword.toLowerCase();
      final matchedExported = exported
          .where((s) => s.name.toLowerCase().contains(lowerKeyword))
          .take(50)
          .toList();
      final matchedImported = imported
          .where((s) => s.name.toLowerCase().contains(lowerKeyword))
          .take(50)
          .toList();
      
      if (matchedExported.isEmpty && matchedImported.isEmpty) {
        return '未找到包含关键词 "$keyword" 的符号';
      }
      
      final b = StringBuffer();
      b.writeln('搜索关键词: "$keyword"');
      
      if (matchedExported.isNotEmpty) {
        b.writeln('\n【导出符号】(${matchedExported.length}个)');
        for (final sym in matchedExported) {
          b.writeln('${sym.name}');
          b.writeln('  类型: ${sym.type}, 绑定: ${sym.binding}, 地址: 0x${sym.address.toRadixString(16)}');
        }
      }
      
      if (matchedImported.isNotEmpty) {
        b.writeln('\n【导入符号】(${matchedImported.length}个)');
        for (final sym in matchedImported) {
          b.writeln('${sym.name}');
          b.writeln('  类型: ${sym.type}, 绑定: ${sym.binding}');
        }
      }
      
      return b.toString();
    } catch (e) {
      return '搜索符号失败: $e';
    }
  }

  Future<String> _getJniFunctions(String soPath) async {
    if (soPath.isEmpty) throw ArgumentError('soPath 不能为空');
    
    try {
      final jniFunctions = await _soDataSource.getJniFunctions(sessionId, soPath);
      
      if (jniFunctions.isEmpty) {
        return '未找到 JNI 函数';
      }
      
      final b = StringBuffer();
      b.writeln('共找到 ${jniFunctions.length} 个 JNI 函数：\n');
      
      for (final fn in jniFunctions) {
        b.writeln('${fn.javaClass}.${fn.javaMethod}');
        b.writeln('  符号: ${fn.symbolName}');
        b.writeln('  地址: 0x${fn.address.toRadixString(16)}');
        b.writeln('  类型: ${fn.isDynamic ? "动态注册" : "静态注册"}');
        if (fn.signature != null) {
          b.writeln('  签名: ${fn.signature}');
        }
        b.writeln();
      }
      
      return b.toString();
    } catch (e) {
      return '获取 JNI 函数失败: $e';
    }
  }

  Future<String> _searchSoStrings(String soPath, String keyword) async {
    if (soPath.isEmpty) throw ArgumentError('soPath 不能为空');
    if (keyword.isEmpty) throw ArgumentError('keyword 不能为空');
    
    try {
      final strings = await _soDataSource.getSoStrings(sessionId, soPath);
      
      final lowerKeyword = keyword.toLowerCase();
      final matched = strings
          .where((s) => s.value.toLowerCase().contains(lowerKeyword))
          .take(100)
          .toList();
      
      if (matched.isEmpty) {
        return '未找到包含关键词 "$keyword" 的字符串';
      }
      
      final b = StringBuffer();
      b.writeln('搜索关键词: "$keyword"');
      b.writeln('共找到 ${matched.length} 个匹配字符串：\n');
      
      for (final str in matched) {
        b.writeln('"${str.value}"');
        b.writeln('  位置: ${str.section}, 偏移: 0x${str.offset.toRadixString(16)}');
        b.writeln();
      }
      
      return b.toString();
    } catch (e) {
      return '搜索字符串失败: $e';
    }
  }

  Future<String> _generateSoHook(String soPath, String symbolName, String address) async {
    if (soPath.isEmpty) throw ArgumentError('soPath 不能为空');
    if (symbolName.isEmpty) throw ArgumentError('symbolName 不能为空');
    if (address.isEmpty) throw ArgumentError('address 不能为空');
    
    try {
      // 解析地址
      final addr = int.parse(address.replaceFirst('0x', ''), radix: 16);
      final hook = await _soDataSource.generateFridaHook(sessionId, soPath, symbolName, addr);
      return hook;
    } catch (e) {
      return '生成 Hook 代码失败: $e';
    }
  }
}
