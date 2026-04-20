import 'package:JsxposedX/features/ai/domain/models/ai_tool_definition.dart';

class MemoryAiOverlayToolDefinitions {
  MemoryAiOverlayToolDefinitions._();

  static const List<String> _rawValueTypes = <String>[
    'i8',
    'i16',
    'i32',
    'i64',
    'f32',
    'f64',
    'bytes',
  ];

  static const List<String> _searchValueTypes = <String>[
    ..._rawValueTypes,
    'text',
    'xor',
    'auto',
  ];

  static const List<String> _writeValueTypes = <String>[
    ..._rawValueTypes,
    'text',
  ];

  static const List<String> _bytesModes = <String>[
    'auto',
    'hex',
    'utf8',
    'utf16le',
  ];

  static const List<String> _matchModes = <String>['exact', 'fuzzy'];
  static const List<String> _fuzzyModes = <String>[
    'unknown',
    'unchanged',
    'changed',
    'increased',
    'decreased',
  ];

  static const List<String> _breakpointAccessTypes = <String>[
    'read',
    'write',
    'readWrite',
  ];

  static final getProcessSummary = AiToolDefinition(
    name: 'get_process_summary',
    description: '获取当前内存工具目标进程的总览，包括暂停状态、搜索会话、断点状态、冻结值数量和指针扫描状态',
    parameters: ToolParametersBuilder.empty(),
  );

  static final listMemoryRegions = AiToolDefinition(
    name: 'list_memory_regions',
    description: '列出当前进程的内存区间，可用于确认可读区域、路径和权限',
    parameters: (ToolParametersBuilder()
          ..addInteger('offset', '分页偏移，默认 0')
          ..addInteger('limit', '分页大小，默认 50')
          ..addBoolean('readableOnly', '是否仅查看可读内存，默认 true')
          ..addBoolean('includeAnonymous', '是否包含匿名映射，默认 true')
          ..addBoolean('includeFileBacked', '是否包含文件映射，默认 true'))
        .build(),
  );

  static final getSearchOverview = AiToolDefinition(
    name: 'get_search_overview',
    description: '获取当前搜索会话与搜索任务状态，确认是否已有结果、是否仍在运行以及是否属于当前进程',
    parameters: ToolParametersBuilder.empty(),
  );

  static final getSearchResults = AiToolDefinition(
    name: 'get_search_results',
    description: '读取当前搜索结果列表，返回地址、区域、类型、显示值和原始字节摘要',
    parameters: (ToolParametersBuilder()
          ..addInteger('offset', '分页偏移，默认 0')
          ..addInteger('limit', '分页大小，默认 50'))
        .build(),
  );

  static final startFirstScan = AiToolDefinition(
    name: 'start_first_scan',
    description: '对当前进程发起首次内存搜索，支持精确搜索、文本搜索、XOR 搜索、自动类型搜索和数值模糊搜索',
    parameters: (ToolParametersBuilder()
          ..addString(
            'valueType',
            '搜索值类型：i8/i16/i32/i64/f32/f64/bytes/text/xor/auto',
            required: true,
            enumValues: _searchValueTypes,
          )
          ..addString(
            'matchMode',
            '匹配模式：exact 或 fuzzy。fuzzy 仅适用于数值类型',
            enumValues: _matchModes,
          )
          ..addString('value', '搜索值；fuzzy 模式下可留空')
          ..addBoolean('littleEndian', '是否按小端处理，默认 true')
          ..addString(
            'fuzzyMode',
            '模糊搜索模式：unknown/unchanged/changed/increased/decreased',
            enumValues: _fuzzyModes,
          )
          ..addString(
            'bytesMode',
            'bytes/text 写法的编码方式：auto/hex/utf8/utf16le',
            enumValues: _bytesModes,
          )
          ..addStringArray(
            'rangeSectionKeys',
            '范围分区 key 列表，如 anonymous/java/cAlloc/cData/codeApp/codeSys/stack/ashmem/other 等',
          )
          ..addBoolean('scanAllReadableRegions', '是否扫描全部可读区，默认 true'))
        .build(),
  );

