import 'package:JsxposedX/features/memory_tool_overlay/presentation/models/memory_tool_saved_item.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/providers/memory_query_provider.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/utils/memory_tool_search_result_presenter.dart';
import 'package:JsxposedX/features/overlay_window/presentation/providers/overlay_window_host_runtime_provider.dart';
import 'package:JsxposedX/generated/memory_tool.g.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'memory_tool_saved_items_provider.g.dart';

class MemoryToolSavedItemsState {
  const MemoryToolSavedItemsState({
    this.itemsByPid = const <int, Map<int, MemoryToolSavedItem>>{},
  });

  final Map<int, Map<int, MemoryToolSavedItem>> itemsByPid;

  MemoryToolSavedItemsState copyWith({
    Map<int, Map<int, MemoryToolSavedItem>>? itemsByPid,
  }) {
    return MemoryToolSavedItemsState(
      itemsByPid: itemsByPid ?? this.itemsByPid,
    );
  }
}

class MemoryToolSavedItemSelectionState {
  const MemoryToolSavedItemSelectionState({
    this.selectedAddresses = const <int>[],
  });

  final List<int> selectedAddresses;

  int get selectedCount => selectedAddresses.length;

  bool contains(int address) {
    return selectedAddresses.contains(address);
  }

  MemoryToolSavedItemSelectionState copyWith({
    List<int>? selectedAddresses,
  }) {
    return MemoryToolSavedItemSelectionState(
      selectedAddresses: selectedAddresses ?? this.selectedAddresses,
    );
  }
}

@riverpod
List<MemoryToolSavedItem> savedItemsForSelectedProcess(Ref ref) {
  final selectedProcess = ref.watch(memoryToolSelectedProcessProvider);
  if (selectedProcess == null) {
    return const <MemoryToolSavedItem>[];
  }

  final itemsByAddress =
      ref.watch(memoryToolSavedItemsProvider).itemsByPid[selectedProcess.pid];
  if (itemsByAddress == null || itemsByAddress.isEmpty) {
    return const <MemoryToolSavedItem>[];
  }

  final sortedItems = itemsByAddress.values.toList(growable: false)
    ..sort((left, right) => left.address.compareTo(right.address));
  return sortedItems;
}

@riverpod
Future<Map<int, MemoryValuePreview>> currentSavedItemLivePreviews(Ref ref) async {
  final savedItems = ref.watch(savedItemsForSelectedProcessProvider);
  final isPanelVisible = ref.watch(
    overlayWindowHostRuntimeProvider.select(
      (state) => state.payload.isPanel && !state.isTransitioningToPanel,
    ),
  );
  if (!isPanelVisible || savedItems.isEmpty) {
    return const <int, MemoryValuePreview>{};
  }

  final previews = await ref
      .watch(memoryQueryRepositoryProvider)
      .readMemoryValues(
        requests: savedItems
            .map(
              (item) => MemoryReadRequest(
                address: item.address,
                type: item.type,
                length: resolveMemoryToolReadLengthForType(
                  type: item.type,
                  bytesLength: item.rawBytes.length,
                ),
              ),
            )
            .toList(growable: false),
      );

  return <int, MemoryValuePreview>{
    for (final preview in previews) preview.address: preview,
  };
}

@Riverpod(keepAlive: true)
class MemoryToolSavedItems extends _$MemoryToolSavedItems {
  @override
  MemoryToolSavedItemsState build() {
    return const MemoryToolSavedItemsState();
  }

  void saveOne({
    required int pid,
    required SearchResult result,
    MemoryValuePreview? preview,
    required bool isFrozen,
  }) {
    final nextItemsByPid = _copyItemsByPid();
    final nextItemsByAddress = <int, MemoryToolSavedItem>{
      ...(nextItemsByPid[pid] ?? const <int, MemoryToolSavedItem>{}),
      result.address: MemoryToolSavedItem.fromSearchResult(
        pid: pid,
        result: result,
        preview: preview,
        isFrozen: isFrozen,
      ),
    };
    nextItemsByPid[pid] = nextItemsByAddress;
    state = state.copyWith(itemsByPid: nextItemsByPid);
  }

