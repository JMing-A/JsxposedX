import 'dart:typed_data';

import 'package:JsxposedX/common/widgets/overlay_window/overlay_panel_dialog.dart';
import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/utils/memory_tool_search_result_presenter.dart';
import 'package:JsxposedX/generated/memory_tool.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class MemoryToolBreakpointConfigDialog extends HookWidget {
  const MemoryToolBreakpointConfigDialog({
    super.key,
    required this.pid,
    required this.result,
    required this.preview,
    required this.onConfirm,
    required this.onClose,
  });

  final int pid;
  final SearchResult result;
  final MemoryValuePreview? preview;
  final Future<void> Function(AddMemoryBreakpointRequest request) onConfirm;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final initialLength = _resolveInitialLength(result, preview);
    final selectedLength = useState<int>(initialLength);
    final accessType = useState<MemoryBreakpointAccessType>(
      MemoryBreakpointAccessType.write,
    );
    final pauseOnHit = useState<bool>(true);
    final isSubmitting = useState<bool>(false);
    final candidateLengths = _resolveSupportedLengths(
      preview?.rawBytes ?? result.rawBytes,
    );

    return OverlayPanelDialog.card(
      onClose: () {
        if (isSubmitting.value) {
          return;
        }
        onClose();
      },
      maxWidthPortrait: 388.r,
      maxWidthLandscape: 560.r,
      maxHeightPortrait: 460.r,
      maxHeightLandscape: 360.r,
      cardBorderRadius: 18.r,
      childBuilder: (context, viewport, layout) {
        return Padding(
          padding: EdgeInsets.all(14.r),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        context.isZh ? '断点调试' : 'Breakpoint Debug',
                        style: context.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 6.r),
                      Text(
                        '${context.isZh ? '地址' : 'Address'}: 0x${formatMemoryToolSearchResultAddress(result.address)}',
                        style: context.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 4.r),
                      Text(
                        '${context.isZh ? '当前值' : 'Current Value'}: ${preview?.displayValue ?? result.displayValue}',
                        style: context.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 12.r),
                _SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        context.isZh ? '监控方式' : 'Access Type',
                        style: context.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 10.r),
                      Wrap(
                        spacing: 8.r,
                        runSpacing: 8.r,
                        children: MemoryBreakpointAccessType.values
                            .map(
                              (type) => ChoiceChip(
                                selected: accessType.value == type,
                                label: Text(_mapAccessTypeLabel(context, type)),
                                onSelected: isSubmitting.value
                                    ? null
                                    : (_) {
                                        accessType.value = type;
                                      },
                              ),
                            )
                            .toList(growable: false),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 12.r),
                _SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        context.isZh ? '监控长度' : 'Watch Length',
                        style: context.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 4.r),
                      Text(
                        context.isZh
                            ? 'CPU 硬件断点监控的是从当前地址开始的一段字节范围，支持 1 / 2 / 4 / 8 字节。'
                            : 'Hardware watchpoints monitor a byte range from the current address. Supported sizes: 1 / 2 / 4 / 8 bytes.',
                        style: context.textTheme.bodySmall?.copyWith(
                          color: context.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      SizedBox(height: 10.r),
                      Wrap(
                        spacing: 8.r,
                        runSpacing: 8.r,
                        children: candidateLengths
                            .map(
                              (length) => ChoiceChip(
                                selected: selectedLength.value == length,
                                label: Text('$length B'),
                                onSelected: isSubmitting.value
                                    ? null
                                    : (_) {
                                        selectedLength.value = length;
                                      },
                              ),
                            )
                            .toList(growable: false),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 12.r),
                _SectionCard(
                  child: SwitchListTile.adaptive(
                    value: pauseOnHit.value,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(context.isZh ? '命中后暂停进程' : 'Pause Process On Hit'),
                    subtitle: Text(
                      context.isZh
                          ? '命中后先停住，方便看是谁写了它。'
                          : 'Pause immediately on hit so you can inspect the writer.',
                    ),
                    onChanged: isSubmitting.value
                        ? null
                        : (value) {
                            pauseOnHit.value = value;
                          },
                  ),
                ),
                SizedBox(height: 12.r),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: isSubmitting.value ? null : onClose,
                        child: Text(context.isZh ? '取消' : 'Cancel'),
                      ),
                    ),
                    SizedBox(width: 10.r),
                    Expanded(
                      child: FilledButton(
                        onPressed: isSubmitting.value
                            ? null
                            : () async {
                                isSubmitting.value = true;
                                try {
                                  await onConfirm(
                                    AddMemoryBreakpointRequest(
                                      pid: pid,
                                      address: result.address,
                                      type: result.type,
                                      length: selectedLength.value,
                                      accessType: accessType.value,
                                      enabled: true,
                                      pauseProcessOnHit: pauseOnHit.value,
                                    ),
                                  );
                                } finally {
                                  isSubmitting.value = false;
                                }
                              },
                        child: Text(context.isZh ? '创建断点' : 'Create Breakpoint'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<int> _resolveSupportedLengths(Uint8List bytes) {
    final availableLength = bytes.isEmpty ? 1 : bytes.length;
    const supported = <int>[1, 2, 4, 8];
    final valid = supported
        .where((length) => length <= availableLength)
        .toList(growable: true);
    if (valid.length < supported.length) {
      final fallback = supported.firstWhere(
        (length) => length >= availableLength,
        orElse: () => 8,
      );
      if (!valid.contains(fallback)) {
        valid.add(fallback);
      }
    }
    if (valid.isEmpty) {
      valid.add(1);
    }
    valid.sort();
    return valid;
  }

  int _resolveInitialLength(SearchResult result, MemoryValuePreview? preview) {
    final rawLength = resolveMemoryToolReadLengthForType(
      type: result.type,
      bytesLength: preview?.rawBytes.length ?? result.rawBytes.length,
    );
    for (final supported in const <int>[1, 2, 4, 8]) {
      if (rawLength <= supported) {
        return supported;
      }
    }
    return 8;
  }

  String _mapAccessTypeLabel(
    BuildContext context,
    MemoryBreakpointAccessType type,
  ) {
    return switch (type) {
      MemoryBreakpointAccessType.read => context.isZh ? '读' : 'Read',
      MemoryBreakpointAccessType.write => context.isZh ? '写' : 'Write',
      MemoryBreakpointAccessType.readWrite => context.isZh ? '读写' : 'Read/Write',
    };
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colorScheme.surfaceContainerHighest.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: context.colorScheme.outlineVariant.withValues(alpha: 0.42),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(12.r),
        child: child,
      ),
    );
  }
}