  static final continueNextScan = AiToolDefinition(
    name: 'continue_next_scan',
    description: '基于当前搜索会话继续筛选结果，参数与首次搜索类似，但 fuzzy 模式通常应传 changed/unchanged/increased/decreased',
    parameters: (ToolParametersBuilder()
          ..addString(
            'valueType',
            '筛选值类型：i8/i16/i32/i64/f32/f64/bytes/text/xor/auto',
            required: true,
            enumValues: _searchValueTypes,
          )
          ..addString(
            'matchMode',
            '匹配模式：exact 或 fuzzy。fuzzy 仅适用于数值类型',
            enumValues: _matchModes,
          )
          ..addString('value', '筛选值；fuzzy 模式下可留空')
          ..addBoolean('littleEndian', '是否按小端处理，默认 true')
          ..addString(
            'fuzzyMode',
            '模糊筛选模式：unchanged/changed/increased/decreased',
            enumValues: _fuzzyModes,
          )
          ..addString(
            'bytesMode',
            'bytes/text 写法的编码方式：auto/hex/utf8/utf16le',
            enumValues: _bytesModes,
          ))
        .build(),
  );

  static final cancelSearch = AiToolDefinition(
    name: 'cancel_search',
    description: '取消当前仍在运行的搜索任务',
    parameters: ToolParametersBuilder.empty(),
  );

  static final resetSearchSession = AiToolDefinition(
    name: 'reset_search_session',
    description: '重置当前搜索会话并清空搜索结果',
    parameters: ToolParametersBuilder.empty(),
  );

  static final readMemory = AiToolDefinition(
    name: 'read_memory',
    description: '读取一个或多个地址的当前内存值。读取 bytes 时如果不传 length 会使用默认长度',
    parameters: (ToolParametersBuilder()
          ..addStringArray(
            'addresses',
            '待读取地址数组，元素可为十六进制或十进制字符串',
            required: true,
          )
          ..addString(
            'valueType',
            '读取类型：i8/i16/i32/i64/f32/f64/bytes',
            required: true,
            enumValues: _rawValueTypes,
          )
          ..addInteger('length', '读取长度；bytes 类型推荐显式传入'))
        .build(),
  );

  static final disassembleMemory = AiToolDefinition(
    name: 'disassemble_memory',
    description: '反汇编一个或多个地址附近的指令',
    parameters: (ToolParametersBuilder()
          ..addStringArray(
            'addresses',
            '待反汇编地址数组，元素可为十六进制或十进制字符串',
            required: true,
          ))
        .build(),
  );

  static final writeMemoryValue = AiToolDefinition(
    name: 'write_memory_value',
    description: '向指定地址写入新值，支持数值、字节序列和文本字节写入',
    parameters: (ToolParametersBuilder()
          ..addString('address', '目标地址', required: true)
          ..addString(
            'valueType',
            '写入值类型：i8/i16/i32/i64/f32/f64/bytes/text',
            required: true,
            enumValues: _writeValueTypes,
          )
          ..addString('value', '要写入的值', required: true)
          ..addBoolean('littleEndian', '是否按小端处理，默认 true')
          ..addString(
            'bytesMode',
            'bytes/text 写法的编码方式：auto/hex/utf8/utf16le',
            enumValues: _bytesModes,
          ))
        .build(),
  );

  static final patchMemoryInstruction = AiToolDefinition(
    name: 'patch_memory_instruction',
    description: '将指定地址的机器指令改写为新的汇编指令文本',
    parameters: (ToolParametersBuilder()
          ..addString('address', '目标指令地址', required: true)
          ..addString('instruction', '新的汇编指令文本', required: true))
        .build(),
  );

  static final setMemoryFreeze = AiToolDefinition(
    name: 'set_memory_freeze',
    description: '对指定地址启用或关闭冻结值。启用时需要同时提供冻结值',
    parameters: (ToolParametersBuilder()
          ..addString('address', '目标地址', required: true)
          ..addString(
            'valueType',
            '冻结值类型：i8/i16/i32/i64/f32/f64/bytes/text',
            required: true,
            enumValues: _writeValueTypes,
          )
          ..addString('value', '冻结值', required: true)
          ..addBoolean('enabled', '是否启用冻结', required: true)
          ..addBoolean('littleEndian', '是否按小端处理，默认 true')
          ..addString(
            'bytesMode',
            'bytes/text 写法的编码方式：auto/hex/utf8/utf16le',
            enumValues: _bytesModes,
          ))
        .build(),
  );

