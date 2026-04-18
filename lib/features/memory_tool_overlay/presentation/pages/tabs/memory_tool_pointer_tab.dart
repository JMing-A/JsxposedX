import 'dart:async';

import 'package:JsxposedX/common/pages/toast.dart';
import 'package:JsxposedX/common/widgets/overlay_window/overlay_text_input_context_menu.dart';
import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/providers/memory_pointer_action_provider.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/providers/memory_pointer_query_provider.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/providers/memory_query_provider.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/providers/memory_tool_browse_provider.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/providers/memory_tool_pointer_provider.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/states/memory_tool_pointer_state.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/utils/memory_tool_pointer_utils.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/utils/memory_tool_search_result_presenter.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/widgets/memory_tool_pointer_result_list.dart';
import 'package:JsxposedX/generated/memory_tool.g.dart'
    show PointerScanResult, PointerScanSessionState, SearchTaskStatus;
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class MemoryToolPointerTab extends HookConsumerWidget {
  const MemoryToolPointerTab({
    super.key,
    required this.onOpenBrowseTab,
  });

  final VoidCallback onOpenBrowseTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    useAutomaticKeepAlive();
    final selectedProcess = ref.watch(memoryToolSelectedProcessProvider);
    final pointerState = ref.watch(memoryToolPointerControllerProvider);
    final pointerController = ref.read(memoryToolPointerControllerProvider.notifier);
    final taskStateAsync = ref.watch(getPointerScanTaskStateProvider);
    final sessionStateAsync = ref.watch(getPointerScanSessionStateProvider);
    final currentLayer = pointerState.currentLayer;
    final scrollController = useScrollController();
    final previousTaskStatus = useRef<SearchTaskStatus?>(null);
    final filterController = useTextEditingController();
    final filterQuery = useState('');
    final selectedRegionTypeKeys = useState<Set<String>>(<String>{});

    useEffect(() {
      void handleScroll() {
        if (!scrollController.hasClients) {
          return;
        }
        if (scrollController.position.extentAfter <= 320.r) {
          pointerController.loadMore();
        }
      }

      scrollController.addListener(handleScroll);
      return () {
        scrollController.removeListener(handleScroll);
      };
    }, [scrollController, pointerController]);

    final isRunningTask = taskStateAsync.maybeWhen(
      data: (state) => state.status == SearchTaskStatus.running,
      orElse: () => false,
    );

    useEffect(() {
      if (!isRunningTask) {
        return null;
      }

      final timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        ref.invalidate(getPointerScanTaskStateProvider);
      });
      return timer.cancel;
    }, [isRunningTask, ref]);

    useEffect(() {
      taskStateAsync.whenData((taskState) {
        final previousStatus = previousTaskStatus.value;
        if (previousStatus == SearchTaskStatus.running &&
            taskState.status != SearchTaskStatus.running) {
          ref.invalidate(getPointerScanSessionStateProvider);
          ref.invalidate(getPointerScanResultsProvider);
          if (taskState.status == SearchTaskStatus.completed) {
            pointerController.refreshLayerForActiveSession();
          } else if (taskState.status == SearchTaskStatus.failed ||
              taskState.status == SearchTaskStatus.cancelled) {
            pointerController.markActiveScanLayerError(taskState.message);
          }
        }
        previousTaskStatus.value = taskState.status;
      });
      return null;
    }, [taskStateAsync, pointerController, ref]);

    final availableRegionTypeKeys = <String>[
      if (currentLayer != null)
        ...{
          for (final result in currentLayer.results) result.regionTypeKey,
        },
    ];
    final availableRegionTypeSignature = availableRegionTypeKeys.join(',');
    final selectedRegionTypeSignature = selectedRegionTypeKeys.value.toList()
      ..sort();

    useEffect(() {
      final nextSelected = selectedRegionTypeKeys.value
          .where(availableRegionTypeKeys.contains)
          .toSet();
      if (nextSelected.length != selectedRegionTypeKeys.value.length) {
        selectedRegionTypeKeys.value = nextSelected;
      }
      return null;
    }, [availableRegionTypeSignature]);

    Future<void> previewAndOpenBrowse(
      Future<void> Function() previewAction,
    ) async {
      try {
        await previewAction();
        onOpenBrowseTab();
      } catch (_) {
        if (!context.mounted) {
          return;
        }
        await ToastOverlayMessage.show(
          context.l10n.memoryToolOffsetPreviewUnreadable,
          duration: const Duration(milliseconds: 1200),
        );
      }
    }

    Future<void> jumpToTarget(PointerScanResult result) async {
      final layer = pointerState.currentLayer;
      if (layer == null) {
        return;
      }

      await previewAndOpenBrowse(
        () => ref
            .read(memoryToolBrowseControllerProvider.notifier)
            .previewFromAddress(
              sourceResult: buildSearchResultFromPointerResult(
                result: result,
                pointerWidth: layer.request.pointerWidth,
              ),
              targetAddress: result.targetAddress,
            ),
      );
    }

    bool matchesPointerResult(PointerScanResult result) {
      if (selectedRegionTypeKeys.value.isNotEmpty &&
          !selectedRegionTypeKeys.value.contains(result.regionTypeKey)) {
        return false;
      }

      final normalizedQuery = filterQuery.value.trim().toUpperCase();
      if (normalizedQuery.isEmpty) {
        return true;
      }

      final pointerAddress =
          formatMemoryToolSearchResultAddress(result.pointerAddress).toUpperCase();
      final baseAddress =
          formatMemoryToolSearchResultAddress(result.baseAddress).toUpperCase();
      final targetAddress =
          formatMemoryToolSearchResultAddress(result.targetAddress).toUpperCase();
      final offsetHex = '0X${result.offset.toRadixString(16).toUpperCase()}';
      final offsetDec = result.offset.toString();
      final regionLabel = mapMemoryToolSearchResultRegionTypeLabel(
        context,
        result.regionTypeKey,
      ).toUpperCase();
      return pointerAddress.contains(normalizedQuery) ||
          baseAddress.contains(normalizedQuery) ||
          targetAddress.contains(normalizedQuery) ||
          offsetHex.contains(normalizedQuery) ||
          offsetDec.contains(normalizedQuery) ||
          regionLabel.contains(normalizedQuery);
    }

    final filteredResults = currentLayer == null
        ? const <PointerScanResult>[]
        : currentLayer.results
              .where(matchesPointerResult)
              .toList(growable: false);

    useEffect(() {
      if (currentLayer == null ||
          currentLayer.isLoadingInitial ||
          currentLayer.isLoadingMore ||
          !currentLayer.hasMore ||
          filteredResults.length >= 12 ||
          (filterQuery.value.trim().isEmpty &&
              selectedRegionTypeKeys.value.isEmpty)) {
        return null;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        pointerController.loadMore();
      });
      return null;
    }, [
      currentLayer?.results.length,
      currentLayer?.hasMore,
      currentLayer?.isLoadingInitial,
      currentLayer?.isLoadingMore,
      filteredResults.length,
      filterQuery.value,
      selectedRegionTypeSignature.join(','),
    ]);

    if (selectedProcess == null) {
      return Center(
        child: Text(
          context.l10n.selectApp,
          style: context.textTheme.bodyMedium?.copyWith(
            color: context.colorScheme.onSurface.withValues(alpha: 0.66),
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return Stack(
      children: <Widget>[
        Padding(
          padding: EdgeInsets.all(12.r),
          child: Column(
            children: <Widget>[
              _PointerBreadcrumbRow(
                state: pointerState,
                onTapLayer: pointerController.selectLayer,
              ),
              if (currentLayer != null) ...<Widget>[
                SizedBox(height: 10.r),
                _PointerFilterPanel(
                  filterController: filterController,
                  filterQuery: filterQuery.value,
                  onFilterChanged: (value) {
                    filterQuery.value = value;
                  },
                  onClearFilter: () {
                    filterController.clear();
                    filterQuery.value = '';
                  },
                  selectedRegionTypeKeys: selectedRegionTypeKeys.value,
                  availableRegionTypeKeys: availableRegionTypeKeys,
                  onToggleRegionTypeKey: (regionTypeKey) {
                    final nextSelected = Set<String>.from(
                      selectedRegionTypeKeys.value,
                    );
                    if (nextSelected.contains(regionTypeKey)) {
                      nextSelected.remove(regionTypeKey);
                    } else {
                      nextSelected.add(regionTypeKey);
                    }
                    selectedRegionTypeKeys.value = nextSelected;
                  },
                  onClearRegionFilters: () {
                    selectedRegionTypeKeys.value = <String>{};
                  },
                ),
              ],
              SizedBox(height: 10.r),
              Expanded(
                child: currentLayer == null
                    ? const SizedBox.shrink()
                    : currentLayer.results.isEmpty && currentLayer.errorText != null
                    ? Center(
                        child: Text(
                          currentLayer.errorText!,
                          textAlign: TextAlign.center,
                          style: context.textTheme.bodyMedium?.copyWith(
                            color: context.colorScheme.error,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    : currentLayer.results.isEmpty && !isRunningTask
                    ? const SizedBox.shrink()
                    : filteredResults.isEmpty && !isRunningTask
                    ? const SizedBox.shrink()
                    : MemoryToolPointerResultList(
                        results: filteredResults,
                        request: currentLayer.request,
                        scrollController: scrollController,
                        onContinueSearch: (result) async {
                          await pointerController.continueScan(
                            result: result,
                            baseRequest: currentLayer.request,
                          );
                        },
                        onJumpToTarget: jumpToTarget,
                      ),
              ),
              SizedBox(height: 8.r),
              _PointerFooter(
                currentLayer: currentLayer,
                sessionStateAsync: sessionStateAsync,
              ),
            ],
          ),
        ),
        if (taskStateAsync case AsyncData(value: final taskState) when taskState.status == SearchTaskStatus.running)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black.withValues(alpha: 0.22),
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: context.colorScheme.surface.withValues(alpha: 0.96),
                    borderRadius: BorderRadius.circular(18.r),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(16.r),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          context.l10n.memoryToolPointerTaskRunningTitle,
                          style: context.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 10.r),
                        SizedBox(
                          width: 28.r,
                          height: 28.r,
                          child: CircularProgressIndicator(strokeWidth: 2.4.r),
                        ),
                        SizedBox(height: 12.r),
                        Text(
                          '${context.l10n.memoryToolTaskRegionsLabel}: ${taskState.processedRegions}/${taskState.totalRegions}',
                          style: context.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 4.r),
                        Text(
                          '${context.l10n.memoryToolTaskResultCountLabel}: ${taskState.resultCount}',
                          style: context.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 12.r),
                        Align(
                          alignment: Alignment.centerRight,
                          child: OutlinedButton(
                            onPressed: () {
                              ref
                                  .read(memoryPointerActionProvider.notifier)
                                  .cancelPointerScan();
                            },
                            child: Text(context.l10n.memoryToolTaskCancelAction),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _PointerBreadcrumbRow extends StatelessWidget {
  const _PointerBreadcrumbRow({
    required this.state,
    required this.onTapLayer,
  });

  final MemoryToolPointerState state;
  final ValueChanged<int> onTapLayer;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List<Widget>.generate(state.layers.length, (index) {
          final layer = state.layers[index];
          final selected = index == state.currentLayerIndex;
          return Padding(
            padding: EdgeInsets.only(right: 8.r),
            child: ChoiceChip(
              label: Text(
                'L$index ${formatMemoryToolSearchResultAddress(layer.request.targetAddress)}',
              ),
              selected: selected,
              onSelected: (_) {
                onTapLayer(index);
              },
            ),
          );
        }),
      ),
    );
  }
}

class _PointerFooter extends StatelessWidget {
  const _PointerFooter({
    required this.currentLayer,
    required this.sessionStateAsync,
  });

  final PointerChainLayerState? currentLayer;
  final AsyncValue<PointerScanSessionState> sessionStateAsync;

  @override
  Widget build(BuildContext context) {
    final loadedCount = currentLayer?.results.length ?? 0;
    final sessionCount = sessionStateAsync.asData?.value.resultCount ?? 0;
    final totalCount = currentLayer?.totalResultCount ?? 0;
    final resolvedTotalCount = totalCount > 0 ? totalCount : sessionCount;

    if (currentLayer == null || (loadedCount <= 0 && resolvedTotalCount <= 0)) {
      return const SizedBox.shrink();
    }

    return Align(
      alignment: Alignment.centerRight,
      child: Text(
        context.l10n.memoryToolPointerLoadedCount(
          loadedCount,
          resolvedTotalCount,
        ),
        style: context.textTheme.bodySmall?.copyWith(
          color: context.colorScheme.onSurface.withValues(alpha: 0.68),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PointerFilterPanel extends StatelessWidget {
  const _PointerFilterPanel({
    required this.filterController,
    required this.filterQuery,
    required this.onFilterChanged,
    required this.onClearFilter,
    required this.selectedRegionTypeKeys,
    required this.availableRegionTypeKeys,
    required this.onToggleRegionTypeKey,
    required this.onClearRegionFilters,
  });

  final TextEditingController filterController;
  final String filterQuery;
  final ValueChanged<String> onFilterChanged;
  final VoidCallback onClearFilter;
  final Set<String> selectedRegionTypeKeys;
  final List<String> availableRegionTypeKeys;
  final ValueChanged<String> onToggleRegionTypeKey;
  final VoidCallback onClearRegionFilters;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colorScheme.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(
          color: context.colorScheme.outlineVariant.withValues(alpha: 0.38),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(10.r),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: filterController,
              onChanged: onFilterChanged,
              enableInteractiveSelection: true,
              contextMenuBuilder: buildOverlayTextInputContextMenu,
              decoration: InputDecoration(
                isDense: true,
                hintText: context.l10n.search,
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: filterQuery.isEmpty
                    ? null
                    : IconButton(
                        onPressed: onClearFilter,
                        icon: const Icon(Icons.close_rounded),
                      ),
                filled: true,
                fillColor: context.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.36),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.r),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            if (availableRegionTypeKeys.isNotEmpty) ...<Widget>[
              SizedBox(height: 10.r),
              Wrap(
                spacing: 8.r,
                runSpacing: 8.r,
                children: <Widget>[
                  ChoiceChip(
                    label: Text(context.l10n.memoryToolRangePresetAll),
                    selected: selectedRegionTypeKeys.isEmpty,
                    onSelected: (_) {
                      onClearRegionFilters();
                    },
                  ),
                  ...availableRegionTypeKeys.map((regionTypeKey) {
                    return FilterChip(
                      label: Text(
                        mapMemoryToolSearchResultRegionTypeLabel(
                          context,
                          regionTypeKey,
                        ),
                      ),
                      selected: selectedRegionTypeKeys.contains(regionTypeKey),
                      onSelected: (_) {
                        onToggleRegionTypeKey(regionTypeKey);
                      },
                    );
                  }),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
