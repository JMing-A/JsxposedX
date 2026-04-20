import 'dart:convert';
import 'dart:typed_data';

import 'package:JsxposedX/features/ai/domain/contracts/ai_chat_tool_handler.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_tool_call.dart';
import 'package:JsxposedX/features/memory_tool_overlay/domain/repositories/memory_action_repository.dart';
import 'package:JsxposedX/features/memory_tool_overlay/domain/repositories/memory_pointer_action_repository.dart';
import 'package:JsxposedX/features/memory_tool_overlay/domain/repositories/memory_pointer_auto_chase_action_repository.dart';
import 'package:JsxposedX/features/memory_tool_overlay/domain/repositories/memory_pointer_auto_chase_query_repository.dart';
import 'package:JsxposedX/features/memory_tool_overlay/domain/repositories/memory_pointer_query_repository.dart';
import 'package:JsxposedX/features/memory_tool_overlay/domain/repositories/memory_query_repository.dart';
import 'package:JsxposedX/generated/memory_tool.g.dart';

class MemoryAiOverlayToolRuntimeContext {
  const MemoryAiOverlayToolRuntimeContext({
    required this.processInfo,
    required this.isZh,
    required this.memoryQueryRepository,
    required this.memoryActionRepository,
    required this.memoryPointerQueryRepository,
    required this.memoryPointerActionRepository,
    required this.memoryPointerAutoChaseQueryRepository,
    required this.memoryPointerAutoChaseActionRepository,
  });

  final ProcessInfo processInfo;
  final bool isZh;
  final MemoryQueryRepository memoryQueryRepository;
  final MemoryActionRepository memoryActionRepository;
  final MemoryPointerQueryRepository memoryPointerQueryRepository;
  final MemoryPointerActionRepository memoryPointerActionRepository;
  final MemoryPointerAutoChaseQueryRepository
  memoryPointerAutoChaseQueryRepository;
  final MemoryPointerAutoChaseActionRepository
  memoryPointerAutoChaseActionRepository;

  int get pid => processInfo.pid;
}

