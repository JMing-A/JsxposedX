import 'dart:typed_data';

import 'package:JsxposedX/features/memory_tool_overlay/presentation/providers/memory_query_provider.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/states/memory_tool_browse_state.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/states/memory_tool_result_selection_state.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/utils/memory_tool_search_result_presenter.dart';
import 'package:JsxposedX/features/overlay_window/presentation/providers/overlay_window_host_runtime_provider.dart';
import 'package:JsxposedX/generated/memory_tool.g.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'memory_tool_browse_provider.g.dart';

const int _memoryToolBrowseInitialExpandCount = 20;
const int _memoryToolBrowseLoadMoreCount = 20;
const int _memoryToolBrowseRegionPageSize = 200;

@riverpod
List<SearchResult> currentBrowseResults(Ref ref) {
  final browseState = ref.watch(memoryToolBrowseControllerProvider);
  return browseState.results
      .where((result) => !browseState.hiddenAddresses.contains(result.address))
      .toList(growable: false);
}

@riverpod
Future<Map<int, MemoryValuePreview>> currentBrowseResultLivePreviews(
  Ref ref,
) async {
  final browseState = ref.watch(memoryToolBrowseControllerProvider);
  final visibleResults = ref.watch(currentBrowseResultsProvider);
  final selectedProcess = ref.watch(memoryToolSelectedProcessProvider);
  final isPanelVisible = ref.watch(
    overlayWindowHostRuntimeProvider.select(
      (state) => state.payload.isPanel && !state.isTransitioningToPanel,
    ),
  );

  if (!isPanelVisible ||
      !browseState.hasAnchor ||
      visibleResults.isEmpty ||
      selectedProcess == null) {
    return const <int, MemoryValuePreview>{};
  }

  final previews = await ref
      .watch(memoryQueryRepositoryProvider)
      .readMemoryValues(
        requests: visibleResults
            .map(
              (result) => MemoryReadRequest(
                pid: selectedProcess.pid,
                address: result.address,
                type: result.type,
                length: result.rawBytes.length,
              ),
            )
            .toList(growable: false),
      );

  return <int, MemoryValuePreview>{
    for (final preview in previews) preview.address: preview,
  };
}

@Riverpod(keepAlive: true)
class MemoryToolBrowseController extends _$MemoryToolBrowseController {
  @override
  MemoryToolBrowseState build() {
    return const MemoryToolBrowseState();
  }

  Future<void> previewFromSearchResult({
    required SearchResult result,
    MemoryValuePreview? preview,
    required String displayValue,
  }) async {
    await previewFromAddress(
      sourceResult: result,
      sourcePreview: preview,
      targetAddress: result.address,
    );
  }

  Future<void> previewFromAddress({
    required SearchResult sourceResult,
    MemoryValuePreview? sourcePreview,
    required int targetAddress,
  }) async {
    final selectedProcess = ref.read(memoryToolSelectedProcessProvider);
    if (selectedProcess == null) {
      return;
    }

    final sourceRawBytes = _resolveAnchorRawBytes(
      preview: sourcePreview,
      result: sourceResult,
    );
    final strideBytes = sourceRawBytes.isEmpty ? 1 : sourceRawBytes.length;
    var readableRegions = state.regions;
    var targetRegion = _resolveRegionForAddress(
      regions: readableRegions,
      address: targetAddress,
      strideBytes: strideBytes,
    );
    if (targetRegion == null) {
      readableRegions = await _loadReadableRegions(pid: selectedProcess.pid);
      targetRegion = _resolveRegionForAddress(
        regions: readableRegions,
        address: targetAddress,
        strideBytes: strideBytes,
      );
    }
    if (targetRegion == null) {
      throw Exception('Target address is unreadable.');
    }

    final targetPreview = await _readTargetPreviewOrNull(
      selectedPid: selectedProcess.pid,
      address: targetAddress,
      bytesLength: strideBytes,
    );
    if (targetPreview == null) {
      throw Exception('Target address is unreadable.');
    }

    final nextAnchorResult = SearchResult(
      address: targetAddress,
      regionStart: targetRegion.startAddress,
      regionTypeKey: _mapBrowseRegionTypeKey(targetRegion),
      type: sourceResult.type,
      rawBytes: targetPreview.rawBytes,
      displayValue: resolveMemoryToolSearchResultValueByType(
        type: sourceResult.type,
        rawBytes: targetPreview.rawBytes,
        fallbackDisplayValue: targetPreview.displayValue,
      ),
    );

    await _previewAnchorResult(
      selectedPid: selectedProcess.pid,
      anchorResult: nextAnchorResult,
      knownReadableRegions: readableRegions,
    );
  }

