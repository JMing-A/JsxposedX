import 'dart:async';
import 'dart:typed_data';

import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/providers/memory_breakpoint_provider.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/providers/memory_query_provider.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/widgets/memory_tool_result_selection_bar.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/widgets/memory_tool_result_stats_bar.dart';
import 'package:JsxposedX/generated/memory_tool.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class MemoryToolDebugTab extends HookConsumerWidget {
  const MemoryToolDebugTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedProcess = ref.watch(memoryToolSelectedProcessProvider);
    final pid = selectedProcess?.pid;
    final selectedBreakpointId = ref.watch(memoryBreakpointSelectedIdProvider);
    final breakpointActionState = ref.watch(memoryBreakpointActionProvider);
    final selectedHitKey = useState<String?>(null);
    final compactTabController = useTabController(initialLength: 3);
    final landscapeDetailTabController = useTabController(initialLength: 2);
    final stateAsync = pid == null
        ? AsyncValue<MemoryBreakpointState>.data(
            MemoryBreakpointState(
              isSupported: true,
              isProcessPaused: false,
              activeBreakpointCount: 0,
              pendingHitCount: 0,
              architecture: '',
              lastError: '',
            ),
          )
        : ref.watch(getMemoryBreakpointStateProvider(pid: pid));
    final breakpointsAsync = pid == null
        ? const AsyncValue<List<MemoryBreakpoint>>.data(<MemoryBreakpoint>[])
        : ref.watch(getMemoryBreakpointsProvider(pid: pid));
    final hitsAsync = pid == null
        ? const AsyncValue<List<MemoryBreakpointHit>>.data(<MemoryBreakpointHit>[])
        : ref.watch(getMemoryBreakpointHitsProvider(pid: pid));
    final breakpoints = breakpointsAsync.asData?.value ?? const <MemoryBreakpoint>[];
    final allHits = hitsAsync.asData?.value ?? const <MemoryBreakpointHit>[];

    useEffect(() {
      selectedHitKey.value = null;
      compactTabController.index = 0;
      landscapeDetailTabController.index = 0;
      return null;
    }, [pid]);

    useEffect(() {
      if (pid == null) {
        return null;
      }
      final timer = Timer.periodic(const Duration(milliseconds: 700), (_) {
        ref.invalidate(getMemoryBreakpointStateProvider(pid: pid));
        ref.invalidate(getMemoryBreakpointsProvider(pid: pid));
        ref.invalidate(getMemoryBreakpointHitsProvider(pid: pid));
      });
      return timer.cancel;
    }, [pid]);

    useEffect(() {
      if (pid == null) {
        return null;
      }
      if (breakpoints.isEmpty) {
        if (selectedBreakpointId != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref.read(memoryBreakpointSelectedIdProvider.notifier).clear();
          });
        }
        return null;
      }
      final hasSelection = breakpoints.any(
        (breakpoint) => breakpoint.id == selectedBreakpointId,
      );
      if (!hasSelection) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref
              .read(memoryBreakpointSelectedIdProvider.notifier)
              .set(breakpoints.first.id);
        });
      }
      return null;
    }, [pid, breakpoints, selectedBreakpointId]);

    final selectedBreakpoint = _resolveSelectedBreakpoint(
      breakpoints: breakpoints,
      selectedBreakpointId: selectedBreakpointId,
    );
    final hits = selectedBreakpoint == null
        ? const <MemoryBreakpointHit>[]
        : allHits
              .where((hit) => hit.breakpointId == selectedBreakpoint.id)
              .toList(growable: false);

    useEffect(() {
      if (pid == null) {
        return null;
      }
      final currentKey = selectedHitKey.value;
      if (hits.isEmpty) {
        if (currentKey != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            selectedHitKey.value = null;
          });
        }
        return null;
      }
      final hasSelection = hits.any((hit) => _buildHitKey(hit) == currentKey);
      if (!hasSelection) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          selectedHitKey.value = _buildHitKey(hits.first);
        });
      }
      return null;
    }, [pid, selectedBreakpoint?.id, hits, selectedHitKey.value]);

    final selectedHit = _resolveSelectedHit(
      hits: hits,
      selectedHitKey: selectedHitKey.value,
    );
    final state = stateAsync.asData?.value;
    final isPaused = state?.isProcessPaused ?? false;

    if (pid == null) {
      return Padding(
        padding: EdgeInsets.all(12.r),
        child: const _DebugProcessEmptyState(),
      );
    }

    Future<void> refreshAll() async {
      ref.invalidate(getMemoryBreakpointStateProvider(pid: pid));
      ref.invalidate(getMemoryBreakpointsProvider(pid: pid));
      ref.invalidate(getMemoryBreakpointHitsProvider(pid: pid));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isLandscape = constraints.maxWidth > constraints.maxHeight;
        final isWide = constraints.maxWidth >= 1280 && constraints.maxHeight >= 480;
        final isMedium = constraints.maxWidth >= 760;
        final isShortHeight = constraints.maxHeight < 320;
        final useLandscapeWorkbench = isLandscape && isMedium && !isWide;
        final outerSpacing = isShortHeight ? 6.r : 8.r;
        final workbenchPadding = isShortHeight ? 8.r : 10.r;

        final breakpointPanel = _DebugSection(
          title: context.isZh ? '断点列表' : 'Breakpoints',
          child: _BreakpointList(
            breakpointsAsync: breakpointsAsync,
            selectedBreakpointId: selectedBreakpoint?.id,
            onSelect: (breakpointId) {
              ref
                  .read(memoryBreakpointSelectedIdProvider.notifier)
                  .set(breakpointId);
              if (useLandscapeWorkbench) {
                landscapeDetailTabController.animateTo(0);
              } else if (!isMedium) {
                compactTabController.animateTo(1);
              }
            },
            onToggleEnabled: (breakpoint) async {
              await ref
                  .read(memoryBreakpointActionProvider.notifier)
                  .setMemoryBreakpointEnabled(
                    pid: pid,
                    breakpointId: breakpoint.id,
                    enabled: !breakpoint.enabled,
                  );
            },
            onRemove: (breakpoint) async {
              await ref
                  .read(memoryBreakpointActionProvider.notifier)
                  .removeMemoryBreakpoint(
                    pid: pid,
                    breakpointId: breakpoint.id,
                  );
            },
          ),
        );

        final hitPanel = _DebugSection(
          title: context.isZh ? '命中记录' : 'Hit Records',
          child: _HitList(
            hitsAsync: hitsAsync,
            selectedBreakpointId: selectedBreakpoint?.id,
            selectedHitKey: selectedHitKey.value,
            onSelectHit: (hit) {
              ref
                  .read(memoryBreakpointSelectedIdProvider.notifier)
                  .set(hit.breakpointId);
              selectedHitKey.value = _buildHitKey(hit);
              if (useLandscapeWorkbench) {
                landscapeDetailTabController.animateTo(1);
              } else if (!isMedium) {
                compactTabController.animateTo(2);
              }
            },
          ),
        );

        final detailPanel = _DebugSection(
          title: context.isZh ? '命中详情' : 'Hit Detail',
          child: _HitDetail(
            hit: selectedHit,
            breakpoint: selectedBreakpoint,
          ),
        );

        final body = isWide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(flex: 9, child: breakpointPanel),
                  _PanelDivider(vertical: true),
                  Expanded(flex: 10, child: hitPanel),
                  _PanelDivider(vertical: true),
                  Expanded(flex: 11, child: detailPanel),
                ],
              )
            : useLandscapeWorkbench
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Expanded(
                        flex: constraints.maxWidth >= 960 ? 8 : 9,
                        child: breakpointPanel,
                      ),
                      _PanelDivider(vertical: true),
                      Expanded(
                        flex: constraints.maxWidth >= 960 ? 14 : 12,
                        child: _LandscapeDetailWorkbench(
                          controller: landscapeDetailTabController,
                          hitPanel: hitPanel,
                          detailPanel: detailPanel,
                        ),
                      ),
                    ],
                  )
            : isMedium
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Expanded(flex: 9, child: breakpointPanel),
                      _PanelDivider(vertical: true),
                      Expanded(
                        flex: 12,
                        child: Column(
                          children: <Widget>[
                            Expanded(child: hitPanel),
                            _PanelDivider(vertical: false),
                            Expanded(child: detailPanel),
                          ],
                        ),
                      ),
                    ],
                  )
                : _CompactWorkbench(
                    controller: compactTabController,
                    breakpointPanel: breakpointPanel,
                    hitPanel: hitPanel,
                    detailPanel: detailPanel,
                  );

        return Padding(
          padding: EdgeInsets.all(isShortHeight ? 8.r : 12.r),
          child: Column(
            children: <Widget>[
              MemoryToolResultSelectionBar(
                actions: <MemoryToolResultSelectionActionData>[
                  MemoryToolResultSelectionActionData(
                    icon: Icons.refresh_rounded,
                    onTap: breakpointActionState.isLoading ? null : refreshAll,
                  ),
                  MemoryToolResultSelectionActionData(
                    icon: Icons.play_arrow_rounded,
                    onTap: breakpointActionState.isLoading || !isPaused
                        ? null
                        : () async {
                            await ref
                                .read(memoryBreakpointActionProvider.notifier)
                                .resumeAfterBreakpoint(pid: pid);
                          },
                  ),
                  MemoryToolResultSelectionActionData(
                    icon: Icons.layers_clear_rounded,
                    onTap: breakpointActionState.isLoading
                        ? null
                        : () async {
                            await ref
                                .read(memoryBreakpointActionProvider.notifier)
                                .clearMemoryBreakpointHits(pid: pid);
                          },
                  ),
                ],
              ),
              SizedBox(height: outerSpacing),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: context.colorScheme.surface.withValues(alpha: 0.84),
                    borderRadius: BorderRadius.circular(14.r),
                    border: Border.all(
                      color: context.colorScheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(workbenchPadding),
                    child: body,
                  ),
                ),
              ),
              if (!useLandscapeWorkbench) ...<Widget>[
                SizedBox(height: isShortHeight ? 4.r : 6.r),
                _DebugStatsBar(
                  state: state,
                  selectedBreakpoint: selectedBreakpoint,
                  hitCount: hits.length,
                  breakpointCount: breakpoints.length,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _CompactWorkbench extends StatelessWidget {
  const _CompactWorkbench({
    required this.controller,
    required this.breakpointPanel,
    required this.hitPanel,
    required this.detailPanel,
  });

  final TabController controller;
  final Widget breakpointPanel;
  final Widget hitPanel;
  final Widget detailPanel;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        TabBar(
          controller: controller,
          dividerColor: Colors.transparent,
          indicatorSize: TabBarIndicatorSize.tab,
          indicator: BoxDecoration(
            borderRadius: BorderRadius.circular(10.r),
            color: context.colorScheme.primary.withValues(alpha: 0.12),
          ),
          labelColor: context.colorScheme.primary,
          unselectedLabelColor: context.colorScheme.onSurfaceVariant,
          labelStyle: context.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
          tabs: <Widget>[
            Tab(text: context.isZh ? '断点' : 'Breakpoints'),
            Tab(text: context.isZh ? '命中' : 'Hits'),
            Tab(text: context.isZh ? '详情' : 'Detail'),
          ],
        ),
        SizedBox(height: 10.r),
        Expanded(
          child: TabBarView(
            controller: controller,
            children: <Widget>[
              breakpointPanel,
              hitPanel,
              detailPanel,
            ],
          ),
        ),
      ],
    );
  }
}