Iterable<AiChatToolHandler> buildMemoryAiOverlayToolHandlers({
  required MemoryAiOverlayToolRuntimeContext context,
}) sync* {
  yield _MemoryAiOverlayCallbackToolHandler(
    toolName: 'get_process_summary',
    onHandle: (call) async => _buildProcessSummary(context),
  );
  yield _MemoryAiOverlayCallbackToolHandler(
    toolName: 'list_memory_regions',
    onHandle: (call) async {
      final regions = await context.memoryQueryRepository.getMemoryRegions(
        pid: context.pid,
        offset: _getOptionalInt(call, 'offset', 0),
        limit: _getOptionalInt(call, 'limit', 50),
        readableOnly: _getOptionalBool(call, 'readableOnly', true),
        includeAnonymous: _getOptionalBool(call, 'includeAnonymous', true),
        includeFileBacked: _getOptionalBool(call, 'includeFileBacked', true),
      );
      if (regions.isEmpty) {
        return '未找到符合条件的内存区。';
      }
      final buffer = StringBuffer()
        ..writeln('共 ${regions.length} 个内存区：');
      for (final region in regions) {
        buffer.writeln(_formatRegion(region));
      }
      return buffer.toString().trim();
    },
  );
  yield _MemoryAiOverlayCallbackToolHandler(
    toolName: 'get_search_overview',
    onHandle: (call) async {
      final session = await context.memoryQueryRepository.getSearchSessionState();
      final task = await context.memoryQueryRepository.getSearchTaskState();
      final buffer = StringBuffer()
        ..writeln('搜索会话：')
        ..writeln(_formatSearchSessionState(session, currentPid: context.pid))
        ..writeln()
        ..writeln('搜索任务：')
        ..writeln(_formatSearchTaskState(task));
      return buffer.toString().trim();
    },
  );
  yield _MemoryAiOverlayCallbackToolHandler(
    toolName: 'get_search_results',
    onHandle: (call) async {
      final results = await context.memoryQueryRepository.getSearchResults(
        offset: _getOptionalInt(call, 'offset', 0),
        limit: _getOptionalInt(call, 'limit', 50),
      );
      if (results.isEmpty) {
        return '当前没有搜索结果。';
      }
      final buffer = StringBuffer()..writeln('共返回 ${results.length} 条搜索结果：');
      for (final result in results) {
        buffer.writeln(_formatSearchResult(result));
      }
      return buffer.toString().trim();
    },
  );
  yield _MemoryAiOverlayCallbackToolHandler(
    toolName: 'start_first_scan',
    onHandle: (call) async {
      final request = FirstScanRequest(
        pid: context.pid,
        value: _buildSearchValueFromToolCall(call, isFirstScan: true),
        matchMode: SearchMatchMode.exact,
        rangeSectionKeys: _getStringList(call, 'rangeSectionKeys'),
        scanAllReadableRegions: _getOptionalBool(
          call,
          'scanAllReadableRegions',
          true,
        ),
      );
      await context.memoryActionRepository.firstScan(request: request);
      return '首次搜索已发起。建议接着调用 get_search_overview 或 get_search_results 查看状态与结果。';
    },
  );
  yield _MemoryAiOverlayCallbackToolHandler(
    toolName: 'continue_next_scan',
    onHandle: (call) async {
      final request = NextScanRequest(
        value: _buildSearchValueFromToolCall(call, isFirstScan: false),
        matchMode: SearchMatchMode.exact,
      );
      await context.memoryActionRepository.nextScan(request: request);
      return '继续筛选已发起。建议接着调用 get_search_overview 或 get_search_results 查看新的结果。';
    },
  );
  yield _MemoryAiOverlayCallbackToolHandler(
    toolName: 'cancel_search',
    onHandle: (call) async {
      await context.memoryActionRepository.cancelSearch();
      return '搜索任务已取消。';
    },
  );
  yield _MemoryAiOverlayCallbackToolHandler(
    toolName: 'reset_search_session',
    onHandle: (call) async {
      await context.memoryActionRepository.resetSearchSession();
      return '搜索会话已重置。';
    },
  );
  yield _MemoryAiOverlayCallbackToolHandler(
    toolName: 'read_memory',
    onHandle: (call) async {
      final valueType = _parseRawSearchValueType(
        _getRequiredString(call, 'valueType'),
      );
      final addresses = _parseAddressList(call, 'addresses');
      if (addresses.isEmpty) {
        throw ArgumentError('addresses 不能为空');
      }
      final length = _resolveReadLength(
        valueType,
        _getOptionalIntOrNull(call, 'length'),
      );
      final previews = await context.memoryQueryRepository.readMemoryValues(
        requests: addresses
            .map(
              (address) => MemoryReadRequest(
                pid: context.pid,
                address: address,
                type: valueType,
                length: length,
              ),
            )
            .toList(growable: false),
      );
      if (previews.isEmpty) {
        return '未读取到任何内存值。';
      }
      final buffer = StringBuffer()..writeln('共读取 ${previews.length} 个地址：');
      for (final preview in previews) {
        buffer.writeln(_formatValuePreview(preview));
      }
      return buffer.toString().trim();
    },
  );
  yield _MemoryAiOverlayCallbackToolHandler(
    toolName: 'disassemble_memory',
    onHandle: (call) async {
      final addresses = _parseAddressList(call, 'addresses');
      if (addresses.isEmpty) {
        throw ArgumentError('addresses 不能为空');
      }
      final previews = await context.memoryQueryRepository.disassembleMemory(
        pid: context.pid,
        addresses: addresses,
      );
      if (previews.isEmpty) {
        return '未读取到任何反汇编结果。';
      }
      final buffer = StringBuffer()..writeln('共反汇编 ${previews.length} 个地址：');
      for (final preview in previews) {
        buffer.writeln(_formatInstructionPreview(preview));
      }
      return buffer.toString().trim();
    },
  );
  yield _MemoryAiOverlayCallbackToolHandler(
    toolName: 'write_memory_value',
    onHandle: (call) async {
      final address = _parseRequiredAddress(call, 'address');
      final value = _buildWriteValueFromToolCall(call);
      await context.memoryActionRepository.writeMemoryValue(
        request: MemoryWriteRequest(address: address, value: value),
      );
      return '已写入地址 ${_formatAddress(address)}。';
    },
  );
  yield _MemoryAiOverlayCallbackToolHandler(
    toolName: 'patch_memory_instruction',
    onHandle: (call) async {
      final address = _parseRequiredAddress(call, 'address');
      final instruction = _getRequiredString(call, 'instruction');
      final result = await context.memoryActionRepository.patchMemoryInstruction(
        request: MemoryInstructionPatchRequest(
          pid: context.pid,
          address: address,
          instruction: instruction,
        ),
      );
      return [
        '指令补丁已完成：',
        '地址: ${_formatAddress(result.address)}',
        '架构: ${result.architecture}',
        '指令大小: ${result.instructionSize}',
        '修改前: ${_formatHex(result.beforeBytes)}',
        '修改后: ${_formatHex(result.afterBytes)}',
        '指令文本: ${result.instructionText}',
      ].join('\n');
    },
  );
  yield _MemoryAiOverlayCallbackToolHandler(
    toolName: 'set_memory_freeze',
    onHandle: (call) async {
      final address = _parseRequiredAddress(call, 'address');
      final value = _buildWriteValueFromToolCall(call);
      final enabled = _getRequiredBool(call, 'enabled');
      await context.memoryActionRepository.setMemoryFreeze(
        request: MemoryFreezeRequest(
          address: address,
          value: value,
          enabled: enabled,
        ),
      );
      return enabled
          ? '已对地址 ${_formatAddress(address)} 启用冻结。'
          : '已对地址 ${_formatAddress(address)} 关闭冻结。';
    },
  );
  yield _MemoryAiOverlayCallbackToolHandler(
    toolName: 'list_frozen_memory_values',
    onHandle: (call) async {
      final allValues = await context.memoryActionRepository.getFrozenMemoryValues();
      final values = allValues
          .where((value) => value.pid == context.pid)
          .toList(growable: false);
      if (values.isEmpty) {
        return '当前进程没有冻结值。';
      }
      final buffer = StringBuffer()..writeln('当前进程共有 ${values.length} 个冻结值：');
      for (final value in values) {
        buffer.writeln(_formatFrozenMemoryValue(value));
      }
      return buffer.toString().trim();
    },
  );
  yield _MemoryAiOverlayCallbackToolHandler(
    toolName: 'set_process_paused',
    onHandle: (call) async {
      final paused = _getRequiredBool(call, 'paused');
      await context.memoryActionRepository.setProcessPaused(
        pid: context.pid,
        paused: paused,
      );
      return paused ? '当前进程已暂停。' : '当前进程已恢复运行。';
    },
  );
  yield _MemoryAiOverlayCallbackToolHandler(
    toolName: 'get_breakpoint_overview',
    onHandle: (call) async {
      final state = await context.memoryQueryRepository.getMemoryBreakpointState(
        pid: context.pid,
      );
      return _formatBreakpointState(state);
    },
  );
  yield _MemoryAiOverlayCallbackToolHandler(
    toolName: 'list_memory_breakpoints',
    onHandle: (call) async {
      final breakpoints = await context.memoryQueryRepository.listMemoryBreakpoints(
        pid: context.pid,
      );
      if (breakpoints.isEmpty) {
        return '当前进程没有断点。';
      }
      final buffer = StringBuffer()..writeln('当前进程共有 ${breakpoints.length} 个断点：');
      for (final breakpoint in breakpoints) {
        buffer.writeln(_formatBreakpoint(breakpoint));
      }
      return buffer.toString().trim();
    },
  );
  yield _MemoryAiOverlayCallbackToolHandler(
    toolName: 'get_memory_breakpoint_hits',
    onHandle: (call) async {
      final hits = await context.memoryQueryRepository.getMemoryBreakpointHits(
        pid: context.pid,
        offset: _getOptionalInt(call, 'offset', 0),
        limit: _getOptionalInt(call, 'limit', 50),
      );
      if (hits.isEmpty) {
        return '当前没有断点命中记录。';
      }
      final buffer = StringBuffer()..writeln('共返回 ${hits.length} 条断点命中：');
      for (final hit in hits) {
        buffer.writeln(_formatBreakpointHit(hit));
      }
      return buffer.toString().trim();
    },
  );
  yield _MemoryAiOverlayCallbackToolHandler(
    toolName: 'add_memory_breakpoint',
    onHandle: (call) async {
      final valueType = _parseRawSearchValueType(
        _getRequiredString(call, 'valueType'),
      );
      final length = _resolveReadLength(
        valueType,
        _getOptionalIntOrNull(call, 'length'),
      );
      final breakpoint = await context.memoryActionRepository.addMemoryBreakpoint(
        request: AddMemoryBreakpointRequest(
          pid: context.pid,
          address: _parseRequiredAddress(call, 'address'),
          type: valueType,
          length: length,
          accessType: _parseBreakpointAccessType(
            _getRequiredString(call, 'accessType'),
          ),
          enabled: _getOptionalBool(call, 'enabled', true),
          pauseProcessOnHit: _getOptionalBool(call, 'pauseProcessOnHit', true),
        ),
      );
      return '断点已创建：\n${_formatBreakpoint(breakpoint)}';
    },
  );
  yield _MemoryAiOverlayCallbackToolHandler(
    toolName: 'remove_memory_breakpoint',
    onHandle: (call) async {
      final breakpointId = _getRequiredString(call, 'breakpointId');
      await context.memoryActionRepository.removeMemoryBreakpoint(
        breakpointId: breakpointId,
      );
      return '断点 $breakpointId 已删除。';
    },
  );
  yield _MemoryAiOverlayCallbackToolHandler(
    toolName: 'set_memory_breakpoint_enabled',
    onHandle: (call) async {
      final breakpointId = _getRequiredString(call, 'breakpointId');
      final enabled = _getRequiredBool(call, 'enabled');
      await context.memoryActionRepository.setMemoryBreakpointEnabled(
        breakpointId: breakpointId,
        enabled: enabled,
      );
      return enabled
          ? '断点 $breakpointId 已启用。'
          : '断点 $breakpointId 已禁用。';
    },
  );
  yield _MemoryAiOverlayCallbackToolHandler(
    toolName: 'clear_memory_breakpoint_hits',
    onHandle: (call) async {
      await context.memoryActionRepository.clearMemoryBreakpointHits(
        pid: context.pid,
      );
      return '断点命中记录已清空。';
    },
  );
  yield _MemoryAiOverlayCallbackToolHandler(
    toolName: 'resume_after_breakpoint',
    onHandle: (call) async {
      await context.memoryActionRepository.resumeAfterBreakpoint(pid: context.pid);
      return '已从断点暂停状态恢复进程执行。';
    },
  );
  yield _MemoryAiOverlayCallbackToolHandler(
    toolName: 'get_pointer_scan_overview',
    onHandle: (call) async {
      final session = await context.memoryPointerQueryRepository
          .getPointerScanSessionState();
      final task = await context.memoryPointerQueryRepository
          .getPointerScanTaskState();
      final buffer = StringBuffer()
        ..writeln('指针扫描会话：')
        ..writeln(_formatPointerScanSession(session, currentPid: context.pid))
        ..writeln()
        ..writeln('指针扫描任务：')
        ..writeln(_formatPointerScanTask(task));
      return buffer.toString().trim();
    },
  );
  yield _MemoryAiOverlayCallbackToolHandler(
    toolName: 'get_pointer_scan_results',
    onHandle: (call) async {
      final results = await context.memoryPointerQueryRepository
          .getPointerScanResults(
            offset: _getOptionalInt(call, 'offset', 0),
            limit: _getOptionalInt(call, 'limit', 50),
          );
      if (results.isEmpty) {
        return '当前没有指针扫描结果。';
      }
      final buffer = StringBuffer()..writeln('共返回 ${results.length} 条指针结果：');
      for (final result in results) {
        buffer.writeln(_formatPointerResult(result));
      }
      return buffer.toString().trim();
    },
  );
  yield _MemoryAiOverlayCallbackToolHandler(
    toolName: 'get_pointer_scan_chase_hint',
    onHandle: (call) async {
      final hint = await context.memoryPointerQueryRepository
          .getPointerScanChaseHint();
      return _formatPointerChaseHint(hint);
    },
  );
  yield _MemoryAiOverlayCallbackToolHandler(
    toolName: 'start_pointer_scan',
    onHandle: (call) async {
      final request = _buildPointerScanRequest(call, context);
      await context.memoryPointerActionRepository.startPointerScan(
        request: request,
      );
      return '指针扫描已启动。建议接着调用 get_pointer_scan_overview 查看任务进度。';
    },
  );
  yield _MemoryAiOverlayCallbackToolHandler(
    toolName: 'cancel_pointer_scan',
    onHandle: (call) async {
      await context.memoryPointerActionRepository.cancelPointerScan();
      return '指针扫描已取消。';
    },
  );
  yield _MemoryAiOverlayCallbackToolHandler(
    toolName: 'reset_pointer_scan_session',
    onHandle: (call) async {
      await context.memoryPointerActionRepository.resetPointerScanSession();
      return '指针扫描会话已重置。';
    },
  );
  yield _MemoryAiOverlayCallbackToolHandler(
    toolName: 'get_pointer_auto_chase_overview',
    onHandle: (call) async {
      final state = await context.memoryPointerAutoChaseQueryRepository
          .getPointerAutoChaseState();
      return _formatPointerAutoChaseState(state);
    },
  );
  yield _MemoryAiOverlayCallbackToolHandler(
    toolName: 'get_pointer_auto_chase_layer_results',
    onHandle: (call) async {
      final layerIndex = _getOptionalInt(call, 'layerIndex', -1);
      if (layerIndex < 0) {
        throw ArgumentError('layerIndex 必须是大于等于 0 的整数');
      }
      final results = await context.memoryPointerAutoChaseQueryRepository
          .getPointerAutoChaseLayerResults(
            layerIndex: layerIndex,
            offset: _getOptionalInt(call, 'offset', 0),
            limit: _getOptionalInt(call, 'limit', 50),
          );
      if (results.isEmpty) {
        return '当前层没有结果。';
      }
      final buffer = StringBuffer()
        ..writeln('自动追链第 $layerIndex 层共返回 ${results.length} 条结果：');
      for (final result in results) {
        buffer.writeln(_formatPointerResult(result));
      }
      return buffer.toString().trim();
    },
  );
  yield _MemoryAiOverlayCallbackToolHandler(
    toolName: 'start_pointer_auto_chase',
    onHandle: (call) async {
      final baseRequest = _buildPointerScanRequest(call, context);
      final maxDepth = _getOptionalInt(call, 'maxDepth', 0);
      if (maxDepth < 1) {
        throw ArgumentError('maxDepth 必须是大于等于 1 的整数');
      }
      await context.memoryPointerAutoChaseActionRepository.startPointerAutoChase(
        request: PointerAutoChaseRequest(
          pid: baseRequest.pid,
          targetAddress: baseRequest.targetAddress,
          pointerWidth: baseRequest.pointerWidth,
          maxOffset: baseRequest.maxOffset,
          alignment: baseRequest.alignment,
          maxDepth: maxDepth,
          rangeSectionKeys: baseRequest.rangeSectionKeys,
          scanAllReadableRegions: baseRequest.scanAllReadableRegions,
        ),
      );
      return '自动指针追链已启动。建议接着调用 get_pointer_auto_chase_overview 查看状态。';
    },
  );
  yield _MemoryAiOverlayCallbackToolHandler(
    toolName: 'cancel_pointer_auto_chase',
    onHandle: (call) async {
      await context.memoryPointerAutoChaseActionRepository.cancelPointerAutoChase();
      return '自动指针追链已取消。';
    },
  );
  yield _MemoryAiOverlayCallbackToolHandler(
    toolName: 'reset_pointer_auto_chase',
    onHandle: (call) async {
      await context.memoryPointerAutoChaseActionRepository.resetPointerAutoChase();
      return '自动指针追链状态已重置。';
    },
  );
}