  Future<void> recenter() async {
    final anchorResult = state.anchorResult;
    final selectedProcess = ref.read(memoryToolSelectedProcessProvider);
    if (anchorResult == null || state.regions.isEmpty || selectedProcess == null) {
      return;
    }

    state = state.copyWith(
      isInitializing: true,
      isLoadingAbove: false,
      isLoadingBelow: false,
      clearErrorText: true,
    );

    try {
      final nextState = await _buildWindowState(
        selectedPid: selectedProcess.pid,
        anchorResult: anchorResult,
        readableRegions: state.regions,
        preservedHiddenAddresses: state.hiddenAddresses,
      );
      state = nextState.copyWith(
        isInitializing: false,
        clearErrorText: true,
        focusRequestId: state.focusRequestId + 1,
      );
    } catch (error) {
      state = state.copyWith(
        isInitializing: false,
        errorText: error.toString(),
      );
    }
  }

  Future<void> loadMoreAbove() async {
    final anchorResult = state.anchorResult;
    final selectedProcess = ref.read(memoryToolSelectedProcessProvider);
    if (anchorResult == null ||
        state.regions.isEmpty ||
        selectedProcess == null ||
        state.isLoadingAbove ||
        state.reachedTopBoundary) {
      return;
    }

    state = state.copyWith(isLoadingAbove: true, clearErrorText: true);

    try {
      final collected = _collectAlignedAddresses(
        anchorAddress: anchorResult.address,
        strideBytes: state.strideBytes,
        startStep: state.topNextStep,
        targetCount: _memoryToolBrowseLoadMoreCount,
        isAbove: true,
        regions: state.regions,
      );
      final loadedResults = await _readBrowseResults(
        selectedPid: selectedProcess.pid,
        anchorResult: anchorResult,
        readableRegions: state.regions,
        addresses: collected.addresses.reversed.toList(growable: false),
      );
      state = state.copyWith(
        results: _mergeBrowseResults(loadedResults, state.results),
        topNextStep: collected.nextStep,
        reachedTopBoundary: collected.reachedBoundary,
        isLoadingAbove: false,
      );
    } catch (error) {
      state = state.copyWith(
        isLoadingAbove: false,
        errorText: error.toString(),
      );
    }
  }

  Future<void> loadMoreBelow() async {
    final anchorResult = state.anchorResult;
    final selectedProcess = ref.read(memoryToolSelectedProcessProvider);
    if (anchorResult == null ||
        state.regions.isEmpty ||
        selectedProcess == null ||
        state.isLoadingBelow ||
        state.reachedBottomBoundary) {
      return;
    }

    state = state.copyWith(isLoadingBelow: true, clearErrorText: true);

    try {
      final collected = _collectAlignedAddresses(
        anchorAddress: anchorResult.address,
        strideBytes: state.strideBytes,
        startStep: state.bottomNextStep,
        targetCount: _memoryToolBrowseLoadMoreCount,
        isAbove: false,
        regions: state.regions,
      );
      final loadedResults = await _readBrowseResults(
        selectedPid: selectedProcess.pid,
        anchorResult: anchorResult,
        readableRegions: state.regions,
        addresses: collected.addresses,
      );
      state = state.copyWith(
        results: _mergeBrowseResults(state.results, loadedResults),
        bottomNextStep: collected.nextStep,
        reachedBottomBoundary: collected.reachedBoundary,
        isLoadingBelow: false,
      );
    } catch (error) {
      state = state.copyWith(
        isLoadingBelow: false,
        errorText: error.toString(),
      );
    }
  }

  void updateSelectionLimit(int limit) {
    final clampedLimit = limit < 1 ? 1 : limit;
    final nextSelectionState = state.selectionState.copyWith(
      selectionLimit: clampedLimit,
      selectedAddresses: state.selectionState.selectedAddresses
          .take(clampedLimit)
          .toList(growable: false),
    );
    state = state.copyWith(selectionState: nextSelectionState);
  }