  static final listFrozenMemoryValues = AiToolDefinition(
    name: 'list_frozen_memory_values',
    description: '列出当前进程已冻结的地址和值',
    parameters: ToolParametersBuilder.empty(),
  );

  static final setProcessPaused = AiToolDefinition(
    name: 'set_process_paused',
    description: '暂停或恢复当前目标进程',
    parameters: (ToolParametersBuilder()
          ..addBoolean('paused', 'true 表示暂停，false 表示恢复', required: true))
        .build(),
  );

  static final getBreakpointOverview = AiToolDefinition(
    name: 'get_breakpoint_overview',
    description: '获取当前进程断点支持状态、暂停状态、活动断点数和待处理命中数',
    parameters: ToolParametersBuilder.empty(),
  );

  static final listMemoryBreakpoints = AiToolDefinition(
    name: 'list_memory_breakpoints',
    description: '列出当前进程的所有内存断点',
    parameters: ToolParametersBuilder.empty(),
  );

  static final getMemoryBreakpointHits = AiToolDefinition(
    name: 'get_memory_breakpoint_hits',
    description: '列出当前进程最近的断点命中记录',
    parameters: (ToolParametersBuilder()
          ..addInteger('offset', '分页偏移，默认 0')
          ..addInteger('limit', '分页大小，默认 50'))
        .build(),
  );

  static final addMemoryBreakpoint = AiToolDefinition(
    name: 'add_memory_breakpoint',
    description: '在指定地址添加内存断点，可设置读/写/读写访问类型及命中后是否暂停进程',
    parameters: (ToolParametersBuilder()
          ..addString('address', '断点地址', required: true)
          ..addString(
            'valueType',
            '断点值类型：i8/i16/i32/i64/f32/f64/bytes',
            required: true,
            enumValues: _rawValueTypes,
          )
          ..addInteger('length', '监控长度；不传时按类型默认长度')
          ..addString(
            'accessType',
            '断点访问类型：read/write/readWrite',
            required: true,
            enumValues: _breakpointAccessTypes,
          )
          ..addBoolean('enabled', '创建后是否立即启用，默认 true')
          ..addBoolean('pauseProcessOnHit', '命中后是否暂停进程，默认 true'))
        .build(),
  );

  static final removeMemoryBreakpoint = AiToolDefinition(
    name: 'remove_memory_breakpoint',
    description: '删除指定断点',
    parameters: (ToolParametersBuilder()
          ..addString('breakpointId', '断点 ID', required: true))
        .build(),
  );

  static final setMemoryBreakpointEnabled = AiToolDefinition(
    name: 'set_memory_breakpoint_enabled',
    description: '启用或禁用指定断点',
    parameters: (ToolParametersBuilder()
          ..addString('breakpointId', '断点 ID', required: true)
          ..addBoolean('enabled', '是否启用', required: true))
        .build(),
  );

  static final clearMemoryBreakpointHits = AiToolDefinition(
    name: 'clear_memory_breakpoint_hits',
    description: '清空当前进程断点命中记录',
    parameters: ToolParametersBuilder.empty(),
  );

  static final resumeAfterBreakpoint = AiToolDefinition(
    name: 'resume_after_breakpoint',
    description: '在断点暂停后恢复当前进程执行',
    parameters: ToolParametersBuilder.empty(),
  );

  static final getPointerScanOverview = AiToolDefinition(
    name: 'get_pointer_scan_overview',
    description: '获取当前指针扫描会话和任务状态',
    parameters: ToolParametersBuilder.empty(),
  );

  static final getPointerScanResults = AiToolDefinition(
    name: 'get_pointer_scan_results',
    description: '读取当前指针扫描结果列表',
    parameters: (ToolParametersBuilder()
          ..addInteger('offset', '分页偏移，默认 0')
          ..addInteger('limit', '分页大小，默认 50'))
        .build(),
  );

  static final getPointerScanChaseHint = AiToolDefinition(
    name: 'get_pointer_scan_chase_hint',
    description: '获取当前指针扫描的自动追链提示',
    parameters: ToolParametersBuilder.empty(),
  );