class _LandscapeDetailWorkbench extends StatelessWidget {
  const _LandscapeDetailWorkbench({
    required this.controller,
    required this.hitPanel,
    required this.detailPanel,
  });

  final TabController controller;
  final Widget hitPanel;
  final Widget detailPanel;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: context.colorScheme.surfaceContainerHighest.withValues(alpha: 0.34),
            borderRadius: BorderRadius.circular(10.r),
          ),
          child: TabBar(
            controller: controller,
            dividerColor: Colors.transparent,
            indicatorSize: TabBarIndicatorSize.tab,
            indicator: BoxDecoration(
              borderRadius: BorderRadius.circular(10.r),
              color: context.colorScheme.primary.withValues(alpha: 0.12),
            ),
            labelColor: context.colorScheme.primary,
            unselectedLabelColor: context.colorScheme.onSurfaceVariant,
            labelStyle: context.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
            tabs: <Widget>[
              Tab(text: context.isZh ? '命中记录' : 'Hits'),
              Tab(text: context.isZh ? '命中详情' : 'Detail'),
            ],
          ),
        ),
        SizedBox(height: 8.r),
        Expanded(
          child: TabBarView(
            controller: controller,
            children: <Widget>[
              hitPanel,
              detailPanel,
            ],
          ),
        ),
      ],
    );
  }
}