class _MemoryAiOverlayCallbackToolHandler implements AiChatToolHandler {
  const _MemoryAiOverlayCallbackToolHandler({
    required this.toolName,
    required Future<String> Function(AiToolCall call) onHandle,
  }) : _onHandle = onHandle;

  @override
  final String toolName;

  final Future<String> Function(AiToolCall call) _onHandle;

  @override
  Future<String> handle(AiToolCall call) {
    return _onHandle(call);
  }
}

Future<String> _buildProcessSummary(
  MemoryAiOverlayToolRuntimeContext context,
) async {
  final processPausedFuture = context.memoryActionRepository.isProcessPaused(
    pid: context.pid,
  );
  final frozenValuesFuture = context.memoryActionRepository.getFrozenMemoryValues();
  final searchSessionFuture = context.memoryQueryRepository.getSearchSessionState();
  final searchTaskFuture = context.memoryQueryRepository.getSearchTaskState();
  final breakpointStateFuture = context.memoryQueryRepository.getMemoryBreakpointState(
    pid: context.pid,
  );
  final pointerSessionFuture = context.memoryPointerQueryRepository
      .getPointerScanSessionState();
  final pointerTaskFuture = context.memoryPointerQueryRepository
      .getPointerScanTaskState();
  final autoChaseFuture = context.memoryPointerAutoChaseQueryRepository
      .getPointerAutoChaseState();

  final processPaused = await processPausedFuture;
  final frozenValues = await frozenValuesFuture;
  final searchSession = await searchSessionFuture;
  final searchTask = await searchTaskFuture;
  final breakpointState = await breakpointStateFuture;
  final pointerSession = await pointerSessionFuture;
  final pointerTask = await pointerTaskFuture;
  final autoChaseState = await autoChaseFuture;

  final currentFrozenCount = frozenValues
      .where((value) => value.pid == context.pid)
      .length;

  return [
    '目标进程:',
    '- 进程名: ${context.processInfo.name}',
    '- 包名: ${context.processInfo.packageName}',
    '- PID: ${context.pid}',
    '- 当前是否暂停: ${processPaused ? "是" : "否"}',
    '- 冻结值数量: $currentFrozenCount',
    '',
    '搜索会话:',
    _formatSearchSessionState(searchSession, currentPid: context.pid),
    _formatSearchTaskState(searchTask),
    '',
    '断点状态:',
    _formatBreakpointState(breakpointState),
    '',
    '指针扫描:',
    _formatPointerScanSession(pointerSession, currentPid: context.pid),
    _formatPointerScanTask(pointerTask),
    '',
    '自动追链:',
    _formatPointerAutoChaseState(autoChaseState),
  ].join('\n').trim();
}

