import 'package:JsxposedX/common/widgets/custom_text_field.dart';
import 'package:JsxposedX/common/widgets/overlay_window/overlay_panel_dialog.dart';
import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/providers/memory_action_provider.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/providers/memory_query_provider.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/utils/memory_tool_search_result_presenter.dart';
import 'package:JsxposedX/generated/memory_tool.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class MemoryToolSearchResultDialog extends HookConsumerWidget {
  const MemoryToolSearchResultDialog({
    super.key,
    required this.result,
    required this.displayValue,
    required this.livePreviewsAsync,
    required this.onClose,
  });

  final SearchResult result;
  final String displayValue;
  final AsyncValue<Map<int, MemoryValuePreview>> livePreviewsAsync;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedType = useState<SearchValueType>(result.type);
    final freezeEnabled = useState<bool>(false);
    final livePreview = livePreviewsAsync.asData?.value[result.address];
    final sourceRawBytes = livePreview?.rawBytes ?? result.rawBytes;
    final sourceType = livePreview?.type ?? result.type;
    final sourceDisplayValue = livePreview?.displayValue ?? displayValue;
    final sourceBytesLength = sourceRawBytes.length;
    final searchSessionStateAsync = ref.watch(getSearchSessionStateProvider);
    final frozenValuesAsync = ref.watch(currentFrozenMemoryValuesProvider);
    final valueActionState = ref.watch(memoryValueActionProvider);
    final valueActionNotifier = ref.read(memoryValueActionProvider.notifier);
    final readRequests = useMemoized(
      () => <MemoryReadRequest>[
        MemoryReadRequest(
          address: result.address,
          type: selectedType.value,
          length: resolveMemoryToolReadLengthForType(
            type: selectedType.value,
            bytesLength: sourceBytesLength,
          ),
        ),
      ],
      <Object>[result.address, selectedType.value, sourceBytesLength],
    );
    final selectedPreviewAsync = ref.watch(
      readMemoryValuesProvider(requests: readRequests),
    );
    final selectedPreviewList = selectedPreviewAsync.asData?.value;
    final selectedPreview = selectedPreviewList == null || selectedPreviewList.isEmpty
        ? null
        : selectedPreviewList.first;
    final selectedDisplayValue =
        selectedType.value == sourceType
            ? sourceDisplayValue
            : selectedPreview?.displayValue ?? '';
    final isFrozen = frozenValuesAsync.asData?.value.any(
          (value) => value.address == result.address,
        ) ??
        false;
    final valueController = useTextEditingController(text: selectedDisplayValue);
    useListenable(valueController);
    useEffect(() {
      freezeEnabled.value = isFrozen;
      return null;
    }, <Object?>[isFrozen]);
    useEffect(() {
      valueController.value = TextEditingValue(
        text: selectedDisplayValue,
        selection: TextSelection.collapsed(offset: selectedDisplayValue.length),
      );
      return null;
    }, <Object?>[selectedType.value, selectedDisplayValue]);
    final selectedTypeLabel = mapMemoryToolSearchResultTypeLabel(
      type: selectedType.value,
      displayValue: selectedDisplayValue,
    );
    final isResolvingAlternateType =
        selectedType.value != sourceType && selectedPreviewAsync.isLoading;
    final canSave =
        valueController.text.trim().isNotEmpty &&
        !valueActionState.isLoading &&
        !isResolvingAlternateType;

    Future<void> handleSave() async {
      try {
        final sessionState = await ref.read(getSearchSessionStateProvider.future);
        final writeValue = buildMemoryToolWriteValue(
          type: selectedType.value,
          input: valueController.text,
          littleEndian: sessionState.littleEndian,
          sourceType: sourceType,
          sourceRawBytes: sourceRawBytes,
          sourceDisplayValue: sourceDisplayValue,
        );

        await valueActionNotifier.writeMemoryValue(
          request: MemoryWriteRequest(
            address: result.address,
            value: writeValue,
          ),
        );
        await valueActionNotifier.setMemoryFreeze(
          request: MemoryFreezeRequest(
            address: result.address,
            value: writeValue,
            enabled: freezeEnabled.value,
          ),
        );

        if (!context.mounted) {
          return;
        }
        onClose();
      } catch (_) {
        return;
      }
    }

    return OverlayPanelDialog.card(
      onClose: onClose,
      maxWidthPortrait: 368.r,
      maxWidthLandscape: 430.r,
      maxHeightPortrait: 360.r,
      maxHeightLandscape: 340.r,
      cardBorderRadius: 18.r,
      childBuilder: (context, viewport, layout) {
        return SingleChildScrollView(
          padding: EdgeInsets.all(14.r),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Text(
                      context.l10n.memoryToolResultDetailTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  SizedBox(width: 10.r),
                  PopupMenuButton<SearchValueType>(
                    onSelected: (value) {
                      selectedType.value = value;
                    },
                    itemBuilder: (context) {
                      return SearchValueType.values
                          .map(
                            (type) => PopupMenuItem<SearchValueType>(
                              value: type,
                              child: Text(
                                mapMemoryToolSearchResultTypeLabel(
                                  type: type,
                                  displayValue: type == SearchValueType.bytes
                                      ? sourceDisplayValue
                                      : '',
                                ),
                              ),
                            ),
                          )
                          .toList(growable: false);
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 10.r,
                        vertical: 8.r,
                      ),
                      decoration: BoxDecoration(
                        color: context.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12.r),
                        border: Border.all(
                          color: context.colorScheme.outlineVariant.withValues(
                            alpha: 0.34,
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            selectedTypeLabel,
                            style: context.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(width: 4.r),
                          Icon(
                            Icons.expand_more_rounded,
                            size: 18.r,
                            color: context.colorScheme.onSurface.withValues(
                              alpha: 0.74,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12.r),
              Text(
                context.l10n.memoryToolResultValue,
                style: context.textTheme.labelMedium?.copyWith(
                  color: context.colorScheme.onSurface.withValues(alpha: 0.62),
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 6.r),
              CustomTextField(
                controller: valueController,
                labelText: context.l10n.memoryToolResultValue,
                hintText: selectedType.value == sourceType
                    ? null
                    : selectedPreviewAsync.isLoading
                    ? '...'
                    : null,
                fillColor: context.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.22,
                ),
                focusedBorderColor: context.colorScheme.primary,
                enabledBorderColor: context.colorScheme.outlineVariant.withValues(
                  alpha: 0.34,
                ),
              ),
              SizedBox(height: 12.r),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: context.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.42,
                  ),
                  borderRadius: BorderRadius.circular(14.r),
                  border: Border.all(
                    color: context.colorScheme.outlineVariant.withValues(
                      alpha: 0.34,
                    ),
                  ),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12.r, vertical: 6.r),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          context.l10n.memoryToolResultActionFreeze,
                          style: context.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Switch.adaptive(
                        value: freezeEnabled.value,
                        onChanged: valueActionState.isLoading
                            ? null
                            : (value) {
                                freezeEnabled.value = value;
                              },
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 12.r),
              _MemoryToolSearchResultLine(
                label: context.l10n.memoryToolResultType,
                value: selectedTypeLabel,
              ),
              SizedBox(height: 8.r),
              _MemoryToolSearchResultLine(
                label: context.l10n.memoryToolResultAddress,
                value: formatMemoryToolSearchResultAddress(result.address),
              ),
              SizedBox(height: 8.r),
              _MemoryToolSearchResultLine(
                label: context.l10n.memoryToolResultRegion,
                value: mapMemoryToolSearchResultRegionTypeLabel(
                  context,
                  result.regionTypeKey,
                ),
              ),
              if (searchSessionStateAsync.hasError || frozenValuesAsync.hasError || valueActionState.hasError) ...<Widget>[
                SizedBox(height: 10.r),
                Text(
                  valueActionState.error?.toString() ??
                      frozenValuesAsync.error?.toString() ??
                      searchSessionStateAsync.error?.toString() ??
                      '',
                  style: context.textTheme.bodySmall?.copyWith(
                    color: context.colorScheme.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              SizedBox(height: 14.r),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onClose,
                      child: Text(context.l10n.close),
                    ),
                  ),
                  SizedBox(width: 10.r),
                  Expanded(
                    child: FilledButton(
                      onPressed: canSave ? handleSave : null,
                      child: Text(context.l10n.save),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MemoryToolSearchResultLine extends StatelessWidget {
  const _MemoryToolSearchResultLine({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 58.r,
          child: Text(
            label,
            style: context.textTheme.bodySmall?.copyWith(
              color: context.colorScheme.onSurface.withValues(alpha: 0.62),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        SizedBox(width: 8.r),
        Expanded(
          child: Text(
            value,
            style: context.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
