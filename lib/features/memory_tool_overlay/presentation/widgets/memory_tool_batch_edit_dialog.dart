import 'package:JsxposedX/common/widgets/custom_text_field.dart';
import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/providers/memory_action_provider.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/providers/memory_query_provider.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/utils/memory_tool_search_result_presenter.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/widgets/memory_tool_value_editor_dialog.dart';
import 'package:JsxposedX/generated/memory_tool.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class MemoryToolBatchEditDialog extends HookConsumerWidget {
  const MemoryToolBatchEditDialog({
    super.key,
    required this.results,
    required this.livePreviewsAsync,
    this.onSaved,
    required this.onClose,
  });

  final List<SearchResult> results;
  final AsyncValue<Map<int, MemoryValuePreview>> livePreviewsAsync;
  final Future<void> Function(
    List<SearchResult> results,
    Map<int, MemoryValuePreview> updatedPreviews,
    bool isFrozen,
  )?
  onSaved;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedType = useState<SearchValueType>(
      results.isEmpty ? SearchValueType.i32 : results.first.type,
    );
    final freezeEnabled = useState<bool>(false);
    final incrementEnabled = useState<bool>(false);
    final valueController = useTextEditingController();
    final incrementController = useTextEditingController(text: '1');
    final valueActionState = ref.watch(memoryValueActionProvider);
    useListenable(valueController);
    useListenable(incrementController);

    final supportsIncrement = isMemoryToolNumericValueType(selectedType.value);
    final previewSamples = <String>[];
    String? localErrorText;
    if (incrementEnabled.value) {
      if (!supportsIncrement) {
        localErrorText = '增量模式仅支持数值类型';
      } else {
        try {
          final sampleCount = results.length < 4 ? results.length : 4;
          for (int index = 0; index < sampleCount; index++) {
            previewSamples.add(
              resolveMemoryToolIncrementedInput(
                type: selectedType.value,
                baseInput: valueController.text,
                incrementInput: incrementController.text,
                index: index,
              ),
            );
          }
        } on FormatException catch (error) {
          localErrorText = error.message;
        } catch (error) {
          localErrorText = error.toString();
        }
      }
    }

    Future<void> handleSave() async {
      if (localErrorText != null) {
        throw FormatException(localErrorText);
      }
      final sessionState = await ref.read(getSearchSessionStateProvider.future);
      final previewRequests = results
          .map((result) {
            final fallbackPreview =
                livePreviewsAsync.asData?.value[result.address];
            final bytesLength =
                fallbackPreview?.rawBytes.length ?? result.rawBytes.length;
            return MemoryReadRequest(
              address: result.address,
              type: selectedType.value,
              length: resolveMemoryToolReadLengthForType(
                type: selectedType.value,
                bytesLength: bytesLength,
              ),
            );
          })
          .toList(growable: false);
      final currentPreviews = await ref
          .read(memoryQueryRepositoryProvider)
          .readMemoryValues(requests: previewRequests);
      final currentPreviewByAddress = <int, MemoryValuePreview>{
        for (final preview in currentPreviews) preview.address: preview,
      };

      final requests = <MemoryWriteRequest>[];
      final freezeRequests = <MemoryFreezeRequest>[];
      final previousPreviews = <MemoryValuePreview>[];
      final processedResults = <SearchResult>[];
      for (final result in results) {
        final currentPreview = currentPreviewByAddress[result.address];
        if (currentPreview == null) {
          continue;
        }

        processedResults.add(result);
        previousPreviews.add(currentPreview);
        final targetIndex = requests.length;
        final writeValue = incrementEnabled.value
            ? buildMemoryToolIncrementalWriteValue(
                type: selectedType.value,
                baseInput: valueController.text,
                incrementInput: incrementController.text,
                index: targetIndex,
                littleEndian: sessionState.littleEndian,
                sourceType: currentPreview.type,
                sourceRawBytes: currentPreview.rawBytes,
                sourceDisplayValue: currentPreview.displayValue,
              )
            : buildMemoryToolWriteValue(
                type: selectedType.value,
                input: valueController.text,
                littleEndian: sessionState.littleEndian,
                sourceType: currentPreview.type,
                sourceRawBytes: currentPreview.rawBytes,
                sourceDisplayValue: currentPreview.displayValue,
              );
        requests.add(
          MemoryWriteRequest(address: result.address, value: writeValue),
        );
        if (freezeEnabled.value) {
          freezeRequests.add(
            MemoryFreezeRequest(
              address: result.address,
              value: writeValue,
              enabled: true,
            ),
          );
        }
      }

      if (requests.isEmpty) {
        throw StateError('No readable selected results.');
      }

      await ref
          .read(memoryValueActionProvider.notifier)
          .writeMemoryValues(
            requests: requests,
            previousPreviews: previousPreviews,
          );
      if (freezeRequests.isNotEmpty) {
        await ref
            .read(memoryValueActionProvider.notifier)
            .setMemoryFreezes(requests: freezeRequests);
      }
      if (onSaved != null) {
        final updatedPreviews = await ref
            .read(memoryQueryRepositoryProvider)
            .readMemoryValues(requests: previewRequests);
        await onSaved!(
          processedResults,
          <int, MemoryValuePreview>{
            for (final preview in updatedPreviews) preview.address: preview,
          },
          freezeEnabled.value,
        );
      }

      if (!context.mounted) {
        return;
      }
      onClose();
    }

    final canSave =
        results.isNotEmpty &&
        valueController.text.trim().isNotEmpty &&
        (!incrementEnabled.value ||
            incrementController.text.trim().isNotEmpty) &&
        localErrorText == null &&
        !valueActionState.isLoading;
    final selectedTypeLabel = mapMemoryToolSearchResultTypeLabel(
      type: selectedType.value,
      displayValue: valueController.text,
    );
    final incrementInputType =
        selectedType.value == SearchValueType.f32 ||
            selectedType.value == SearchValueType.f64
        ? const TextInputType.numberWithOptions(decimal: true, signed: true)
        : const TextInputType.numberWithOptions(signed: true);

    return MemoryToolValueEditorDialog(
      title: context.l10n.memoryToolResultActionBatchEdit,
      subtitle:
          '${context.l10n.memoryToolSessionSelectedCount}: ${results.length}',
      selectedTypeLabel: selectedTypeLabel,
      typeLabelBuilder: (type) {
        return mapMemoryToolSearchResultTypeLabel(
          type: type,
          displayValue: type == SearchValueType.bytes
              ? valueController.text
              : '',
        );
      },
      onSelectedType: (value) {
        selectedType.value = value;
        if (!isMemoryToolNumericValueType(value)) {
          incrementEnabled.value = false;
        }
      },
      valueController: valueController,
      valueHintText: context.l10n.memoryToolFieldValuePlaceholder,
      extraContent: supportsIncrement
          ? DecoratedBox(
              decoration: BoxDecoration(
                color: context.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.42,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: context.colorScheme.outlineVariant.withValues(
                    alpha: 0.34,
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Text(
                          '递增',
                          style: context.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Switch.adaptive(
                          value: incrementEnabled.value,
                          onChanged: valueActionState.isLoading
                              ? null
                              : (value) {
                                  incrementEnabled.value = value;
                                },
                        ),
                      ],
                    ),
                    if (incrementEnabled.value) ...<Widget>[
                      const SizedBox(height: 6),
                      Text(
                        '步长',
                        style: context.textTheme.labelMedium?.copyWith(
                          color: context.colorScheme.onSurface.withValues(
                            alpha: 0.62,
                          ),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      CustomTextField(
                        controller: incrementController,
                        labelText: '步长',
                        hintText: '1',
                        keyboardType: incrementInputType,
                        inputFormatters: <TextInputFormatter>[
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[-0-9.]'),
                          ),
                        ],
                        fillColor: context.colorScheme.surface.withValues(
                          alpha: 0.4,
                        ),
                        focusedBorderColor: context.colorScheme.primary,
                        enabledBorderColor: context.colorScheme.outlineVariant
                            .withValues(alpha: 0.34),
                      ),
                      if (previewSamples.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 10),
                        Text(
                          '预览 ${previewSamples.join(', ')}${results.length > previewSamples.length ? '...' : ''}',
                          style: context.textTheme.bodySmall?.copyWith(
                            color: context.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            )
          : null,
      isFreezeEnabled: freezeEnabled.value,
      onFreezeChanged: valueActionState.isLoading
          ? null
          : (value) {
              freezeEnabled.value = value;
            },
      errorText: localErrorText ?? valueActionState.error?.toString(),
      canSave: canSave,
      onSave: handleSave,
      onClose: onClose,
      maxWidthPortrait: 372,
      maxWidthLandscape: 430,
      maxHeightPortrait: 320,
      maxHeightLandscape: 300,
    );
  }
}
