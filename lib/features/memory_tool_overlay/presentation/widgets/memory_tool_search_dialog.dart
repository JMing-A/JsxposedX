import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/providers/memory_action_provider.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/providers/memory_query_provider.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/providers/memory_tool_search_provider.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/widgets/memory_tool_search_form_card.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/widgets/memory_tool_search_session_card.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/widgets/memory_tool_search_task_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class MemoryToolSearchDialog extends HookConsumerWidget {
  const MemoryToolSearchDialog({
    super.key,
    required this.onClose,
  });

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedProcess = ref.watch(memoryToolSelectedProcessProvider);
    final searchFormState = ref.watch(memoryToolSearchFormProvider);
    final searchActionState = ref.watch(memorySearchActionProvider);
    final taskStateAsync = ref.watch(getSearchTaskStateProvider);
    final sessionStateAsync = ref.watch(getSearchSessionStateProvider);
    final hasMatchingSession = ref.watch(hasMatchingSearchSessionProvider);
    final hasRunningTask = ref.watch(hasRunningSearchTaskProvider);
    final valueController = useTextEditingController(text: searchFormState.value);

    useEffect(() {
      Future.microtask(() {
        ref.invalidate(getSearchSessionStateProvider);
        ref.invalidate(getSearchTaskStateProvider);
      });
      return null;
    }, const []);

    useEffect(() {
      if (valueController.text == searchFormState.value) {
        return null;
      }

      valueController.value = valueController.value.copyWith(
        text: searchFormState.value,
        selection: TextSelection.collapsed(
          offset: searchFormState.value.length,
        ),
        composing: TextRange.empty,
      );
      return null;
    }, [searchFormState.value, valueController]);

    Future<void> runAndClose(Future<void> Function() action) async {
      await action();
      if (!context.mounted) {
        return;
      }

      final latestFormState = ref.read(memoryToolSearchFormProvider);
      final latestActionState = ref.read(memorySearchActionProvider);
      final shouldDismiss =
          latestFormState.validationError == null && !latestActionState.hasError;
      if (shouldDismiss) {
        onClose();
      }
    }

    return Material(
      color: Colors.black.withValues(alpha: 0.35),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onClose,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isLandscapeDialog =
                constraints.maxWidth > constraints.maxHeight * 1.1;
            final availableWidth = (constraints.maxWidth - 20.0)
                .clamp(0.0, double.infinity)
                .toDouble();
            final availableHeight = constraints.maxHeight
                .clamp(0.0, double.infinity)
                .toDouble();
            final dialogWidthCap = isLandscapeDialog ? 560.0 : 388.0;
            final dialogHeightCap = isLandscapeDialog ? 360.0 : 460.0;
            final dialogWidth = availableWidth < dialogWidthCap
                ? availableWidth
                : dialogWidthCap;
            final dialogMaxHeight = isLandscapeDialog
                ? availableHeight * 0.9
                : (availableHeight < dialogHeightCap
                      ? availableHeight
                      : dialogHeightCap);

            if (dialogWidth <= 0 || dialogMaxHeight <= 0) {
              return const SizedBox.shrink();
            }

            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: Material(
                    color: context.colorScheme.surface,
                    borderRadius: BorderRadius.circular(18.r),
                    clipBehavior: Clip.antiAlias,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: dialogWidth,
                        maxHeight: dialogMaxHeight,
                      ),
                      child: SizedBox(
                        width: dialogWidth,
                        child: SingleChildScrollView(
                          padding: EdgeInsets.all(14.r),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            if (selectedProcess != null) ...<Widget>[
                                MemoryToolSearchSessionCard(
                                  sessionStateAsync: sessionStateAsync,
                                  selectedPid: selectedProcess.pid,
                                ),
                                SizedBox(height: 12.r),
                              ],
                              MemoryToolSearchFormCard(
                                valueController: valueController,
                                state: searchFormState,
                                actionState: searchActionState,
                                hasRunningTask: hasRunningTask,
                                canRunNextScan: hasMatchingSession,
                                onValueChanged: ref
                                    .read(memoryToolSearchFormProvider.notifier)
                                    .updateValue,
                                onTypeChanged: ref
                                    .read(memoryToolSearchFormProvider.notifier)
                                    .updateType,
                                onEndianChanged: ref
                                    .read(memoryToolSearchFormProvider.notifier)
                                    .updateEndian,
                                onFirstScan: () => runAndClose(
                                  ref
                                      .read(memoryToolSearchFormProvider.notifier)
                                      .firstScan,
                                ),
                                onNextScan: () => runAndClose(
                                  ref
                                      .read(memoryToolSearchFormProvider.notifier)
                                      .nextScan,
                                ),
                                onReset: () => runAndClose(
                                  ref
                                      .read(memoryToolSearchFormProvider.notifier)
                                      .resetSearchSession,
                                ),
                                taskStatus: MemoryToolSearchTaskFeedback(
                                  taskStateAsync: taskStateAsync,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