  void toggle(SearchResult result) {
    final selected = List<int>.from(state.selectionState.selectedAddresses);
    final address = result.address;
    final existingIndex = selected.indexOf(address);
    if (existingIndex >= 0) {
      selected.removeAt(existingIndex);
    } else if (state.selectionState.selectionLimit == 1) {
      selected
        ..clear()
        ..add(address);
    } else if (selected.length < state.selectionState.selectionLimit) {
      selected.add(address);
    }

    state = state.copyWith(
      selectionState: state.selectionState.copyWith(
        selectedAddresses: selected,
      ),
    );
  }

  void selectVisible(List<SearchResult> results) {
    state = state.copyWith(
      selectionState: state.selectionState.copyWith(
        selectedAddresses: results
            .take(state.selectionState.selectionLimit)
            .map((result) => result.address)
            .toList(growable: false),
      ),
    );
  }

  void invertVisible(List<SearchResult> results) {
    final visibleAddresses = results.map((result) => result.address).toSet();
    final preserved = state.selectionState.selectedAddresses
        .where((address) => !visibleAddresses.contains(address))
        .toList(growable: false);
    final selectedVisible = state.selectionState.selectedAddresses.toSet();
    final nextSelected = <int>[...preserved];
    for (final result in results) {
      if (selectedVisible.contains(result.address) ||
          nextSelected.length >= state.selectionState.selectionLimit) {
        continue;
      }
      nextSelected.add(result.address);
    }

    state = state.copyWith(
      selectionState: state.selectionState.copyWith(
        selectedAddresses: nextSelected
            .take(state.selectionState.selectionLimit)
            .toList(growable: false),
      ),
    );
  }

  void clearSelection() {
    if (state.selectionState.selectedAddresses.isEmpty) {
      return;
    }

    state = state.copyWith(
      selectionState: state.selectionState.copyWith(
        selectedAddresses: const <int>[],
      ),
    );
  }

  void hideAddress(int address) {
    if (state.anchorAddress == address ||
        state.hiddenAddresses.contains(address)) {
      return;
    }

    final nextHiddenAddresses = <int>{...state.hiddenAddresses, address};
    final nextSelectedAddresses = state.selectionState.selectedAddresses
        .where((selectedAddress) => selectedAddress != address)
        .toList(growable: false);
    state = state.copyWith(
      hiddenAddresses: nextHiddenAddresses,
      selectionState: state.selectionState.copyWith(
        selectedAddresses: nextSelectedAddresses,
      ),
    );
  }

  void hideMany(Iterable<int> addresses) {
    final filteredAddresses = addresses
        .where((address) => address != state.anchorAddress)
        .toSet();
    if (filteredAddresses.isEmpty) {
      return;
    }

    final nextHiddenAddresses = <int>{
      ...state.hiddenAddresses,
      ...filteredAddresses,
    };
    final nextSelectedAddresses = state.selectionState.selectedAddresses
        .where(
          (selectedAddress) => !filteredAddresses.contains(selectedAddress),
        )
        .toList(growable: false);
    state = state.copyWith(
      hiddenAddresses: nextHiddenAddresses,
      selectionState: state.selectionState.copyWith(
        selectedAddresses: nextSelectedAddresses,
      ),
    );
  }

  void clear() {
    if (!state.hasAnchor &&
        state.results.isEmpty &&
        state.hiddenAddresses.isEmpty &&
        state.selectionState.selectedAddresses.isEmpty) {
      return;
    }
    state = const MemoryToolBrowseState();
  }