  static final startPointerScan = AiToolDefinition(
    name: 'start_pointer_scan',
    description: '从目标地址开始进行指针扫描',
    parameters: (ToolParametersBuilder()
          ..addString('targetAddress', '目标地址', required: true)
          ..addInteger('pointerWidth', '指针宽度，一般为 4 或 8', required: true)
          ..addString('maxOffset', '最大偏移，可传十六进制或十进制字符串', required: true)
          ..addInteger(
            'alignment',
            '对齐字节数；不传则默认跟随 pointerWidth',
          )
          ..addStringArray(
            'rangeSectionKeys',
            '范围分区 key 列表，如 anonymous/java/cAlloc/cData/codeApp/codeSys/stack/ashmem/other 等',
          )
          ..addBoolean('scanAllReadableRegions', '是否扫描全部可读区，默认 true'))
        .build(),
  );

  static final cancelPointerScan = AiToolDefinition(
    name: 'cancel_pointer_scan',
    description: '取消当前指针扫描任务',
    parameters: ToolParametersBuilder.empty(),
  );

  static final resetPointerScanSession = AiToolDefinition(
    name: 'reset_pointer_scan_session',
    description: '重置当前指针扫描会话',
    parameters: ToolParametersBuilder.empty(),
  );

  static final getPointerAutoChaseOverview = AiToolDefinition(
    name: 'get_pointer_auto_chase_overview',
    description: '获取当前自动追链状态，包括层数、进度、是否仍在运行和停止原因',
    parameters: ToolParametersBuilder.empty(),
  );

  static final getPointerAutoChaseLayerResults = AiToolDefinition(
    name: 'get_pointer_auto_chase_layer_results',
    description: '读取自动追链指定层的指针结果',
    parameters: (ToolParametersBuilder()
          ..addInteger('layerIndex', '追链层索引', required: true)
          ..addInteger('offset', '分页偏移，默认 0')
          ..addInteger('limit', '分页大小，默认 50'))
        .build(),
  );

  static final startPointerAutoChase = AiToolDefinition(
    name: 'start_pointer_auto_chase',
    description: '从目标地址开始执行自动指针追链',
    parameters: (ToolParametersBuilder()
          ..addString('targetAddress', '目标地址', required: true)
          ..addInteger('pointerWidth', '指针宽度，一般为 4 或 8', required: true)
          ..addString('maxOffset', '最大偏移，可传十六进制或十进制字符串', required: true)
          ..addInteger(
            'alignment',
            '对齐字节数；不传则默认跟随 pointerWidth',
          )
          ..addInteger('maxDepth', '最大追链层数', required: true)
          ..addStringArray(
            'rangeSectionKeys',
            '范围分区 key 列表，如 anonymous/java/cAlloc/cData/codeApp/codeSys/stack/ashmem/other 等',
          )
          ..addBoolean('scanAllReadableRegions', '是否扫描全部可读区，默认 true'))
        .build(),
  );

  static final cancelPointerAutoChase = AiToolDefinition(
    name: 'cancel_pointer_auto_chase',
    description: '取消当前自动指针追链任务',
    parameters: ToolParametersBuilder.empty(),
  );

  static final resetPointerAutoChase = AiToolDefinition(
    name: 'reset_pointer_auto_chase',
    description: '重置当前自动指针追链状态',
    parameters: ToolParametersBuilder.empty(),
  );

  static final List<AiToolDefinition> all = <AiToolDefinition>[
    getProcessSummary,
    listMemoryRegions,
    getSearchOverview,
    getSearchResults,
    startFirstScan,
    continueNextScan,
    cancelSearch,
    resetSearchSession,
    readMemory,
    disassembleMemory,
    writeMemoryValue,
    patchMemoryInstruction,
    setMemoryFreeze,
    listFrozenMemoryValues,
    setProcessPaused,
    getBreakpointOverview,
    listMemoryBreakpoints,
    getMemoryBreakpointHits,
    addMemoryBreakpoint,
    removeMemoryBreakpoint,
    setMemoryBreakpointEnabled,
    clearMemoryBreakpointHits,
    resumeAfterBreakpoint,
    getPointerScanOverview,
    getPointerScanResults,
    getPointerScanChaseHint,
    startPointerScan,
    cancelPointerScan,
    resetPointerScanSession,
    getPointerAutoChaseOverview,
    getPointerAutoChaseLayerResults,
    startPointerAutoChase,
    cancelPointerAutoChase,
    resetPointerAutoChase,
  ];
}