SearchValue _buildSearchValueFromToolCall(
  AiToolCall call, {
  required bool isFirstScan,
}) {
  final valueType = _normalizeLower(_getRequiredString(call, 'valueType'));
  final matchMode = _normalizeLower(_getOptionalString(call, 'matchMode', 'exact'));
  final littleEndian = _getOptionalBool(call, 'littleEndian', true);
  final value = _getOptionalString(call, 'value', '').trim();
  final bytesMode = _normalizeLower(_getOptionalString(call, 'bytesMode', 'auto'));
  final fuzzyMode = _normalizeLower(
    _getOptionalString(
      call,
      'fuzzyMode',
      isFirstScan ? 'unknown' : 'changed',
    ),
  );

  if (matchMode == 'fuzzy') {
    final numericType = _parseRawSearchValueType(valueType);
    if (numericType == SearchValueType.bytes) {
      throw ArgumentError('fuzzy 搜索仅支持数值类型');
    }
    final effectiveFuzzyMode = isFirstScan
        ? 'unknown'
        : (fuzzyMode == 'unknown' ? 'changed' : fuzzyMode);
    if (!_supportedFuzzyModes.contains(effectiveFuzzyMode)) {
      throw ArgumentError('不支持的 fuzzyMode: $effectiveFuzzyMode');
    }
    return SearchValue(
      type: numericType,
      textValue: '__jsx_fuzzy__:$effectiveFuzzyMode',
      littleEndian: littleEndian,
    );
  }

  if (value.isEmpty) {
    throw ArgumentError('value 不能为空');
  }

  switch (valueType) {
    case 'text':
      final bytes = bytesMode == 'utf16le' || (bytesMode == 'auto' && littleEndian)
          ? _encodeUtf16Le(value)
          : Uint8List.fromList(utf8.encode(value));
      final prefix =
          bytesMode == 'utf16le' || (bytesMode == 'auto' && littleEndian)
          ? '__jsx_text_utf16le__:'
          : '__jsx_text_utf8__:';
      return SearchValue(
        type: SearchValueType.bytes,
        textValue: '$prefix$value',
        bytesValue: bytes,
        littleEndian: littleEndian,
      );
    case 'xor':
      return SearchValue(
        type: SearchValueType.i32,
        textValue: '__jsx_xor__:$value',
        littleEndian: littleEndian,
      );
    case 'auto':
      return SearchValue(
        type: SearchValueType.bytes,
        textValue: '__jsx_auto__:$value',
        littleEndian: littleEndian,
      );
    case 'bytes':
      final resolvedMode = bytesMode == 'auto'
          ? (_looksLikeHexByteSequence(value) ? 'hex' : 'utf8')
          : bytesMode;
      if (resolvedMode == 'hex') {
        return SearchValue(
          type: SearchValueType.bytes,
          bytesValue: _parseHexBytes(value),
          littleEndian: littleEndian,
        );
      }
      final isUtf16Le = resolvedMode == 'utf16le';
      final bytes = isUtf16Le
          ? _encodeUtf16Le(value)
          : Uint8List.fromList(utf8.encode(value));
      return SearchValue(
        type: SearchValueType.bytes,
        textValue: '${isUtf16Le ? "__jsx_text_utf16le__:" : "__jsx_text_utf8__:"}$value',
        bytesValue: bytes,
        littleEndian: littleEndian,
      );
    default:
      return SearchValue(
        type: _parseRawSearchValueType(valueType),
        textValue: value,
        littleEndian: littleEndian,
      );
  }
}