  Future<MemoryToolBrowseState> _buildWindowState({
    required int selectedPid,
    required SearchResult anchorResult,
    required List<MemoryRegion> readableRegions,
    required Set<int> preservedHiddenAddresses,
  }) async {
    final aboveCollected = _collectAlignedAddresses(
      anchorAddress: anchorResult.address,
      strideBytes: anchorResult.rawBytes.isEmpty
          ? 1
          : anchorResult.rawBytes.length,
      startStep: 1,
      targetCount: _memoryToolBrowseInitialExpandCount,
      isAbove: true,
      regions: readableRegions,
    );
    final belowCollected = _collectAlignedAddresses(
      anchorAddress: anchorResult.address,
      strideBytes: anchorResult.rawBytes.isEmpty
          ? 1
          : anchorResult.rawBytes.length,
      startStep: 1,
      targetCount: _memoryToolBrowseInitialExpandCount,
      isAbove: false,
      regions: readableRegions,
    );
    final aboveResults = await _readBrowseResults(
      selectedPid: selectedPid,
      anchorResult: anchorResult,
      readableRegions: readableRegions,
      addresses: aboveCollected.addresses.reversed.toList(growable: false),
    );
    final belowResults = await _readBrowseResults(
      selectedPid: selectedPid,
      anchorResult: anchorResult,
      readableRegions: readableRegions,
      addresses: belowCollected.addresses,
    );

    return MemoryToolBrowseState(
      anchorResult: anchorResult,
      regions: readableRegions,
      results: <SearchResult>[...aboveResults, anchorResult, ...belowResults],
      hiddenAddresses: preservedHiddenAddresses,
      selectionState: const MemoryToolResultSelectionState(),
      topNextStep: aboveCollected.nextStep,
      bottomNextStep: belowCollected.nextStep,
      reachedTopBoundary: aboveCollected.reachedBoundary,
      reachedBottomBoundary: belowCollected.reachedBoundary,
    );
  }

  Future<List<MemoryRegion>> _loadReadableRegions({required int pid}) async {
    final repository = ref.read(memoryQueryRepositoryProvider);
    final regions = <MemoryRegion>[];

    for (int offset = 0; ; offset += _memoryToolBrowseRegionPageSize) {
      final page = await repository.getMemoryRegions(
        pid: pid,
        offset: offset,
        limit: _memoryToolBrowseRegionPageSize,
        readableOnly: true,
        includeAnonymous: true,
        includeFileBacked: true,
      );
      if (page.isEmpty) {
        break;
      }

      regions.addAll(page);
      if (page.length < _memoryToolBrowseRegionPageSize) {
        break;
      }
    }

    regions.sort(
      (left, right) => left.startAddress.compareTo(right.startAddress),
    );
    return regions;
  }

  Future<List<SearchResult>> _readBrowseResults({
    required int selectedPid,
    required SearchResult anchorResult,
    required List<MemoryRegion> readableRegions,
    required List<int> addresses,
  }) async {
    if (addresses.isEmpty) {
      return const <SearchResult>[];
    }

    final strideBytes = anchorResult.rawBytes.isEmpty
        ? 1
        : anchorResult.rawBytes.length;
    final previews = await ref
        .read(memoryQueryRepositoryProvider)
        .readMemoryValues(
          requests: addresses
              .map(
              (address) => MemoryReadRequest(
                  pid: selectedPid,
                  address: address,
                  type: SearchValueType.bytes,
                  length: strideBytes,
                ),
              )
              .toList(growable: false),
        );

    final previewByAddress = <int, MemoryValuePreview>{
      for (final preview in previews) preview.address: preview,
    };

    final results = <SearchResult>[];
    for (final address in addresses) {
      final preview = previewByAddress[address];
      final region = _resolveRegionForAddress(
        regions: readableRegions,
        address: address,
        strideBytes: strideBytes,
      );
      if (preview == null || region == null) {
        continue;
      }

      results.add(
        SearchResult(
          address: address,
          regionStart: region.startAddress,
          regionTypeKey: _mapBrowseRegionTypeKey(region),
          type: anchorResult.type,
          rawBytes: preview.rawBytes,
          displayValue: resolveMemoryToolSearchResultValueByType(
            type: anchorResult.type,
            rawBytes: preview.rawBytes,
            fallbackDisplayValue: anchorResult.displayValue,
          ),
        ),
      );
    }
    return results;
  }

