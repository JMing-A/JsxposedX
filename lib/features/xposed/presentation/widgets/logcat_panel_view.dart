import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/features/xposed/presentation/providers/logcat_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

// Mirrors the hardcoded tags in logcat_provider._passesFilter
const _kQuickFilterTags = [
  (label: 'All JsX', tag: 'JsxposedX'),
  (label: 'Frida', tag: 'JsxposedX-Frida'),
  (label: 'Shell', tag: 'JsxposedX-Shell'),
  (label: 'Provider', tag: 'JsxposedX-JsxposedProvider'),
  (label: 'Hook', tag: 'HookJsXposed'),
  (label: 'Error', tag: 'E'),
];

class LogcatPanelView extends HookConsumerWidget {
  final bool isFullscreen;
  final VoidCallback onToggleFullscreen;

  const LogcatPanelView({
    super.key,
    required this.isFullscreen,
    required this.onToggleFullscreen,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logEntries = ref.watch(logcatProvider);
    final logcatNotifier = ref.read(logcatProvider.notifier);
    final autoScroll = logcatNotifier.isAutoScroll;
    final searchQuery = logcatNotifier.searchQuery;
    final scrollController = useScrollController();
    final selectedTag = useState<String?>(null);

    // 使用 useMemoized 缓存过滤结果，避免每次都重新计算
    final filteredEntries = useMemoized(() {
      return logEntries.where((entry) {
        // Text search filter (from provider search query)
        if (searchQuery.isNotEmpty &&
            !entry.rawLine.toLowerCase().contains(searchQuery.toLowerCase())) {
          return false;
        }
        // Tag quick filter (local UI state)
        if (selectedTag.value != null) {
          // 对于 Error 和 Warning，匹配 level
          if (selectedTag.value == 'E' || selectedTag.value == 'W') {
            return entry.level == selectedTag.value;
          }
          // 其他标签匹配 tag 或 rawLine
          if (entry.tag.isNotEmpty) {
            return entry.tag.contains(selectedTag.value!);
          }
          return entry.rawLine.contains(selectedTag.value!);
        }
        return true;
      }).toList();
    }, [logEntries, searchQuery, selectedTag.value]);

    ref.listen(logcatProvider, (previous, next) {
      if (logcatNotifier.isAutoScroll && scrollController.hasClients) {
        Future.delayed(const Duration(milliseconds: 50), () {
          if (scrollController.hasClients) {
            scrollController.jumpTo(scrollController.position.maxScrollExtent);
          }
        });
      }
    });

    final isAnyFiltered = searchQuery.isNotEmpty || selectedTag.value != null;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        border: Border(
          top: BorderSide(
            color: context.theme.dividerColor.withValues(alpha: 0.15),
          ),
        ),
      ),
      child: Column(
        children: [
          // ── Toolbar ──
          _LogcatToolbar(
            autoScroll: autoScroll,
            filteredCount: filteredEntries.length,
            totalCount: logEntries.length,
            isFullscreen: isFullscreen,
            onSearchChanged: logcatNotifier.setSearchQuery,
            onAutoScrollToggle: () =>
                logcatNotifier.setAutoScroll(!autoScroll),
            onClear: logcatNotifier.clear,
            onToggleFullscreen: onToggleFullscreen,
          ),
          Divider(
            height: 1,
            thickness: 0.5,
            color: Colors.white.withValues(alpha: 0.06),
          ),
          // ── Tag Filter Chips ──
          _TagFilterRow(
            selectedTag: selectedTag.value,
            onTagSelected: (tag) => selectedTag.value = tag,
          ),
          Divider(
            height: 1,
            thickness: 0.5,
            color: Colors.white.withValues(alpha: 0.04),
          ),
          // ── Log List ──
          Expanded(
            child: filteredEntries.isEmpty
                ? _EmptyState(isFiltered: isAnyFiltered)
                : ListView.builder(
                    controller: scrollController,
                    padding: EdgeInsets.symmetric(vertical: 4.h),
                    itemCount: filteredEntries.length,
                    itemBuilder: (context, index) =>
                        _LogRow(entry: filteredEntries[index]),
                  ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Toolbar
// ─────────────────────────────────────────────

class _LogcatToolbar extends StatelessWidget {
  final bool autoScroll;
  final int filteredCount;
  final int totalCount;
  final bool isFullscreen;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onAutoScrollToggle;
  final VoidCallback onClear;
  final VoidCallback onToggleFullscreen;

  const _LogcatToolbar({
    required this.autoScroll,
    required this.filteredCount,
    required this.totalCount,
    required this.isFullscreen,
    required this.onSearchChanged,
    required this.onAutoScrollToggle,
    required this.onClear,
    required this.onToggleFullscreen,
  });

  @override
  Widget build(BuildContext context) {
    final isFiltered = filteredCount != totalCount;
    return Container(
      height: 38.h,
      padding: EdgeInsets.symmetric(horizontal: 10.w),
      color: const Color(0xFF1A1A1A),
      child: Row(
        children: [
          Icon(
            Icons.terminal_rounded,
            size: 13.sp,
            color: Colors.grey[500],
          ),
          SizedBox(width: 6.w),
          Text(
            context.l10n.terminal,
            style: TextStyle(
              fontSize: 12.sp,
              fontWeight: FontWeight.w600,
              color: Colors.grey[300],
              letterSpacing: 0.4,
            ),
          ),
          SizedBox(width: 6.w),
          // Entry count badge
          if (totalCount > 0)
            Container(
              padding: EdgeInsets.symmetric(horizontal: 5.w, vertical: 1.h),
              decoration: BoxDecoration(
                color: isFiltered
                    ? Colors.blue.withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Text(
                isFiltered ? '$filteredCount/$totalCount' : '$totalCount',
                style: TextStyle(
                  fontSize: 9.sp,
                  color: isFiltered ? Colors.blue[300] : Colors.grey[500],
                  fontFamily: 'monospace',
                ),
              ),
            ),
          const Spacer(),
          // Search field
          SizedBox(
            width: 130.w,
            height: 26.h,
            child: TextField(
              style: TextStyle(fontSize: 11.sp, color: Colors.grey[200]),
              decoration: InputDecoration(
                hintText: context.l10n.terminalFilterHint,
                hintStyle: TextStyle(
                  fontSize: 11.sp,
                  color: Colors.grey[700],
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 13.sp,
                  color: Colors.grey[600],
                ),
                prefixIconConstraints: BoxConstraints(minWidth: 28.w),
                contentPadding: EdgeInsets.symmetric(vertical: 4.h),
                isDense: true,
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6.r),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6.r),
                  borderSide: BorderSide(
                    color: Colors.grey[600]!,
                    width: 0.8,
                  ),
                ),
              ),
              onChanged: onSearchChanged,
            ),
          ),
          SizedBox(width: 8.w),
          _ToolbarIconButton(
            icon: autoScroll
                ? Icons.vertical_align_bottom_rounded
                : Icons.pause_circle_outline_rounded,
            tooltip: context.l10n.autoScroll,
            color: autoScroll ? const Color(0xFF66BB6A) : Colors.grey[600]!,
            onPressed: onAutoScrollToggle,
          ),
          SizedBox(width: 2.w),
          _ToolbarIconButton(
            icon: Icons.delete_sweep_outlined,
            tooltip: context.l10n.clearPanel,
            color: Colors.grey[600]!,
            onPressed: onClear,
          ),
          SizedBox(width: 2.w),
          // Fullscreen toggle
          _ToolbarIconButton(
            icon: isFullscreen
                ? Icons.close_fullscreen_rounded
                : Icons.open_in_full_rounded,
            tooltip: context.l10n.logcatFullscreen,
            color:
                isFullscreen ? Colors.blue[300]! : Colors.grey[600]!,
            onPressed: onToggleFullscreen,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Tag Filter Row
// ─────────────────────────────────────────────

class _TagFilterRow extends StatelessWidget {
  final String? selectedTag;
  final ValueChanged<String?> onTagSelected;

  const _TagFilterRow({
    required this.selectedTag,
    required this.onTagSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32.h,
      color: const Color(0xFF161616),
      padding: EdgeInsets.symmetric(horizontal: 10.w),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _kQuickFilterTags.length + 1, // +1 for "All"
        separatorBuilder: (_, __) => SizedBox(width: 6.w),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _TagChip(
              label: 'All',
              isSelected: selectedTag == null,
              onTap: () => onTagSelected(null),
            );
          }
          final filter = _kQuickFilterTags[index - 1];
          return _TagChip(
            label: filter.label,
            isSelected: selectedTag == filter.tag,
            onTap: () => onTagSelected(
              selectedTag == filter.tag ? null : filter.tag,
            ),
          );
        },
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _TagChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        alignment: Alignment.center,
        margin: EdgeInsets.symmetric(vertical: 5.h),
        padding: EdgeInsets.symmetric(horizontal: 8.w),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.blue.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(
            color: isSelected
                ? Colors.blue.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.07),
            width: 0.8,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.sp,
            fontFamily: 'monospace',
            color: isSelected ? Colors.blue[200] : Colors.grey[500],
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Log Row
// ─────────────────────────────────────────────

class _LogRow extends StatelessWidget {
  final LogcatEntry entry;

  const _LogRow({required this.entry});

  Color get _levelColor => switch (entry.level) {
        'E' => const Color(0xFFEF5350),
        'F' => const Color(0xFFEC407A),
        'W' => const Color(0xFFFFA726),
        'D' => const Color(0xFF42A5F5),
        _ => const Color(0xFFB0BEC5),
      };

  Color get _rowBgColor => switch (entry.level) {
        'E' || 'F' => const Color(0x14EF5350),
        'W' => const Color(0x0DFFA726),
        _ => Colors.transparent,
      };

  @override
  Widget build(BuildContext context) {
    final hasStructured = entry.tag.isNotEmpty;
    // Show only HH:MM:SS.mmm from "MM-DD HH:MM:SS.mmm" (skip first 6 chars)
    final timeDisplay =
        entry.timestamp.length > 6 ? entry.timestamp.substring(6) : '';

    return Container(
      color: _rowBgColor,
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 3.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Level badge
          Container(
            width: 16.w,
            height: 16.h,
            margin: EdgeInsets.only(top: 2.h),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _levelColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(3.r),
            ),
            child: Text(
              entry.level,
              style: TextStyle(
                fontSize: 9.5.sp,
                fontWeight: FontWeight.bold,
                color: _levelColor,
                fontFamily: 'monospace',
              ),
            ),
          ),
          SizedBox(width: 8.w),
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasStructured)
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.tag,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.sp,
                            color: _levelColor.withValues(alpha: 0.7),
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (timeDisplay.isNotEmpty)
                        Text(
                          timeDisplay,
                          style: TextStyle(
                            fontSize: 9.sp,
                            color: Colors.grey[700],
                            fontFamily: 'monospace',
                          ),
                        ),
                    ],
                  ),
                SelectableText(
                  hasStructured ? entry.message : entry.rawLine,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11.sp,
                    color: entry.level == 'E' || entry.level == 'F'
                        ? const Color(0xFFEF9A9A)
                        : entry.level == 'W'
                            ? const Color(0xFFFFCC80)
                            : Colors.white70,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Empty State
// ─────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool isFiltered;

  const _EmptyState({required this.isFiltered});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isFiltered ? Icons.filter_list_off : Icons.terminal_rounded,
              size: 28.sp,
              color: Colors.grey[800],
            ),
            SizedBox(height: 8.h),
            Text(
              isFiltered ? context.l10n.noLogsFiltered : context.l10n.noLogs,
              style: TextStyle(fontSize: 12.sp, color: Colors.grey[700]),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Toolbar Icon Button
// ─────────────────────────────────────────────

class _ToolbarIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onPressed;

  const _ToolbarIconButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4.r),
        child: Padding(
          padding: EdgeInsets.all(5.w),
          child: Icon(icon, size: 15.sp, color: color),
        ),
      ),
    );
  }
}