  void saveMany({
    required int pid,
    required List<SearchResult> results,
    Map<int, MemoryValuePreview> previewsByAddress =
        const <int, MemoryValuePreview>{},
    Set<int> frozenAddresses = const <int>{},
  }) {
    if (results.isEmpty) {
      return;
    }

    final nextItemsByPid = _copyItemsByPid();
    final nextItemsByAddress = <int, MemoryToolSavedItem>{
      ...(nextItemsByPid[pid] ?? const <int, MemoryToolSavedItem>{}),
    };

    for (final result in results) {
      nextItemsByAddress[result.address] = MemoryToolSavedItem.fromSearchResult(
        pid: pid,
        result: result,
        preview: previewsByAddress[result.address],
        isFrozen: frozenAddresses.contains(result.address),
      );
    }

    nextItemsByPid[pid] = nextItemsByAddress;
    state = state.copyWith(itemsByPid: nextItemsByPid);
  }

  void removeOne({required int pid, required int address}) {
    final currentItemsByAddress = state.itemsByPid[pid];
    if (currentItemsByAddress == null || !currentItemsByAddress.containsKey(address)) {
      return;
    }

    final nextItemsByPid = _copyItemsByPid();
    final nextItemsByAddress = <int, MemoryToolSavedItem>{
      ...currentItemsByAddress,
    }..remove(address);
    if (nextItemsByAddress.isEmpty) {
      nextItemsByPid.remove(pid);
    } else {
      nextItemsByPid[pid] = nextItemsByAddress;
    }
    state = state.copyWith(itemsByPid: nextItemsByPid);
  }

  void removeSelected({
    required int pid,
    required Iterable<int> addresses,
  }) {
    final currentItemsByAddress = state.itemsByPid[pid];
    if (currentItemsByAddress == null || currentItemsByAddress.isEmpty) {
      return;
    }

    final nextItemsByAddress = <int, MemoryToolSavedItem>{
      ...currentItemsByAddress,
    };
    var changed = false;
    for (final address in addresses) {
      changed = nextItemsByAddress.remove(address) != null || changed;
    }
    if (!changed) {
      return;
    }

    final nextItemsByPid = _copyItemsByPid();
    if (nextItemsByAddress.isEmpty) {
      nextItemsByPid.remove(pid);
    } else {
      nextItemsByPid[pid] = nextItemsByAddress;
    }
    state = state.copyWith(itemsByPid: nextItemsByPid);
  }

  void clearProcess(int pid) {
    if (!state.itemsByPid.containsKey(pid)) {
      return;
    }

    final nextItemsByPid = _copyItemsByPid()..remove(pid);
    state = state.copyWith(itemsByPid: nextItemsByPid);
  }

  Map<int, Map<int, MemoryToolSavedItem>> _copyItemsByPid() {
    return <int, Map<int, MemoryToolSavedItem>>{
      for (final entry in state.itemsByPid.entries)
        entry.key: <int, MemoryToolSavedItem>{...entry.value},
    };
  }
}

@Riverpod(keepAlive: true)
class MemoryToolSavedItemSelection extends _$MemoryToolSavedItemSelection {
  @override
  MemoryToolSavedItemSelectionState build() {
    return const MemoryToolSavedItemSelectionState();
  }

  void toggle(int address) {
    final selected = List<int>.from(state.selectedAddresses);
    final existingIndex = selected.indexOf(address);
    if (existingIndex >= 0) {
      selected.removeAt(existingIndex);
    } else {
      selected.add(address);
    }
    state = state.copyWith(selectedAddresses: selected);
  }

  void selectVisible(Iterable<int> addresses) {
    state = state.copyWith(
      selectedAddresses: addresses.toList(growable: false),
    );
  }

  void invertVisible(Iterable<int> addresses) {
    final visibleAddresses = addresses.toSet();
    final selected = state.selectedAddresses.toSet();
    final nextSelected = <int>[
      for (final address in state.selectedAddresses)
        if (!visibleAddresses.contains(address)) address,
      for (final address in visibleAddresses)
        if (!selected.contains(address)) address,
    ];
    state = state.copyWith(selectedAddresses: nextSelected);
  }

  void retainVisible(Iterable<int> addresses) {
    final visibleAddresses = addresses.toSet();
    final nextSelected = state.selectedAddresses
        .where(visibleAddresses.contains)
        .toList(growable: false);
    if (nextSelected.length == state.selectedAddresses.length) {
      return;
    }
    state = state.copyWith(selectedAddresses: nextSelected);
  }

  void removeAddress(int address) {
    if (!state.selectedAddresses.contains(address)) {
      return;
    }

    state = state.copyWith(
      selectedAddresses: state.selectedAddresses
          .where((selectedAddress) => selectedAddress != address)
          .toList(growable: false),
    );
  }

  void clearSelection() {
    if (state.selectedAddresses.isEmpty) {
      return;
    }
    state = const MemoryToolSavedItemSelectionState();
  }
}
