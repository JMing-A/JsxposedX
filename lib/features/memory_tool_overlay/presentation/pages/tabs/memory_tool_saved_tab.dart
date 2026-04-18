import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/models/memory_tool_saved_item.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/providers/memory_action_provider.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/providers/memory_tool_saved_items_provider.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/providers/memory_query_provider.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/widgets/memory_tool_batch_edit_dialog.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/widgets/memory_tool_result_calculator_dialog.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/widgets/memory_tool_result_selection_bar.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/widgets/memory_tool_result_stats_bar.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/widgets/memory_tool_search_result_dialog.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/widgets/memory_tool_search_result_tile.dart';
import 'package:JsxposedX/generated/memory_tool.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class MemoryToolSavedTab extends HookConsumerWidget {
  const MemoryToolSavedTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    useAutomaticKeepAlive();
    final selectedProcess = ref.watch(memoryToolSelectedProcessProvider);
    final savedItems = ref.watch(savedItemsForSelectedProcessProvider);
    final selectionState = ref.watch(memoryToolSavedItemSelectionProvider);
    final selectionNotifier = ref.read(
      memoryToolSavedItemSelectionProvider.notifier,
    );
    final savedItemsNotifier = ref.read(memoryToolSavedItemsProvider.notifier);
    final livePreviewsAsync = ref.watch(currentSavedItemLivePreviewsProvider);
    final frozenValuesAsync = ref.watch(currentFrozenMemoryValuesProvider);
    final valueHistoryState = ref.watch(memoryValueHistoryProvider);
    final valueActionState = ref.watch(memoryValueActionProvider);
    final isBatchEditVisible = useState(false);
    final isCalculatorVisible = useState(false);
    final activeDialog =
        useState<({MemoryToolSavedItem item, String displayValue})?>(null);

    useEffect(() {
      selectionNotifier.retainVisible(
        savedItems.map((item) => item.address).toList(growable: false),
      );
      return null;
    }, [selectedProcess?.pid, savedItems]);

    final previewMap =
        livePreviewsAsync.asData?.value ?? const <int, MemoryValuePreview>{};
    final currentFrozenAddresses = selectedProcess == null
        ? null
        : frozenValuesAsync.asData?.value
              ?.where((value) => value.pid == selectedProcess.pid)
              .map((value) => value.address)
              .toSet();
    final selectedItems = savedItems
        .where((item) => selectionState.contains(item.address))
        .toList(growable: false);
    final previousValueByAddress = <int, String>{
      for (final entry in valueHistoryState.entries)
        entry.key: entry.value.displayValue,
    };
    final canRestorePrevious = selectionState.selectedAddresses.any(
      valueHistoryState.containsKey,
    );

    Future<void> restoreAddresses(List<int> addresses) async {
      try {
        final sessionState = await ref.read(getSearchSessionStateProvider.future);
        await ref
            .read(memoryValueActionProvider.notifier)
            .restorePreviousValues(
              addresses: addresses,
              littleEndian: sessionState.littleEndian,
            );
      } catch (error) {
        if (!context.mounted) {
          return;
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }

    Future<void> syncSavedItems({
      required List<SearchResult> results,
      required Map<int, MemoryValuePreview> previewsByAddress,
      required bool isFrozen,
    }) async {
      if (selectedProcess == null || results.isEmpty) {
        return;
      }

      savedItemsNotifier.saveMany(
        pid: selectedProcess.pid,
        results: results,
        previewsByAddress: previewsByAddress,
        frozenAddresses: isFrozen
            ? results.map((result) => result.address).toSet()
            : const <int>{},
      );
    }

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
              MemoryToolResultSelectionBar(
                actions: <MemoryToolResultSelectionActionData>[
                  MemoryToolResultSelectionActionData(
                    icon: Icons.done_all_rounded,
                    onTap: savedItems.isEmpty
                        ? null
                        : () {
                            selectionNotifier.selectVisible(
                              savedItems.map((item) => item.address),
                            );
                          },
                  ),
                  MemoryToolResultSelectionActionData(
                    icon: Icons.flip_rounded,
                    onTap: savedItems.isEmpty
                        ? null
                        : () {
                            selectionNotifier.invertVisible(
                              savedItems.map((item) => item.address),
                            );
                          },
                  ),
                  MemoryToolResultSelectionActionData(
                    icon: Icons.layers_clear_rounded,
                    onTap: savedItems.isEmpty
                        ? null
                        : selectionNotifier.clearSelection,
                  ),
                  MemoryToolResultSelectionActionData(
                    icon: Icons.edit_rounded,
                    onTap: selectedItems.isEmpty
                        ? null
                        : () {
                            isBatchEditVisible.value = true;
                          },
                  ),
                  MemoryToolResultSelectionActionData(
                    icon: Icons.calculate_outlined,
                    onTap: selectedItems.length >= 2
                        ? () {
                            isCalculatorVisible.value = true;
                          }
                        : null,
                  ),
                  MemoryToolResultSelectionActionData(
                    icon: Icons.undo_rounded,
                    onTap: canRestorePrevious && !valueActionState.isLoading
                        ? () async {
                            await restoreAddresses(
                              selectionState.selectedAddresses,
                            );
                          }
                        : null,
                  ),
                  MemoryToolResultSelectionActionData(
                    icon: Icons.delete_sweep_rounded,
                    onTap: selectedItems.isEmpty
                        ? null
                        : () {
                            savedItemsNotifier.removeSelected(
                              pid: selectedProcess.pid,
                              addresses: selectionState.selectedAddresses,
                            );
                            selectionNotifier.clearSelection();
                          },
                  ),
                ],
              ),
              SizedBox(height: 8.r),
              Expanded(
                child: savedItems.isEmpty
                    ? Center(
                        child: Text(
                          context.l10n.memoryToolSavedEmpty,
                          style: context.textTheme.bodyMedium?.copyWith(
                            color: context.colorScheme.onSurface.withValues(
                              alpha: 0.66,
                            ),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    : ListView.separated(
                        key: PageStorageKey<String>(
                          'memory_tool_saved_results_${selectedProcess.pid}',
                        ),
                        padding: EdgeInsets.zero,
                        itemCount: savedItems.length,
                        separatorBuilder: (_, index) => SizedBox(
                          height: index == savedItems.length - 1 ? 6.r : 4.r,
                        ),
                        itemBuilder: (context, index) {
                          final item = savedItems[index];
                          final preview = previewMap[item.address];
                          final displayValue =
                              preview?.displayValue ?? item.displayValue;
                          final isFrozen =
                              currentFrozenAddresses?.contains(item.address) ??
                              item.isFrozen;
                          return MemoryToolSearchResultTile(
                            result: item.toSearchResult(),
                            displayValue: displayValue,
                            previousDisplayValue:
                                previousValueByAddress[item.address],
                            isFrozen: isFrozen,
                            isSelected: selectionState.contains(item.address),
                            onToggleSelection: () {
                              selectionNotifier.toggle(item.address);
                            },
                            onDeleteRecord: () {
                              selectionNotifier.removeAddress(item.address);
                              savedItemsNotifier.removeOne(
                                pid: selectedProcess.pid,
                                address: item.address,
                              );
                            },
                            onTap: () {
                              activeDialog.value = (
                                item: item,
                                displayValue: displayValue,
                              );
                            },
                          );
                        },
                      ),
              ),
              SizedBox(height: 6.r),
              MemoryToolResultStatsBar(
                resultCount: savedItems.length,
                selectedCount: selectionState.selectedCount,
                renderedCount: savedItems.length,
                pageCount: 0,
              ),
            ],
          ),
        ),
        if (activeDialog.value case final dialog?)
          Positioned.fill(
            child: MemoryToolSearchResultDialog(
              result: dialog.item.toSearchResult(),
              displayValue: dialog.displayValue,
              livePreviewsAsync: livePreviewsAsync,
              processPid: dialog.item.pid,
              initialFrozenState:
                  currentFrozenAddresses?.contains(dialog.item.address) ??
                  dialog.item.isFrozen,
              onSaved: (result, preview, isFrozen) async {
                savedItemsNotifier.saveOne(
                  pid: dialog.item.pid,
                  result: result,
                  preview: preview,
                  isFrozen: isFrozen,
                );
              },
              onClose: () {
                activeDialog.value = null;
              },
            ),
          ),
        if (isBatchEditVisible.value)
          Positioned.fill(
            child: MemoryToolBatchEditDialog(
              results: selectedItems
                  .map((item) => item.toSearchResult())
                  .toList(growable: false),
              livePreviewsAsync: livePreviewsAsync,
              onSaved: (results, updatedPreviews, isFrozen) async {
                await syncSavedItems(
                  results: results,
                  previewsByAddress: updatedPreviews,
                  isFrozen: isFrozen,
                );
              },
              onClose: () {
                isBatchEditVisible.value = false;
              },
            ),
          ),
        if (isCalculatorVisible.value)
          Positioned.fill(
            child: MemoryToolResultCalculatorDialog(
              results: selectedItems
                  .map((item) => item.toSearchResult())
                  .toList(growable: false),
              livePreviewsAsync: livePreviewsAsync,
              onClose: () {
                isCalculatorVisible.value = false;
              },
            ),
          ),
      ],
    );
  }
}