  Future<List<SearchResult>> _extendResultsAroundAnchor({
    required int selectedPid,
    required SearchResult anchorResult,
    required MemoryRegion anchorRegion,
    required List<SearchResult> existingResults,
  }) async {
    final strideBytes = anchorResult.rawBytes.isEmpty
        ? 1
        : anchorResult.rawBytes.length;
    final localRegions = <MemoryRegion>[anchorRegion];
    final aboveCollected = _collectAlignedAddresses(
      anchorAddress: anchorResult.address,
      strideBytes: strideBytes,
      startStep: 1,
      targetCount: _memoryToolBrowseInitialExpandCount,
      isAbove: true,
      regions: localRegions,
    );
    final belowCollected = _collectAlignedAddresses(
      anchorAddress: anchorResult.address,
      strideBytes: strideBytes,
      startStep: 1,
      targetCount: _memoryToolBrowseInitialExpandCount,
      isAbove: false,
      regions: localRegions,
    );
    final aboveResults = await _readBrowseResults(
      selectedPid: selectedPid,
      anchorResult: anchorResult,
      readableRegions: localRegions,
      addresses: aboveCollected.addresses.reversed.toList(growable: false),
    );
    final belowResults = await _readBrowseResults(
      selectedPid: selectedPid,
      anchorResult: anchorResult,
      readableRegions: localRegions,
      addresses: belowCollected.addresses,
    );
    return _mergeBrowseResults(
      existingResults,
      <SearchResult>[...aboveResults, anchorResult, ...belowResults],
    );
  }

  Future<void> _previewAnchorResult({
    required int selectedPid,
    required SearchResult anchorResult,
    List<MemoryRegion>? knownReadableRegions,
  }) async {
    final nextAnchorRegion = _resolveRegionForAddress(
      regions: state.regions,
      address: anchorResult.address,
      strideBytes: anchorResult.rawBytes.isEmpty ? 1 : anchorResult.rawBytes.length,
    );
    final resolvedAnchorResult = nextAnchorRegion == null
        ? anchorResult
        : _resolveAnchorResultWithRegion(
            anchorResult: anchorResult,
            region: nextAnchorRegion,
          );

    if (_canReuseCurrentWindow(
      state: state,
      anchorResult: resolvedAnchorResult,
    )) {
      final nextHiddenAddresses = <int>{
        ...state.hiddenAddresses,
      }..remove(resolvedAnchorResult.address);
      final nextResults = _replaceBrowseResult(
        state.results,
        resolvedAnchorResult,
      );
      final paginationState = _resolveBrowsePaginationState(
        anchorAddress: resolvedAnchorResult.address,
        strideBytes: resolvedAnchorResult.rawBytes.isEmpty
            ? 1
            : resolvedAnchorResult.rawBytes.length,
        regions: state.regions,
        loadedResults: nextResults,
      );
      state = state.copyWith(
        anchorResult: resolvedAnchorResult,
        results: nextResults,
        hiddenAddresses: nextHiddenAddresses,
        selectionState: const MemoryToolResultSelectionState(),
        focusRequestId: state.focusRequestId + 1,
        isInitializing: false,
        isLoadingAbove: false,
        isLoadingBelow: false,
        topNextStep: paginationState.topNextStep,
        bottomNextStep: paginationState.bottomNextStep,
        reachedTopBoundary: paginationState.reachedTopBoundary,
        reachedBottomBoundary: paginationState.reachedBottomBoundary,
        clearErrorText: true,
      );
      return;
    }

    if (_canReuseCurrentRegion(
      state: state,
      anchorResult: resolvedAnchorResult,
      anchorRegion: nextAnchorRegion,
    )) {
      try {
        final nextResults = await _extendResultsAroundAnchor(
          selectedPid: selectedPid,
          anchorResult: resolvedAnchorResult,
          anchorRegion: nextAnchorRegion!,
          existingResults: state.results,
        );
        final nextHiddenAddresses = <int>{
          ...state.hiddenAddresses,
        }..remove(resolvedAnchorResult.address);
        final paginationState = _resolveBrowsePaginationState(
          anchorAddress: resolvedAnchorResult.address,
          strideBytes: resolvedAnchorResult.rawBytes.isEmpty
              ? 1
              : resolvedAnchorResult.rawBytes.length,
          regions: state.regions,
          loadedResults: nextResults,
        );
        state = state.copyWith(
          anchorResult: resolvedAnchorResult,
          results: nextResults,
          hiddenAddresses: nextHiddenAddresses,
          selectionState: const MemoryToolResultSelectionState(),
          focusRequestId: state.focusRequestId + 1,
          isInitializing: false,
          isLoadingAbove: false,
          isLoadingBelow: false,
          topNextStep: paginationState.topNextStep,
          bottomNextStep: paginationState.bottomNextStep,
          reachedTopBoundary: paginationState.reachedTopBoundary,
          reachedBottomBoundary: paginationState.reachedBottomBoundary,
          clearErrorText: true,
        );
        return;
      } catch (error) {
        state = state.copyWith(errorText: error.toString());
      }
    }

    if (_canReuseKnownRegions(
      state: state,
      anchorResult: resolvedAnchorResult,
      anchorRegion: nextAnchorRegion,
    )) {
      final nextHiddenAddresses = <int>{
        ...state.hiddenAddresses,
      }..remove(resolvedAnchorResult.address);
      state = state.copyWith(
        isInitializing: true,
        isLoadingAbove: false,
        isLoadingBelow: false,
        clearErrorText: true,
      );
      try {
        final nextState = await _buildWindowState(
          selectedPid: selectedPid,
          anchorResult: resolvedAnchorResult,
          readableRegions: state.regions,
          preservedHiddenAddresses: nextHiddenAddresses,
        );
        state = nextState.copyWith(
          isInitializing: false,
          clearErrorText: true,
          focusRequestId: state.focusRequestId + 1,
        );
        return;
      } catch (error) {
        state = state.copyWith(
          isInitializing: false,
          errorText: error.toString(),
        );
      }
    }

    state = state.copyWith(
      isInitializing: true,
      isLoadingAbove: false,
      isLoadingBelow: false,
      clearErrorText: true,
    );

    try {
      final readableRegions =
          knownReadableRegions ?? await _loadReadableRegions(pid: selectedPid);
      if (readableRegions.isEmpty) {
        state = state.copyWith(
          results: const <SearchResult>[],
          regions: const <MemoryRegion>[],
          selectionState: const MemoryToolResultSelectionState(),
          hiddenAddresses: const <int>{},
          isInitializing: false,
          reachedTopBoundary: true,
          reachedBottomBoundary: true,
          errorText: 'No readable memory region.',
        );
        return;
      }

      final finalAnchorRegion = _resolveRegionForAddress(
        regions: readableRegions,
        address: resolvedAnchorResult.address,
        strideBytes: resolvedAnchorResult.rawBytes.isEmpty
            ? 1
            : resolvedAnchorResult.rawBytes.length,
      );
      final finalAnchorResult = finalAnchorRegion == null
          ? resolvedAnchorResult
          : _resolveAnchorResultWithRegion(
              anchorResult: resolvedAnchorResult,
              region: finalAnchorRegion,
            );
      final nextState = await _buildWindowState(
        selectedPid: selectedPid,
        anchorResult: finalAnchorResult,
        readableRegions: readableRegions,
        preservedHiddenAddresses: const <int>{},
      );
      state = nextState.copyWith(
        isInitializing: false,
        clearErrorText: true,
        focusRequestId: state.focusRequestId + 1,
      );
    } catch (error) {
      state = state.copyWith(
        isInitializing: false,
        errorText: error.toString(),
      );
    }
  }

