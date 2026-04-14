import 'dart:async';

import 'package:JsxposedX/features/memory_tool_overlay/presentation/widgets/memory_tool_search_dialog.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/widgets/memory_tool_search_result_card.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/widgets/memory_tool_search_task_feedback.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/widgets/memory_tool_search_task_overlay.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/providers/memory_action_provider.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/providers/memory_query_provider.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/providers/memory_tool_search_provider.dart';
import 'package:JsxposedX/generated/memory_tool.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class MemoryToolSearchTab extends HookConsumerWidget {
  const MemoryToolSearchTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    useAutomaticKeepAlive();
    final isSearchDialogVisible = useState(false);
    final selectedPid = ref.watch(memoryToolSelectedProcessProvider)?.pid;
    final sessionStateAsync = ref.watch(getSearchSessionStateProvider);
    final taskStateAsync = ref.watch(getSearchTaskStateProvider);
    final hasMatchingSession = ref.watch(hasMatchingSearchSessionProvider);
    final hasRunningTask = ref.watch(hasRunningSearchTaskProvider);
    final previousTaskStatus = useRef<SearchTaskStatus?>(null);

    useEffect(() {
      if (!hasRunningTask) {
        return null;
      }

      final timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        ref.invalidate(getSearchTaskStateProvider);
      });
      return timer.cancel;
    }, [hasRunningTask]);

    useEffect(() {
      taskStateAsync.whenData((state) {
        final previousStatus = previousTaskStatus.value;
        final currentStatus = state.status;
        if (previousStatus == SearchTaskStatus.running &&
            currentStatus != SearchTaskStatus.running) {
          ref.invalidate(getSearchSessionStateProvider);
          ref.invalidate(getSearchTaskStateProvider);
          ref.invalidate(getSearchResultsProvider);
          ref.invalidate(hasMatchingSearchSessionProvider);
          ref.invalidate(currentSearchResultsProvider);
          ref.read(memoryToolResultSelectionProvider.notifier).clear();
        }
        previousTaskStatus.value = currentStatus;
      });
      return null;
    }, [taskStateAsync]);

    useEffect(() {
      ref.read(memoryToolResultSelectionProvider.notifier).clear();
      return null;
    }, [selectedPid]);

    useEffect(() {
      if (!hasMatchingSession) {
        ref.read(memoryToolResultSelectionProvider.notifier).clear();
      }
      return null;
    }, [hasMatchingSession]);

    final resultCard = MemoryToolSearchResultCard(
      hasMatchingSession: hasMatchingSession,
      sessionStateAsync: sessionStateAsync,
      onRetry: () {
        ref.invalidate(getSearchSessionStateProvider);
        ref.invalidate(getSearchResultsProvider);
        ref.invalidate(hasMatchingSearchSessionProvider);
        ref.invalidate(currentSearchResultsProvider);
      },
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final spacing = 12.r;
        final padding = EdgeInsets.all(
          constraints.maxHeight < 320 ? 8.r : 12.r,
        );
        final hasTaskFeedback = taskStateAsync.maybeWhen(
          data: (state) =>
              state.status == SearchTaskStatus.cancelled ||
              state.status == SearchTaskStatus.failed,
          orElse: () => false,
        );
        final content = Padding(
          padding: padding,
          child: Column(
            children: <Widget>[
              if (hasTaskFeedback) ...<Widget>[
                MemoryToolSearchTaskFeedback(taskStateAsync: taskStateAsync),
                SizedBox(height: spacing),
              ],
              Expanded(child: resultCard),
            ],
          ),
        );

        return Stack(
          children: <Widget>[
            Positioned.fill(child: content),
            Positioned(
              right: 16.r,
              bottom: 16.r,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: Size(52.r, 52.r),
                  padding: EdgeInsets.symmetric(horizontal: 16.r),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18.r),
                  ),
                ),
                onPressed: () {
                  isSearchDialogVisible.value = true;
                },
                child: Icon(Icons.search_rounded, size: 22.r),
              ),
            ),
            if (isSearchDialogVisible.value)
              Positioned.fill(
                child: MemoryToolSearchDialog(
                  onClose: () {
                    isSearchDialogVisible.value = false;
                  },
                ),
              ),
            MemoryToolSearchTaskOverlay(
              taskStateAsync: taskStateAsync,
              onCancel: () {
                ref.read(memorySearchActionProvider.notifier).cancelSearch();
              },
            ),
          ],
        );
      },
    );
  }
}
