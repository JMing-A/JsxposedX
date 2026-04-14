import 'dart:typed_data';

import 'package:JsxposedX/features/memory_tool_overlay/presentation/providers/memory_action_provider.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/providers/memory_query_provider.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/states/memory_tool_result_selection_state.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/states/memory_tool_search_state.dart';
import 'package:JsxposedX/generated/memory_tool.g.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'memory_tool_search_provider.g.dart';

const int memoryToolSearchResultPageLimit = 20;

@riverpod
bool hasMatchingSearchSession(Ref ref) {
  final selectedProcess = ref.watch(memoryToolSelectedProcessProvider);
  final sessionStateAsync = ref.watch(getSearchSessionStateProvider);

  return sessionStateAsync.maybeWhen(
    data: (state) =>
        selectedProcess != null &&
        state.hasActiveSession &&
        state.pid == selectedProcess.pid,
    orElse: () => false,
  );
}

@riverpod
bool hasRunningSearchTask(Ref ref) {
  final taskStateAsync = ref.watch(getSearchTaskStateProvider);
  return taskStateAsync.maybeWhen(
    data: (state) => state.status == SearchTaskStatus.running,
    orElse: () => false,
  );
}

@riverpod
AsyncValue<List<SearchResult>> currentSearchResults(Ref ref) {
  final hasMatchingSession = ref.watch(hasMatchingSearchSessionProvider);
  if (!hasMatchingSession) {
    return const AsyncData<List<SearchResult>>(<SearchResult>[]);
  }

  return ref.watch(
    getSearchResultsProvider(offset: 0, limit: memoryToolSearchResultPageLimit),
  );
}

final memoryToolResultSelectionProvider = NotifierProvider<
  MemoryToolResultSelectionController,
  MemoryToolResultSelectionState
>(MemoryToolResultSelectionController.new);

class MemoryToolResultSelectionController
    extends Notifier<MemoryToolResultSelectionState> {
  @override
  MemoryToolResultSelectionState build() {
    return const MemoryToolResultSelectionState();
  }

  void updateSelectionLimit(int limit) {
    final clampedLimit = limit < 1 ? 1 : limit;
    state = state.copyWith(
      selectionLimit: clampedLimit,
      selectedAddresses: state.selectedAddresses.take(clampedLimit).toList(),
    );
  }

  void toggle(SearchResult result) {
    final selected = List<int>.from(state.selectedAddresses);
    final address = result.address;
    final existingIndex = selected.indexOf(address);
    if (existingIndex >= 0) {
      selected.removeAt(existingIndex);
      state = state.copyWith(selectedAddresses: selected);
      return;
    }

    if (state.selectionLimit == 1) {
      state = state.copyWith(selectedAddresses: <int>[address]);
      return;
    }

    if (selected.length >= state.selectionLimit) {
      return;
    }

    selected.add(address);
    state = state.copyWith(selectedAddresses: selected);
  }

  void selectVisible(List<SearchResult> results) {
    state = state.copyWith(
      selectedAddresses: results
          .take(state.selectionLimit)
          .map((result) => result.address)
          .toList(),
    );
  }

  void invertVisible(List<SearchResult> results) {
    final visibleAddresses = results.map((result) => result.address).toSet();
    final preserved = state.selectedAddresses
        .where((address) => !visibleAddresses.contains(address))
        .toList();
    final selectedVisible = state.selectedAddresses.toSet();
    for (final result in results) {
      if (selectedVisible.contains(result.address)) {
        continue;
      }
      if (preserved.length >= state.selectionLimit) {
        break;
      }
      preserved.add(result.address);
    }

    state = state.copyWith(selectedAddresses: preserved);
  }

  void clear() {
    if (state.selectedAddresses.isEmpty) {
      return;
    }
    state = state.copyWith(selectedAddresses: const <int>[]);
  }
}