SearchValue _buildWriteValueFromToolCall(AiToolCall call) {
  final valueType = _normalizeLower(_getRequiredString(call, 'valueType'));
  final value = _getRequiredString(call, 'value').trim();
  final littleEndian = _getOptionalBool(call, 'littleEndian', true);
  final bytesMode = _normalizeLower(_getOptionalString(call, 'bytesMode', 'auto'));
  if (value.isEmpty) {
    throw ArgumentError('value 不能为空');
  }

  if (valueType == 'text') {
    final useUtf16Le = bytesMode == 'utf16le' || (bytesMode == 'auto' && littleEndian);
    final bytes = useUtf16Le
        ? _encodeUtf16Le(value)
        : Uint8List.fromList(utf8.encode(value));
    return SearchValue(
      type: SearchValueType.bytes,
      textValue:
          '${useUtf16Le ? "__jsx_text_utf16le__:" : "__jsx_text_utf8__:"}$value',
      bytesValue: bytes,
      littleEndian: littleEndian,
    );
  }

  if (valueType == 'bytes') {
    final resolvedMode = bytesMode == 'auto'
        ? (_looksLikeHexByteSequence(value) ? 'hex' : 'utf8')
        : bytesMode;
    if (resolvedMode == 'hex') {
      return SearchValue(
        type: SearchValueType.bytes,
        bytesValue: _parseHexBytes(value),
        littleEndian: littleEndian,
      );
    }
    final useUtf16Le = resolvedMode == 'utf16le';
    final bytes = useUtf16Le
        ? _encodeUtf16Le(value)
        : Uint8List.fromList(utf8.encode(value));
    return SearchValue(
      type: SearchValueType.bytes,
      textValue:
          '${useUtf16Le ? "__jsx_text_utf16le__:" : "__jsx_text_utf8__:"}$value',
      bytesValue: bytes,
      littleEndian: littleEndian,
    );
  }

  return SearchValue(
    type: _parseRawSearchValueType(valueType),
    textValue: value,
    littleEndian: littleEndian,
  );
}