  Future<MemoryValuePreview?> _readTargetPreviewOrNull({
    required int selectedPid,
    required int address,
    required int bytesLength,
  }) async {
    try {
      final previews = await ref
          .read(memoryQueryRepositoryProvider)
          .readMemoryValues(
            requests: <MemoryReadRequest>[
              MemoryReadRequest(
                pid: selectedPid,
                address: address,
                type: SearchValueType.bytes,
                length: bytesLength < 1 ? 1 : bytesLength,
              ),
            ],
          );
      if (previews.isEmpty) {
        return null;
      }
      return previews.first;
    } catch (_) {
      return null;
    }
  }
}

SearchResult _resolveAnchorResultWithRegion({
  required SearchResult anchorResult,
  required MemoryRegion region,
}) {
  return SearchResult(
    address: anchorResult.address,
    regionStart: region.startAddress,
    regionTypeKey: _mapBrowseRegionTypeKey(region),
    type: anchorResult.type,
    rawBytes: anchorResult.rawBytes,
    displayValue: anchorResult.displayValue,
  );
}

bool _canReuseCurrentWindow({
  required MemoryToolBrowseState state,
  required SearchResult anchorResult,
}) {
  if (!state.hasAnchor ||
      state.regions.isEmpty ||
      state.results.isEmpty ||
      state.isInitializing) {
    return false;
  }

  if (state.browseType != anchorResult.type ||
      state.strideBytes != anchorResult.rawBytes.length) {
    return false;
  }

  return state.results.any((result) => result.address == anchorResult.address);
}