@Riverpod(keepAlive: true)
class MemoryToolSearchForm extends _$MemoryToolSearchForm {
  @override
  MemoryToolSearchState build() {
    return const MemoryToolSearchState();
  }

  void updateValue(String value) {
    state = state.copyWith(value: value, validationError: null);
  }

  void updateType(SearchValueType type) {
    state = state.copyWith(selectedType: type, validationError: null);
  }

  void updateEndian(bool isLittleEndian) {
    state = state.copyWith(isLittleEndian: isLittleEndian);
  }

  Future<void> firstScan() async {
    final selectedProcess = ref.read(memoryToolSelectedProcessProvider);
    if (selectedProcess == null) {
      return;
    }

    final validationError = _validateValue(
      type: state.selectedType,
      rawValue: state.value,
    );
    if (validationError != null) {
      state = state.copyWith(validationError: validationError);
      return;
    }

    final request = FirstScanRequest(
      pid: selectedProcess.pid,
      value: _buildSearchValue(),
      matchMode: SearchMatchMode.exact,
      scanAllReadableRegions: true,
    );

    state = state.copyWith(validationError: null);
    await ref
        .read(memorySearchActionProvider.notifier)
        .firstScan(request: request);
  }

  Future<void> nextScan() async {
    final selectedProcess = ref.read(memoryToolSelectedProcessProvider);
    if (selectedProcess == null) {
      return;
    }

    final validationError = _validateValue(
      type: state.selectedType,
      rawValue: state.value,
    );
    if (validationError != null) {
      state = state.copyWith(validationError: validationError);
      return;
    }

    final latestSessionState = await ref.refresh(
      getSearchSessionStateProvider.future,
    );
    final hasMatchingSession =
        latestSessionState.hasActiveSession &&
        latestSessionState.pid == selectedProcess.pid;
    if (!hasMatchingSession) {
      throw StateError('当前没有可继续筛选的搜索会话，请先重新执行首次扫描。');
    }

    final request = NextScanRequest(
      value: _buildSearchValue(),
      matchMode: SearchMatchMode.exact,
    );

    state = state.copyWith(validationError: null);
    await ref
        .read(memorySearchActionProvider.notifier)
        .nextScan(request: request);
  }

  Future<void> resetSearchSession() async {
    state = state.copyWith(validationError: null);
    await ref.read(memorySearchActionProvider.notifier).resetSearchSession();
  }

  MemoryToolSearchValidationError? _validateValue({
    required SearchValueType type,
    required String rawValue,
  }) {
    final trimmedValue = rawValue.trim();
    if (trimmedValue.isEmpty) {
      return MemoryToolSearchValidationError.valueRequired;
    }

    if (type == SearchValueType.bytes && _parseBytes(trimmedValue) == null) {
      return MemoryToolSearchValidationError.invalidBytes;
    }

    return null;
  }

  SearchValue _buildSearchValue() {
    final trimmedValue = state.value.trim();
    final bytesValue = state.selectedType == SearchValueType.bytes
        ? _parseBytes(trimmedValue)
        : null;

    return SearchValue(
      type: state.selectedType,
      textValue: state.selectedType == SearchValueType.bytes
          ? null
          : trimmedValue,
      bytesValue: bytesValue,
      littleEndian: state.isLittleEndian,
    );
  }

  Uint8List? _parseBytes(String rawValue) {
    final sanitized = rawValue
        .replaceAll(RegExp(r'0x', caseSensitive: false), '')
        .replaceAll(RegExp(r'[^0-9a-fA-F]'), '');

    if (sanitized.isEmpty || sanitized.length.isOdd) {
      return null;
    }

    final bytes = <int>[];
    for (int index = 0; index < sanitized.length; index += 2) {
      final value = int.tryParse(
        sanitized.substring(index, index + 2),
        radix: 16,
      );
      if (value == null) {
        return null;
      }
      bytes.add(value);
    }

    return Uint8List.fromList(bytes);
  }
}