PointerScanRequest _buildPointerScanRequest(
  AiToolCall call,
  MemoryAiOverlayToolRuntimeContext context,
) {
  final pointerWidth = _getOptionalInt(call, 'pointerWidth', 8);
  final maxOffset = _parseFlexibleInt(
    _getRequiredString(call, 'maxOffset'),
    argumentName: 'maxOffset',
  );
  final alignment = _getOptionalInt(call, 'alignment', pointerWidth);
  return PointerScanRequest(
    pid: context.pid,
    targetAddress: _parseRequiredAddress(call, 'targetAddress'),
    pointerWidth: pointerWidth,
    maxOffset: maxOffset,
    alignment: alignment,
    rangeSectionKeys: _getStringList(call, 'rangeSectionKeys'),
    scanAllReadableRegions: _getOptionalBool(call, 'scanAllReadableRegions', true),
  );
}

String _formatRegion(MemoryRegion region) {
  final endExclusive = region.endAddress;
  final path = region.path?.trim();
  return [
    '${_formatAddress(region.startAddress)}-${_formatAddress(endExclusive)}',
    'size=${_formatByteCount(region.size)}',
    'perms=${region.perms}',
    'anonymous=${region.isAnonymous}',
    if (path != null && path.isNotEmpty) 'path=$path',
  ].join(' | ');
}

String _formatSearchSessionState(
  SearchSessionState state, {
  required int currentPid,
}) {
  if (!state.hasActiveSession) {
    return '- 当前没有活动搜索会话';
  }
  return [
    '- hasActiveSession: true',
    '- pid: ${state.pid}${state.pid == currentPid ? " (当前进程)" : " (其他进程)"}',
    '- resultCount: ${state.resultCount}',
    '- littleEndian: ${state.littleEndian}',
  ].join('\n');
}

String _formatSearchTaskState(SearchTaskState state) {
  return [
    '- status: ${state.status.name}',
    '- processedRegions: ${state.processedRegions}/${state.totalRegions}',
    '- processedBytes: ${state.processedBytes}/${state.totalBytes}',
    '- resultCount: ${state.resultCount}',
    '- elapsedMs: ${state.elapsedMilliseconds}',
    '- canCancel: ${state.canCancel}',
    if (state.message.trim().isNotEmpty) '- message: ${state.message.trim()}',
  ].join('\n');
}

String _formatSearchResult(SearchResult result) {
  return [
    _formatAddress(result.address),
    'regionStart=${_formatAddress(result.regionStart)}',
    'regionType=${result.regionTypeKey}',
    'type=${result.type.name}',
    'value=${result.displayValue}',
    'hex=${_formatHex(result.rawBytes)}',
  ].join(' | ');
}

String _formatValuePreview(MemoryValuePreview preview) {
  return [
    _formatAddress(preview.address),
    'type=${preview.type.name}',
    'value=${preview.displayValue}',
    'hex=${_formatHex(preview.rawBytes)}',
  ].join(' | ');
}

String _formatInstructionPreview(MemoryInstructionPreview preview) {
  return [
    _formatAddress(preview.address),
    'arch=${preview.architecture}',
    'size=${preview.instructionSize}',
    'bytes=${_formatHex(preview.rawBytes)}',
    'asm=${preview.instructionText}',
  ].join(' | ');
}

String _formatFrozenMemoryValue(FrozenMemoryValue value) {
  return [
    _formatAddress(value.address),
    'type=${value.type.name}',
    'value=${value.displayValue}',
    'hex=${_formatHex(value.rawBytes)}',
  ].join(' | ');
}

String _formatBreakpointState(MemoryBreakpointState state) {
  return [
    '- isSupported: ${state.isSupported}',
    '- isProcessPaused: ${state.isProcessPaused}',
    '- activeBreakpointCount: ${state.activeBreakpointCount}',
    '- pendingHitCount: ${state.pendingHitCount}',
    '- architecture: ${state.architecture}',
    if (state.lastError.trim().isNotEmpty) '- lastError: ${state.lastError.trim()}',
  ].join('\n');
}