bool _canReuseCurrentRegion({
  required MemoryToolBrowseState state,
  required SearchResult anchorResult,
  required MemoryRegion? anchorRegion,
}) {
  if (!_hasCompatibleBrowseShape(state: state, anchorResult: anchorResult) ||
      anchorRegion == null ||
      state.anchorResult == null) {
    return false;
  }
  return anchorRegion.startAddress == state.anchorResult!.regionStart;
}

bool _canReuseKnownRegions({
  required MemoryToolBrowseState state,
  required SearchResult anchorResult,
  required MemoryRegion? anchorRegion,
}) {
  return _hasCompatibleBrowseShape(state: state, anchorResult: anchorResult) &&
      anchorRegion != null;
}

bool _hasCompatibleBrowseShape({
  required MemoryToolBrowseState state,
  required SearchResult anchorResult,
}) {
  if (!state.hasAnchor ||
      state.regions.isEmpty ||
      state.results.isEmpty ||
      state.isInitializing) {
    return false;
  }

  if (state.browseType != anchorResult.type ||
      state.strideBytes != anchorResult.rawBytes.length) {
    return false;
  }

  return true;
}

List<SearchResult> _replaceBrowseResult(
  List<SearchResult> results,
  SearchResult nextResult,
) {
  return results
      .map(
        (result) => result.address == nextResult.address ? nextResult : result,
      )
      .toList(growable: false);
}

({
  int topNextStep,
  int bottomNextStep,
  bool reachedTopBoundary,
  bool reachedBottomBoundary,
}) _resolveBrowsePaginationState({
  required int anchorAddress,
  required int strideBytes,
  required List<MemoryRegion> regions,
  required List<SearchResult> loadedResults,
}) {
  final loadedAddresses = loadedResults.map((result) => result.address).toSet();
  final aboveState = _resolveNextStep(
    anchorAddress: anchorAddress,
    strideBytes: strideBytes,
    regions: regions,
    loadedAddresses: loadedAddresses,
    isAbove: true,
  );
  final belowState = _resolveNextStep(
    anchorAddress: anchorAddress,
    strideBytes: strideBytes,
    regions: regions,
    loadedAddresses: loadedAddresses,
    isAbove: false,
  );
  return (
    topNextStep: aboveState.nextStep,
    bottomNextStep: belowState.nextStep,
    reachedTopBoundary: aboveState.reachedBoundary,
    reachedBottomBoundary: belowState.reachedBoundary,
  );
}

({int nextStep, bool reachedBoundary}) _resolveNextStep({
  required int anchorAddress,
  required int strideBytes,
  required List<MemoryRegion> regions,
  required Set<int> loadedAddresses,
  required bool isAbove,
}) {
  if (regions.isEmpty) {
    return (nextStep: 1, reachedBoundary: true);
  }

  final minReadableAddress = regions.first.startAddress;
  final maxReadableAddress = regions.last.endAddress;
  var nextStep = 1;

  while (true) {
    final candidate = isAbove
        ? anchorAddress - (nextStep * strideBytes)
        : anchorAddress + (nextStep * strideBytes);
    final isOutOfTopBoundary = candidate < minReadableAddress;
    final isOutOfBottomBoundary = candidate + strideBytes > maxReadableAddress;
    if (isOutOfTopBoundary || isOutOfBottomBoundary) {
      return (nextStep: nextStep, reachedBoundary: true);
    }

    final hasValidRegion = _resolveRegionForAddress(
          regions: regions,
          address: candidate,
          strideBytes: strideBytes,
        ) !=
        null;
    if (hasValidRegion && !loadedAddresses.contains(candidate)) {
      return (nextStep: nextStep, reachedBoundary: false);
    }
    nextStep += 1;
  }
}

({List<int> addresses, int nextStep, bool reachedBoundary})
_collectAlignedAddresses({
  required int anchorAddress,
  required int strideBytes,
  required int startStep,
  required int targetCount,
  required bool isAbove,
  required List<MemoryRegion> regions,
}) {
  if (regions.isEmpty) {
    return (
      addresses: const <int>[],
      nextStep: startStep,
      reachedBoundary: true,
    );
  }

  final minReadableAddress = regions.first.startAddress;
  final maxReadableAddress = regions.last.endAddress;
  final addresses = <int>[];
  var nextStep = startStep;

  while (addresses.length < targetCount) {
    final candidate = isAbove
        ? anchorAddress - (nextStep * strideBytes)
        : anchorAddress + (nextStep * strideBytes);
    final isOutOfTopBoundary = candidate < minReadableAddress;
    final isOutOfBottomBoundary = candidate + strideBytes > maxReadableAddress;
    if (isOutOfTopBoundary || isOutOfBottomBoundary) {
      return (addresses: addresses, nextStep: nextStep, reachedBoundary: true);
    }

    if (_resolveRegionForAddress(
          regions: regions,
          address: candidate,
          strideBytes: strideBytes,
        ) !=
        null) {
      addresses.add(candidate);
    }
    nextStep += 1;
  }

  return (addresses: addresses, nextStep: nextStep, reachedBoundary: false);
}