class _DebugSection extends StatelessWidget {
  const _DebugSection({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: context.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(height: 8.r),
        Expanded(child: child),
      ],
    );
  }
}

class _BreakpointList extends StatelessWidget {
  const _BreakpointList({
    required this.breakpointsAsync,
    required this.selectedBreakpointId,
    required this.onSelect,
    required this.onToggleEnabled,
    required this.onRemove,
  });

  final AsyncValue<List<MemoryBreakpoint>> breakpointsAsync;
  final String? selectedBreakpointId;
  final ValueChanged<String> onSelect;
  final Future<void> Function(MemoryBreakpoint breakpoint) onToggleEnabled;
  final Future<void> Function(MemoryBreakpoint breakpoint) onRemove;

  @override
  Widget build(BuildContext context) {
    return breakpointsAsync.when(
      data: (breakpoints) {
        if (breakpoints.isEmpty) {
          return _DebugEmptyState(
            message: context.isZh ? '还没有断点' : 'No breakpoints yet',
          );
        }
        return ListView.separated(
          padding: EdgeInsets.zero,
          itemCount: breakpoints.length,
          separatorBuilder: (_, _) => SizedBox(height: 6.r),
          itemBuilder: (context, index) {
            final breakpoint = breakpoints[index];
            final isSelected = breakpoint.id == selectedBreakpointId;
            return _ListItemShell(
              selected: isSelected,
              onTap: () {
                onSelect(breakpoint.id);
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '0x${breakpoint.address.toRadixString(16).toUpperCase()}',
                          style: context.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      _InlineChip(
                        text: breakpoint.enabled
                            ? (context.isZh ? '已启用' : 'Enabled')
                            : (context.isZh ? '已禁用' : 'Disabled'),
                        active: breakpoint.enabled,
                      ),
                    ],
                  ),
                  SizedBox(height: 6.r),
                  Wrap(
                    spacing: 6.r,
                    runSpacing: 6.r,
                    children: <Widget>[
                      _InlineChip(
                        text: _mapAccessType(context, breakpoint.accessType),
                      ),
                      _InlineChip(text: '${breakpoint.length}B'),
                      _InlineChip(
                        text: breakpoint.pauseProcessOnHit
                            ? (context.isZh ? '命中即暂停' : 'Pause On Hit')
                            : (context.isZh ? '仅记录' : 'Record Only'),
                      ),
                      _InlineChip(
                        text: '${breakpoint.hitCount}${context.isZh ? ' 次命中' : ' hits'}',
                      ),
                    ],
                  ),
                  if (breakpoint.lastHitAtMillis != null) ...<Widget>[
                    SizedBox(height: 6.r),
                    Text(
                      context.isZh
                          ? '最近命中 ${_formatTimestamp(breakpoint.lastHitAtMillis!)}'
                          : 'Last hit ${_formatTimestamp(breakpoint.lastHitAtMillis!)}',
                      style: context.textTheme.bodySmall?.copyWith(
                        color: context.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (breakpoint.lastError.isNotEmpty) ...<Widget>[
                    SizedBox(height: 6.r),
                    Text(
                      breakpoint.lastError,
                      style: context.textTheme.bodySmall?.copyWith(
                        color: context.colorScheme.error,
                      ),
                    ),
                  ],
                  SizedBox(height: 6.r),
                  Row(
                    children: <Widget>[
                      Switch.adaptive(
                        value: breakpoint.enabled,
                        onChanged: (_) async {
                          await onToggleEnabled(breakpoint);
                        },
                      ),
                      const Spacer(),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () async {
                          await onRemove(breakpoint);
                        },
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
      error: (error, _) => _DebugEmptyState(message: error.toString()),
      loading: () => const Center(child: CircularProgressIndicator.adaptive()),
    );
  }

  String _mapAccessType(BuildContext context, MemoryBreakpointAccessType type) {
    return switch (type) {
      MemoryBreakpointAccessType.read => context.isZh ? '读' : 'Read',
      MemoryBreakpointAccessType.write => context.isZh ? '写' : 'Write',
      MemoryBreakpointAccessType.readWrite => context.isZh ? '读写' : 'Read/Write',
    };
  }
}

class _HitList extends StatelessWidget {
  const _HitList({
    required this.hitsAsync,
    required this.selectedBreakpointId,
    required this.selectedHitKey,
    required this.onSelectHit,
  });

  final AsyncValue<List<MemoryBreakpointHit>> hitsAsync;
  final String? selectedBreakpointId;
  final String? selectedHitKey;
  final ValueChanged<MemoryBreakpointHit> onSelectHit;

  @override
  Widget build(BuildContext context) {
    return hitsAsync.when(
      data: (allHits) {
        if (selectedBreakpointId == null) {
          return _DebugEmptyState(
            message: context.isZh ? '先选择一个断点' : 'Select a breakpoint first',
          );
        }
        final hits = allHits
            .where((hit) => hit.breakpointId == selectedBreakpointId)
            .toList(growable: false);
        if (hits.isEmpty) {
          return _DebugEmptyState(
            message: context.isZh ? '这个断点还没有命中' : 'No hits for the selected breakpoint',
          );
        }
        return ListView.separated(
          padding: EdgeInsets.zero,
          itemCount: hits.length,
          separatorBuilder: (_, _) => SizedBox(height: 6.r),
          itemBuilder: (context, index) {
            final hit = hits[index];
            final isSelected = _buildHitKey(hit) == selectedHitKey;
            return _ListItemShell(
              selected: isSelected,
              onTap: () {
                onSelectHit(hit);
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          _formatTimestamp(hit.timestampMillis),
                          style: context.textTheme.bodySmall?.copyWith(
                            color: context.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      _InlineChip(text: 'TID ${hit.threadId}'),
                    ],
                  ),
                  SizedBox(height: 4.r),
                  Text(
                    'PC 0x${hit.pc.toRadixString(16).toUpperCase()}',
                    style: context.textTheme.bodyMedium?.copyWith(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 3.r),
                  if (hit.instructionText.isNotEmpty) ...<Widget>[
                    Text(
                      _formatInstruction(hit.instructionText),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 3.r),
                  ],
                  Text(
                    '${hit.moduleName.isEmpty ? '[anonymous]' : hit.moduleName}+0x${hit.moduleOffset.toRadixString(16).toUpperCase()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
      error: (error, _) => _DebugEmptyState(message: error.toString()),
      loading: () => const Center(child: CircularProgressIndicator.adaptive()),
    );
  }

  String _hex(Uint8List bytes) {
    if (bytes.isEmpty) {
      return '--';
    }
    return bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(' ');
  }

  String _formatInstruction(String instruction) {
    final normalized = instruction.trim().replaceAll(RegExp(r'\s+'), ' ');
    return normalized;
  }
}

class _HitDetail extends StatelessWidget {
  const _HitDetail({required this.hit, required this.breakpoint});

  final MemoryBreakpointHit? hit;
  final MemoryBreakpoint? breakpoint;

  @override
  Widget build(BuildContext context) {
    if (hit == null) {
      return _DebugEmptyState(
        message: context.isZh
            ? '选择一条命中记录查看详情'
            : 'Select a hit record to inspect details',
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: 6.r,
            runSpacing: 6.r,
            children: <Widget>[
              _InlineChip(
                text: 'PC 0x${hit!.pc.toRadixString(16).toUpperCase()}',
              ),
              _InlineChip(text: 'TID ${hit!.threadId}'),
              _InlineChip(text: _formatTimestamp(hit!.timestampMillis)),
              if (breakpoint != null)
                _InlineChip(text: '${breakpoint!.length}B'),
            ],
          ),
          SizedBox(height: 10.r),
          _DetailBlock(
            title: context.isZh ? '模块偏移' : 'Module Offset',
            value:
                '${hit!.moduleName.isEmpty ? '[anonymous]' : hit!.moduleName}+0x${hit!.moduleOffset.toRadixString(16).toUpperCase()}',
            monospace: true,
          ),
          SizedBox(height: 8.r),
          _DetailBlock(
            title: context.isZh ? '命中地址' : 'Hit Address',
            value: '0x${hit!.address.toRadixString(16).toUpperCase()}',
            monospace: true,
          ),
          SizedBox(height: 8.r),
          _DetailBlock(
            title: context.isZh ? '旧值' : 'Old Value',
            value: _formatBytesForDetail(hit!.oldValue),
            monospace: true,
          ),
          SizedBox(height: 8.r),
          _DetailBlock(
            title: context.isZh ? '新值' : 'New Value',
            value: _formatBytesForDetail(hit!.newValue),
            active: true,
            monospace: true,
          ),
          if (hit!.instructionText.isNotEmpty) ...<Widget>[
            SizedBox(height: 8.r),
            _DetailBlock(
              title: context.isZh ? '指令' : 'Instruction',
              value: hit!.instructionText.trim(),
              monospace: true,
            ),
          ],
          if (breakpoint != null) ...<Widget>[
            SizedBox(height: 8.r),
            _DetailBlock(
              title: context.isZh ? '断点地址' : 'Breakpoint Address',
              value: '0x${breakpoint!.address.toRadixString(16).toUpperCase()}',
              monospace: true,
            ),
            SizedBox(height: 8.r),
            _DetailBlock(
              title: context.isZh ? '监控模式' : 'Watch Mode',
              value:
                  '${_mapAccessType(context, breakpoint!.accessType)} · ${breakpoint!.pauseProcessOnHit ? (context.isZh ? '命中即暂停' : 'Pause On Hit') : (context.isZh ? '仅记录' : 'Record Only')}',
            ),
          ],
        ],
      ),
    );
  }

  String _hex(Uint8List bytes) {
    if (bytes.isEmpty) {
      return '--';
    }
    return bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(' ');
  }

  String _formatBytesForDetail(Uint8List bytes) {
    if (bytes.isEmpty) {
      return '--';
    }
    final values = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0').toUpperCase())
        .toList(growable: false);
    final lines = <String>[];
    for (int index = 0; index < values.length; index += 8) {
      final end = (index + 8 < values.length) ? index + 8 : values.length;
      lines.add(values.sublist(index, end).join(' '));
    }
    return lines.join('\n');
  }

  String _mapAccessType(BuildContext context, MemoryBreakpointAccessType type) {
    return switch (type) {
      MemoryBreakpointAccessType.read => context.isZh ? '读' : 'Read',
      MemoryBreakpointAccessType.write => context.isZh ? '写' : 'Write',
      MemoryBreakpointAccessType.readWrite => context.isZh ? '读写' : 'Read/Write',
    };
  }
}

class _PanelDivider extends StatelessWidget {
  const _PanelDivider({required this.vertical});

  final bool vertical;

  @override
  Widget build(BuildContext context) {
    if (vertical) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 10.r),
        child: VerticalDivider(
          width: 1,
          thickness: 1,
          color: context.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 10.r),
      child: Divider(
        height: 1,
        thickness: 1,
        color: context.colorScheme.outlineVariant.withValues(alpha: 0.4),
      ),
    );
  }
}

class _DebugStatsBar extends StatelessWidget {
  const _DebugStatsBar({
    required this.state,
    required this.selectedBreakpoint,
    required this.hitCount,
    required this.breakpointCount,
  });

  final MemoryBreakpointState? state;
  final MemoryBreakpoint? selectedBreakpoint;
  final int hitCount;
  final int breakpointCount;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            MemoryToolResultStatChip(
              label: context.isZh ? '断点' : 'Breakpoints',
              value: breakpointCount,
            ),
            SizedBox(width: 6.r),
            MemoryToolResultStatChip(
              label: context.isZh ? '活动' : 'Active',
              value: state?.activeBreakpointCount ?? 0,
            ),
            SizedBox(width: 6.r),
            MemoryToolResultStatChip(
              label: context.isZh ? '当前命中' : 'Hits',
              value: hitCount,
            ),
            SizedBox(width: 6.r),
            MemoryToolResultStatChip(
              label: context.isZh ? '待处理' : 'Pending',
              value: state?.pendingHitCount ?? 0,
            ),
            if (selectedBreakpoint != null) ...<Widget>[
              SizedBox(width: 6.r),
              MemoryToolResultStatChip(
                label: context.isZh ? '长度' : 'Length',
                value: selectedBreakpoint!.length,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ListItemShell extends StatelessWidget {
  const _ListItemShell({
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12.r),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: selected
                ? context.colorScheme.primary.withValues(alpha: 0.07)
                : context.colorScheme.surface.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(
              color: selected
                  ? context.colorScheme.primary.withValues(alpha: 0.42)
                  : context.colorScheme.outlineVariant.withValues(alpha: 0.32),
            ),
          ),
          child: Padding(
            padding: EdgeInsets.all(10.r),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _InlineChip extends StatelessWidget {
  const _InlineChip({required this.text, this.active = false});

  final String text;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: active
            ? context.colorScheme.primary.withValues(alpha: 0.08)
            : context.colorScheme.surfaceContainerHighest.withValues(alpha: 0.46),
        borderRadius: BorderRadius.circular(999.r),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 8.r, vertical: 4.r),
        child: Text(
          text,
          style: context.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: active ? context.colorScheme.primary : null,
          ),
        ),
      ),
    );
  }
}

class _DetailBlock extends StatelessWidget {
  const _DetailBlock({
    required this.title,
    required this.value,
    this.active = false,
    this.monospace = false,
  });

  final String title;
  final String value;
  final bool active;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: active
            ? context.colorScheme.primary.withValues(alpha: 0.08)
            : context.colorScheme.surfaceContainerHighest.withValues(alpha: 0.46),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: active
              ? context.colorScheme.primary.withValues(alpha: 0.18)
              : Colors.transparent,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(10.r),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: context.textTheme.labelMedium?.copyWith(
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
            SizedBox(height: 4.r),
            Text(
              value,
              style: context.textTheme.bodyMedium?.copyWith(
                fontFamily: monospace ? 'monospace' : null,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DebugEmptyState extends StatelessWidget {
  const _DebugEmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.r),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: context.textTheme.bodyMedium?.copyWith(
            color: context.colorScheme.onSurface.withValues(alpha: 0.66),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _DebugProcessEmptyState extends StatelessWidget {
  const _DebugProcessEmptyState();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colorScheme.surface.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(
          color: context.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(18.r),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.bug_report_rounded,
                size: 28.r,
                color: context.colorScheme.primary,
              ),
              SizedBox(height: 10.r),
              Text(
                context.isZh ? '请先选择进程' : 'Select a process first',
                style: context.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 6.r),
              Text(
                context.isZh
                    ? '长按搜索结果、预览结果或暂存结果创建断点后，这里会显示命中记录和写入指令。'
                    : 'Create a watchpoint from a long-press result to inspect hit records here.',
                textAlign: TextAlign.center,
                style: context.textTheme.bodySmall?.copyWith(
                  color: context.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

MemoryBreakpoint? _resolveSelectedBreakpoint({
  required List<MemoryBreakpoint> breakpoints,
  required String? selectedBreakpointId,
}) {
  for (final breakpoint in breakpoints) {
    if (breakpoint.id == selectedBreakpointId) {
      return breakpoint;
    }
  }
  if (breakpoints.isEmpty) {
    return null;
  }
  return breakpoints.first;
}

MemoryBreakpointHit? _resolveSelectedHit({
  required List<MemoryBreakpointHit> hits,
  required String? selectedHitKey,
}) {
  for (final hit in hits) {
    if (_buildHitKey(hit) == selectedHitKey) {
      return hit;
    }
  }
  if (hits.isEmpty) {
    return null;
  }
  return hits.first;
}

String _buildHitKey(MemoryBreakpointHit hit) {
  return '${hit.breakpointId}_${hit.timestampMillis}_${hit.threadId}_${hit.pc}';
}

String _formatTimestamp(int millis) {
  final time = DateTime.fromMillisecondsSinceEpoch(millis);
  final year = time.year.toString().padLeft(4, '0');
  final month = time.month.toString().padLeft(2, '0');
  final day = time.day.toString().padLeft(2, '0');
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  final second = time.second.toString().padLeft(2, '0');
  return '$year-$month-$day $hour:$minute:$second';
}