String _formatBreakpoint(MemoryBreakpoint breakpoint) {
  return [
    'id=${breakpoint.id}',
    'address=${_formatAddress(breakpoint.address)}',
    'type=${breakpoint.type.name}',
    'length=${breakpoint.length}',
    'access=${_formatBreakpointAccessType(breakpoint.accessType)}',
    'enabled=${breakpoint.enabled}',
    'pauseOnHit=${breakpoint.pauseProcessOnHit}',
    'hitCount=${breakpoint.hitCount}',
    if (breakpoint.lastHitAtMillis != null)
      'lastHit=${breakpoint.lastHitAtMillis}',
    if (breakpoint.lastError.trim().isNotEmpty)
      'lastError=${breakpoint.lastError.trim()}',
  ].join(' | ');
}

String _formatBreakpointHit(MemoryBreakpointHit hit) {
  return [
    'breakpointId=${hit.breakpointId}',
    'address=${_formatAddress(hit.address)}',
    'access=${_formatBreakpointAccessType(hit.accessType)}',
    'threadId=${hit.threadId}',
    'time=${hit.timestampMillis}',
    'old=${_formatHex(hit.oldValue)}',
    'new=${_formatHex(hit.newValue)}',
    'pc=${_formatAddress(hit.pc)}',
    'module=${hit.moduleName}',
    'moduleOffset=${_formatAddress(hit.moduleOffset)}',
    'instruction=${hit.instructionText}',
  ].join(' | ');
}

String _formatPointerScanSession(
  PointerScanSessionState state, {
  required int currentPid,
}) {
  if (!state.hasActiveSession) {
    return '- 当前没有活动指针扫描会话';
  }
  return [
    '- hasActiveSession: true',
    '- pid: ${state.pid}${state.pid == currentPid ? " (当前进程)" : " (其他进程)"}',
    '- targetAddress: ${_formatAddress(state.targetAddress)}',
    '- pointerWidth: ${state.pointerWidth}',
    '- maxOffset: ${_formatAddress(state.maxOffset)}',
    '- alignment: ${state.alignment}',
    '- regionCount: ${state.regionCount}',
    '- resultCount: ${state.resultCount}',
  ].join('\n');
}

String _formatPointerScanTask(PointerScanTaskState state) {
  return [
    '- status: ${state.status.name}',
    '- processedRegions: ${state.processedRegions}/${state.totalRegions}',
    '- processedEntries: ${state.processedEntries}/${state.totalEntries}',
    '- processedBytes: ${state.processedBytes}/${state.totalBytes}',
    '- resultCount: ${state.resultCount}',
    '- elapsedMs: ${state.elapsedMilliseconds}',
    '- canCancel: ${state.canCancel}',
    if (state.message.trim().isNotEmpty) '- message: ${state.message.trim()}',
  ].join('\n');
}

String _formatPointerResult(PointerScanResult result) {
  return [
    'pointer=${_formatAddress(result.pointerAddress)}',
    'base=${_formatAddress(result.baseAddress)}',
    'target=${_formatAddress(result.targetAddress)}',
    'offset=${_formatAddress(result.offset)}',
    'regionStart=${_formatAddress(result.regionStart)}',
    'regionType=${result.regionTypeKey}',
  ].join(' | ');
}

String _formatPointerChaseHint(PointerScanChaseHint hint) {
  return [
    'isTerminalStaticCandidate=${hint.isTerminalStaticCandidate}',
    'stopReasonKey=${hint.stopReasonKey}',
    if (hint.result != null) 'result=${_formatPointerResult(hint.result!)}',
  ].join('\n');
}

String _formatPointerAutoChaseState(PointerAutoChaseState state) {
  final buffer = StringBuffer()
    ..writeln('- isRunning: ${state.isRunning}')
    ..writeln('- pid: ${state.pid}')
    ..writeln('- currentDepth: ${state.currentDepth}/${state.maxDepth}');
  if (state.message.trim().isNotEmpty) {
    buffer.writeln('- message: ${state.message.trim()}');
  }
  if (state.layers.isEmpty) {
    buffer.writeln('- 当前没有追链层数据');
    return buffer.toString().trim();
  }
  buffer.writeln('- layers: ${state.layers.length}');
  for (final layer in state.layers) {
    buffer.writeln(
      '  - layer=${layer.layerIndex} target=${_formatAddress(layer.targetAddress)} selectedPointer=${layer.selectedPointerAddress == null ? "-" : _formatAddress(layer.selectedPointerAddress!)} resultCount=${layer.resultCount} hasMore=${layer.hasMore} terminal=${layer.isTerminalLayer} stopReason=${layer.stopReasonKey}',
    );
  }
  return buffer.toString().trim();
}

MemoryBreakpointAccessType _parseBreakpointAccessType(String rawValue) {
  return switch (_normalizeLower(rawValue)) {
    'read' => MemoryBreakpointAccessType.read,
    'write' => MemoryBreakpointAccessType.write,
    'readwrite' => MemoryBreakpointAccessType.readWrite,
    _ => throw ArgumentError('不支持的 accessType: $rawValue'),
  };
}

SearchValueType _parseRawSearchValueType(String rawValue) {
  return switch (_normalizeLower(rawValue)) {
    'i8' => SearchValueType.i8,
    'i16' => SearchValueType.i16,
    'i32' => SearchValueType.i32,
    'i64' => SearchValueType.i64,
    'f32' => SearchValueType.f32,
    'f64' => SearchValueType.f64,
    'bytes' || 'text' => SearchValueType.bytes,
    _ => throw ArgumentError('不支持的 valueType: $rawValue'),
  };
}

String _formatBreakpointAccessType(MemoryBreakpointAccessType type) {
  return switch (type) {
    MemoryBreakpointAccessType.read => 'read',
    MemoryBreakpointAccessType.write => 'write',
    MemoryBreakpointAccessType.readWrite => 'readWrite',
  };
}