MemoryRegion? _resolveRegionForAddress({
  required List<MemoryRegion> regions,
  required int address,
  required int strideBytes,
}) {
  for (final region in regions) {
    if (address < region.startAddress) {
      return null;
    }
    if (address >= region.startAddress &&
        address + strideBytes <= region.endAddress) {
      return region;
    }
    if (address < region.endAddress) {
      return null;
    }
  }
  return null;
}

String _mapBrowseRegionTypeKey(MemoryRegion region) {
  final lowerPath = (region.path ?? '').toLowerCase();
  final executable = region.perms.length > 2 && region.perms[2] == 'x';
  final isAppPath =
      lowerPath.startsWith('/data/app/') ||
      lowerPath.startsWith('/data/data/') ||
      lowerPath.startsWith('/mnt/expand/');
  final isSystemPath =
      lowerPath.startsWith('/system/') ||
      lowerPath.startsWith('/apex/') ||
      lowerPath.startsWith('/vendor/') ||
      lowerPath.startsWith('/product/');

  if (region.perms.isEmpty || region.perms[0] != 'r') {
    return 'bad';
  }

  if (lowerPath.contains('[stack')) {
    return 'stack';
  }

  if (lowerPath.contains('ashmem')) {
    if (lowerPath.contains('dalvik')) {
      return 'javaHeap';
    }
    return 'ashmem';
  }

  if (lowerPath.contains('dalvik-main space') ||
      lowerPath.contains('dalvik-allocspace') ||
      lowerPath.contains('dalvik-large object space') ||
      lowerPath.contains('dalvik-free list large object space') ||
      lowerPath.contains('dalvik-non moving space') ||
      lowerPath.contains('dalvik-zygote space')) {
    return 'javaHeap';
  }

  if (lowerPath.contains('dalvik') ||
      lowerPath.contains('.art') ||
      lowerPath.contains('.oat') ||
      lowerPath.contains('.odex')) {
    return 'java';
  }

  if (lowerPath.contains('[heap]')) {
    return 'cHeap';
  }

  if (lowerPath.contains('malloc') ||
      lowerPath.contains('scudo:') ||
      lowerPath.contains('jemalloc') ||
      lowerPath.contains('[anon:libc_malloc]')) {
    return 'cAlloc';
  }

  if (lowerPath.contains('.bss') || lowerPath.contains('[anon:.bss')) {
    return 'cBss';
  }

  if (executable) {
    if (isAppPath) {
      return 'codeApp';
    }
    if (isSystemPath || !region.isAnonymous) {
      return 'codeSys';
    }
  }

  if (!region.isAnonymous) {
    if (isAppPath || isSystemPath || lowerPath.contains('.so')) {
      return 'cData';
    }
    return 'other';
  }

  return 'anonymous';
}

Uint8List _resolveAnchorRawBytes({
  required MemoryValuePreview? preview,
  required SearchResult result,
}) {
  final rawBytes = preview?.rawBytes ?? result.rawBytes;
  if (rawBytes.isNotEmpty) {
    return rawBytes;
  }
  final fallbackLength = resolveMemoryToolReadLengthForType(
    type: preview?.type ?? result.type,
    bytesLength: rawBytes.length,
  );
  return Uint8List(fallbackLength);
}

List<SearchResult> _mergeBrowseResults(
  List<SearchResult> leading,
  List<SearchResult> trailing,
) {
  final merged = <int, SearchResult>{
    for (final result in leading) result.address: result,
    for (final result in trailing) result.address: result,
  };
  final sorted = merged.values.toList(growable: false)
    ..sort((left, right) => left.address.compareTo(right.address));
  return sorted;
}
