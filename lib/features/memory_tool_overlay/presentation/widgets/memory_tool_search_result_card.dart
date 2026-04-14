import 'package:JsxposedX/common/widgets/loading.dart';
import 'package:JsxposedX/common/widgets/ref_error.dart';
import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/providers/memory_query_provider.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/providers/memory_tool_search_provider.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/states/memory_tool_result_selection_state.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/widgets/memory_tool_result_selection_dialog.dart';
import 'package:JsxposedX/generated/memory_tool.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class MemoryToolSearchResultCard extends HookConsumerWidget {
  const MemoryToolSearchResultCard({
    super.key,
    required this.hasMatchingSession,
    required this.sessionStateAsync,
    required this.onRetry,
  });

  final bool hasMatchingSession;
  final AsyncValue<SearchSessionState> sessionStateAsync;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visibleLimit = useState(memoryToolSearchResultPageLimit);
    final scrollController = useScrollController();
    final isSettingsVisible = useState(false);
    final selectionState = ref.watch(memoryToolResultSelectionProvider);
    final selectionNotifier = ref.read(
      memoryToolResultSelectionProvider.notifier,
    );

    useEffect(() {
      visibleLimit.value = memoryToolSearchResultPageLimit;
      return null;
    }, [hasMatchingSession]);

    final resultsAsync = hasMatchingSession
        ? ref.watch(
            getSearchResultsProvider(offset: 0, limit: visibleLimit.value),
          )
        : const AsyncValue.data(<SearchResult>[]);

    useEffect(
      () {
        if (!hasMatchingSession) {
          return null;
        }

        void onScroll() {
          if (!scrollController.hasClients) {
            return;
          }

          final position = scrollController.position;
          final shouldLoadMore =
              position.pixels >= position.maxScrollExtent - 120.r;
          if (!shouldLoadMore) {
            return;
          }

          final totalCount = sessionStateAsync.maybeWhen(
            data: (state) => state.resultCount,
            orElse: () => 0,
          );
          if (totalCount <= visibleLimit.value) {
            return;
          }

          visibleLimit.value =
              (visibleLimit.value + memoryToolSearchResultPageLimit).clamp(
                0,
                totalCount,
              );
        }

        scrollController.addListener(onScroll);
        return () {
          scrollController.removeListener(onScroll);
        };
      },
      [
        hasMatchingSession,
        scrollController,
        sessionStateAsync,
        visibleLimit.value,
      ],
    );

    return Stack(
      children: <Widget>[
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 2.r),
          child: !hasMatchingSession
              ? Center(
                  child: Text(
                    context.l10n.noData,
                    style: context.textTheme.bodyMedium?.copyWith(
                      color: context.colorScheme.onSurface.withValues(
                        alpha: 0.66,
                      ),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              : resultsAsync.when(
                  data: (results) {
                    if (results.isEmpty) {
                      return Center(
                        child: Text(
                          context.l10n.noData,
                          style: context.textTheme.bodyMedium?.copyWith(
                            color: context.colorScheme.onSurface.withValues(
                              alpha: 0.66,
                            ),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    }

                    final totalCount = sessionStateAsync.maybeWhen(
                      data: (state) => state.resultCount,
                      orElse: () => results.length,
                    );
                    final hasMore = results.length < totalCount;

                    return Column(
                      children: <Widget>[
                        _MemoryToolResultSelectionBar(
                          onSelectAll: () {
                            selectionNotifier.selectVisible(results);
                          },
                          onInvert: () {
                            selectionNotifier.invertVisible(results);
                          },
                          onClear: selectionNotifier.clear,
                          onOpenSettings: () {
                            isSettingsVisible.value = true;
                          },
                        ),
                        SizedBox(height: 1.r),
                        Expanded(
                          child: ListView.separated(
                            controller: scrollController,
                            padding: EdgeInsets.zero,
                            itemCount: results.length + (hasMore ? 1 : 0),
                            separatorBuilder: (_, index) => SizedBox(
                              height: index == results.length - 1 && hasMore
                                  ? 6.r
                                  : 4.r,
                            ),
                            itemBuilder: (BuildContext context, int index) {
                              if (index >= results.length) {
                                return Padding(
                                  padding: EdgeInsets.symmetric(vertical: 4.r),
                                  child: Center(
                                    child: Text(
                                      '${results.length}/$totalCount',
                                      style: context.textTheme.labelMedium
                                          ?.copyWith(
                                            color: context.colorScheme.onSurface
                                                .withValues(alpha: 0.64),
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                );
                              }

                              final result = results[index];
                              return _MemoryToolSearchResultTile(
                                result: result,
                                isSelected: selectionState.contains(
                                  result.address,
                                ),
                                onTap: () {
                                  selectionNotifier.toggle(result);
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                  error: (error, _) => RefError(onRetry: onRetry, error: error),
                  loading: () => const Loading(),
                ),
        ),
        if (isSettingsVisible.value)
          Positioned.fill(
            child: MemoryToolResultSelectionDialog(
              initialLimit: selectionState.selectionLimit,
              onClose: () {
                isSettingsVisible.value = false;
              },
              onConfirm: (value) {
                selectionNotifier.updateSelectionLimit(value);
                isSettingsVisible.value = false;
              },
            ),
          ),
      ],
    );
  }
}

class _MemoryToolResultSelectionBar extends StatelessWidget {
  const _MemoryToolResultSelectionBar({
    required this.onSelectAll,
    required this.onInvert,
    required this.onClear,
    required this.onOpenSettings,
  });

  final VoidCallback onSelectAll;
  final VoidCallback onInvert;
  final VoidCallback onClear;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colorScheme.surface.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(
          color: context.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 8.r, vertical: 6.r),
        child: Row(
          children: <Widget>[
            _MemoryToolToolbarGroup(
              children: <Widget>[
                _MemoryToolToolbarAction(
                  icon: Icons.done_all_rounded,
                  onTap: onSelectAll,
                ),
                _MemoryToolToolbarDivider(),
                _MemoryToolToolbarAction(
                  icon: Icons.flip_rounded,
                  onTap: onInvert,
                ),
                _MemoryToolToolbarDivider(),
                _MemoryToolToolbarAction(
                  icon: Icons.layers_clear_rounded,
                  onTap: onClear,
                ),
                _MemoryToolToolbarDivider(),
                _MemoryToolToolbarAction(
                  icon: Icons.tune_rounded,
                  onTap: onOpenSettings,
                ),
              ],
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

class _MemoryToolToolbarGroup extends StatelessWidget {
  const _MemoryToolToolbarGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.42,
        ),
        borderRadius: BorderRadius.circular(10.r),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 4.r, vertical: 2.r),
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}

class _MemoryToolToolbarDivider extends StatelessWidget {
  const _MemoryToolToolbarDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 18.r,
      margin: EdgeInsets.symmetric(horizontal: 2.r),
      color: context.colorScheme.outlineVariant.withValues(alpha: 0.52),
    );
  }
}

class _MemoryToolToolbarAction extends StatelessWidget {
  const _MemoryToolToolbarAction({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8.r),
      onTap: onTap,
      child: SizedBox(
        width: 28.r,
        height: 28.r,
        child: Center(
          child: Icon(
            icon,
            size: 18.r,
            color: context.colorScheme.onSurface.withValues(alpha: 0.76),
          ),
        ),
      ),
    );
  }
}

class _MemoryToolSearchResultTile extends StatelessWidget {
  const _MemoryToolSearchResultTile({
    required this.result,
    required this.isSelected,
    required this.onTap,
  });

  final SearchResult result;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14.r),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: isSelected
                ? context.colorScheme.primaryContainer.withValues(alpha: 0.72)
                : context.colorScheme.surface.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(14.r),
            border: Border.all(
              color: isSelected
                  ? context.colorScheme.primary
                  : context.colorScheme.outlineVariant.withValues(alpha: 0.42),
            ),
          ),
          padding: EdgeInsets.all(12.r),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Transform.scale(
                scale: 0.9,
                child: Checkbox(
                  value: isSelected,
                  onChanged: (_) => onTap(),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              SizedBox(width: 4.r),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            _formatHex(result.address),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        SizedBox(width: 10.r),
                        Flexible(
                          child: Text(
                            result.displayValue,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: context.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: context.colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 2.r),
                    Text(
                      '${_typeLabel(result.type)}   ${_formatHex(result.regionStart)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.labelMedium?.copyWith(
                        color: context.colorScheme.onSurface.withValues(
                          alpha: 0.62,
                        ),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatHex(int value) {
    return '0x${value.toRadixString(16).toUpperCase()}';
  }

  String _typeLabel(SearchValueType type) {
    return switch (type) {
      SearchValueType.i8 => 'I8',
      SearchValueType.i16 => 'I16',
      SearchValueType.i32 => 'I32',
      SearchValueType.i64 => 'I64',
      SearchValueType.f32 => 'F32',
      SearchValueType.f64 => 'F64',
      SearchValueType.bytes => 'AOB',
    };
  }
}