int _resolveReadLength(SearchValueType type, int? explicitLength) {
  if (explicitLength != null && explicitLength > 0) {
    return explicitLength;
  }
  return switch (type) {
    SearchValueType.i8 => 1,
    SearchValueType.i16 => 2,
    SearchValueType.i32 || SearchValueType.f32 => 4,
    SearchValueType.i64 || SearchValueType.f64 => 8,
    SearchValueType.bytes => 16,
  };
}

int _parseRequiredAddress(AiToolCall call, String key) {
  return _parseFlexibleInt(
    _getRequiredString(call, key),
    argumentName: key,
  );
}

List<int> _parseAddressList(AiToolCall call, String key) {
  return _getStringList(call, key)
      .map((value) => _parseFlexibleInt(value, argumentName: key))
      .toList(growable: false);
}

String _getRequiredString(AiToolCall call, String key) {
  final raw = call.arguments[key];
  final value = raw?.toString().trim() ?? '';
  if (value.isEmpty) {
    throw ArgumentError('$key 不能为空');
  }
  return value;
}

String _getOptionalString(AiToolCall call, String key, String defaultValue) {
  final raw = call.arguments[key];
  final value = raw?.toString().trim();
  if (value == null || value.isEmpty) {
    return defaultValue;
  }
  return value;
}

int _getOptionalInt(AiToolCall call, String key, int defaultValue) {
  final value = _getOptionalIntOrNull(call, key);
  return value ?? defaultValue;
}

int? _getOptionalIntOrNull(AiToolCall call, String key) {
  final raw = call.arguments[key];
  if (raw == null) {
    return null;
  }
  if (raw is int) {
    return raw;
  }
  return int.tryParse(raw.toString().trim());
}

bool _getRequiredBool(AiToolCall call, String key) {
  final raw = call.arguments[key];
  if (raw is bool) {
    return raw;
  }
  if (raw is String) {
    final normalized = raw.trim().toLowerCase();
    if (normalized == 'true') {
      return true;
    }
    if (normalized == 'false') {
      return false;
    }
  }
  throw ArgumentError('$key 必须是布尔值');
}

bool _getOptionalBool(AiToolCall call, String key, bool defaultValue) {
  final raw = call.arguments[key];
  if (raw == null) {
    return defaultValue;
  }
  if (raw is bool) {
    return raw;
  }
  if (raw is String) {
    final normalized = raw.trim().toLowerCase();
    if (normalized == 'true') {
      return true;
    }
    if (normalized == 'false') {
      return false;
    }
  }
  return defaultValue;
}

List<String> _getStringList(AiToolCall call, String key) {
  final raw = call.arguments[key];
  if (raw is List) {
    return raw.map((value) => value.toString()).toList(growable: false);
  }
  if (raw is String && raw.trim().isNotEmpty) {
    return raw
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
  return const <String>[];
}

int _parseFlexibleInt(
  String rawValue, {
  required String argumentName,
}) {
  final value = rawValue.trim();
  if (value.isEmpty) {
    throw ArgumentError('$argumentName 不能为空');
  }
  final normalized = value.toLowerCase().startsWith('0x')
      ? value.substring(2)
      : value;
  final radix = value.toLowerCase().startsWith('0x') ? 16 : 10;
  final parsed = int.tryParse(normalized, radix: radix);
  if (parsed == null) {
    throw ArgumentError('$argumentName 不是合法整数: $rawValue');
  }
  return parsed;
}

String _normalizeLower(String value) {
  return value.trim().toLowerCase();
}

String _formatAddress(int value) {
  return '0x${value.toRadixString(16).toUpperCase()}';
}

String _formatByteCount(int value) {
  if (value >= 1024 * 1024) {
    return '${(value / (1024 * 1024)).toStringAsFixed(2)}MB';
  }
  if (value >= 1024) {
    return '${(value / 1024).toStringAsFixed(2)}KB';
  }
  return '${value}B';
}

String _formatHex(Uint8List bytes) {
  if (bytes.isEmpty) {
    return '(empty)';
  }
  return bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(' ');
}

bool _looksLikeHexByteSequence(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    return false;
  }
  final sanitized = normalized
      .replaceAll(RegExp(r'0x', caseSensitive: false), '')
      .replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
  return sanitized.isNotEmpty && sanitized.length.isEven;
}

Uint8List _parseHexBytes(String value) {
  final sanitized = value
      .replaceAll(RegExp(r'0x', caseSensitive: false), '')
      .replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
  if (sanitized.isEmpty || sanitized.length.isOdd) {
    throw const FormatException('非法字节序列');
  }
  final bytes = <int>[];
  for (var index = 0; index < sanitized.length; index += 2) {
    final byte = int.tryParse(
      sanitized.substring(index, index + 2),
      radix: 16,
    );
    if (byte == null) {
      throw const FormatException('非法字节序列');
    }
    bytes.add(byte);
  }
  return Uint8List.fromList(bytes);
}

Uint8List _encodeUtf16Le(String value) {
  final bytes = <int>[];
  for (final unit in value.codeUnits) {
    bytes.add(unit & 0xFF);
    bytes.add((unit >> 8) & 0xFF);
  }
  return Uint8List.fromList(bytes);
}

const Set<String> _supportedFuzzyModes = <String>{
  'unknown',
  'unchanged',
  'changed',
  'increased',
  'decreased',
};
