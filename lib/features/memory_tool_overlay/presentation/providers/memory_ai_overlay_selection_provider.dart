import 'package:JsxposedX/features/memory_tool_overlay/presentation/providers/memory_query_provider.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/providers/memory_tool_browse_provider.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/providers/memory_tool_saved_items_provider.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/providers/memory_tool_search_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final memoryAiOverlayHasSelectedValueProvider = Provider<bool>((ref) {
  final selectedProcess = ref.watch(memoryToolSelectedProcessProvider);
  if (selectedProcess == null) {
    return false;
  }

  final hasSearchSelection =
      ref.watch(hasMatchingSearchSessionProvider) &&
      ref.watch(
        memoryToolResultSelectionProvider.select(
          (state) => state.selectedCount > 0,
        ),
      );

  final browseSelectedAddresses = ref.watch(
    memoryToolBrowseControllerProvider.select(
      (state) => state.selectionState.selectedAddresses,
    ),
  );
  final browseVisibleAddresses = ref.watch(
    currentBrowseResultsProvider.select(
      (results) => results.map((item) => item.address).toSet(),
    ),
  );
  final hasBrowseSelection = browseSelectedAddresses.any(
    browseVisibleAddresses.contains,
  );

  final savedSelectedAddresses = ref.watch(
    memoryToolSavedItemSelectionProvider.select(
      (state) => state.selectedAddresses,
    ),
  );
  final savedVisibleAddresses = ref.watch(
    savedItemsForSelectedProcessProvider.select(
      (items) => items.map((item) => item.address).toSet(),
    ),
  );
  final hasSavedSelection = savedSelectedAddresses.any(
    savedVisibleAddresses.contains,
  );

  return hasSearchSelection || hasBrowseSelection || hasSavedSelection;
});
