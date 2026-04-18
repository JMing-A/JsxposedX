import 'package:JsxposedX/common/pages/toast.dart';
import 'package:JsxposedX/common/widgets/app_bottom_sheet.dart';
import 'package:JsxposedX/common/widgets/custom_text_field.dart';
import 'package:JsxposedX/common/widgets/loading.dart';
import 'package:JsxposedX/common/widgets/ref_error.dart';
import 'package:JsxposedX/core/enums/ai_api_type.dart';
import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/core/models/ai_config.dart';
import 'package:JsxposedX/core/utils/url_helper.dart';
import 'package:JsxposedX/features/ai/domain/constants/builtin_ai_config.dart';
import 'package:JsxposedX/features/ai/presentation/providers/chat/ai_chat_action_provider.dart';
import 'package:JsxposedX/features/ai/presentation/providers/config/ai_config_action_provider.dart';
import 'package:JsxposedX/features/ai/presentation/providers/config/ai_config_query_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:uuid/uuid.dart';

/// AI 配置表单 Key 提供者，用于跨组件访问表单状态
final _sheetFormKeyProvider = Provider((ref) => GlobalKey<FormBuilderState>());

/// AI 配置弹窗内容组件
class AIConfigSheet extends HookConsumerWidget {
  const AIConfigSheet({super.key});

  /// 显示 AI 配置弹窗
  static void show(BuildContext context) {
    AppBottomSheet.show(
      context: context,
      title: context.l10n.aiConfigTitle,
      action: [
        Consumer(
          builder: (context, ref, child) {
            return Row(
              children: [
                TextButton(
                  onPressed: () => UrlHelper.openUrlInBrowser(
                    url:
                        "https://www.yuque.com/ababa-haoqq/hake3e/npt913l7r1goxsoi?singleDoc",
                  ),
                  child: Text(context.l10n.aiTutorial),
                ),
                TextButton(
                  onPressed: () => _handleTest(context, ref),
                  child: Text(context.l10n.test),
                ),
              ],
            );
          },
        ),
      ],
      child: const AIConfigSheet(),
    );
  }

  /// 从表单值构建 AiConfig 对象
  static AiConfig _buildConfigFromFormValues(
    Map<String, dynamic> values,
    String id,
  ) {
    return AiConfig(
      id: id,
      name: values["name"] ?? "",
      apiUrl: values["api"] ?? "",
      apiKey: values["api_key"] ?? "",
      moduleName: values["module_name"] ?? "",
      maxToken: int.tryParse(values["max_token"]?.toString() ?? "") ?? 2048,
      temperature: (values["temperature"] as num?)?.toDouble() ?? 0.7,
      memoryRounds: (values["memory_rounds"] as num?)?.toDouble() ?? 5.0,
      apiType: AiApiType.fromString(values["api_type"]?.toString() ?? "openai"),
    );
  }

  static String _apiTypeLabel(BuildContext context, AiApiType type) {
    switch (type) {
      case AiApiType.openai:
        return context.l10n.aiApiTypeOpenAI;
      case AiApiType.openaiResponses:
        return context.l10n.aiApiTypeOpenAIResponses;
      case AiApiType.anthropic:
        return context.l10n.aiApiTypeAnthropic;
    }
  }

  static AiConfig _emptyFormConfig() {
    return const AiConfig(
      id: '',
      name: '',
      apiUrl: '',
      apiKey: '',
      moduleName: '',
      maxToken: 300,
      temperature: 0.7,
      memoryRounds: 5.0,
      apiType: AiApiType.openai,
    );
  }

  static Map<String, dynamic> _formValuesFromConfig(AiConfig config) {
    return {
      'name': config.name,
      'api': config.apiUrl,
      'api_key': config.apiKey,
      'module_name': config.moduleName,
      'max_token': config.maxToken.toString(),
      'temperature': config.temperature,
      'memory_rounds': config.memoryRounds,
      'api_type': config.apiType.name,
    };
  }

  static BuiltinAiConfigSpec? _builtinSpecOf(AiConfig config) {
    return getBuiltinAiConfigSpecById(config.id);
  }

  /// 处理测试连接逻辑
  static Future<void> _handleTest(BuildContext context, WidgetRef ref) async {
    final formKey = ref.read(_sheetFormKeyProvider);
    if (formKey.currentState?.saveAndValidate() ?? false) {
      final values = formKey.currentState!.value;
      final config = _buildConfigFromFormValues(values, const Uuid().v4());

      ToastMessage.show(context.l10n.aiTestConnecting);
      try {
        final result = await ref
            .read(aiChatActionProvider(packageName: 'temp').notifier)
            .testConnection(config);
        if (context.mounted) {
          ToastMessage.show(context.l10n.aiTestSuccess(result));
        }
      } catch (e) {
        if (context.mounted) {
          ToastMessage.show(context.l10n.aiTestFailed(e.toString()));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final formKey = ref.watch(_sheetFormKeyProvider);
    final aiConfigAsync = ref.watch(aiConfigProvider);
    final configListAsync = ref.watch(aiConfigListProvider);

    // editingConfig: null = 新建模式, non-null = 编辑某个已有配置
    // 用 useState 管理，避免引入额外的全局 provider
    final editingConfig = useState<AiConfig?>(null);
    final isNewMode = useState<bool>(false);
    final builtinApiKeyController = useTextEditingController();
    final lastLoadedBuiltinApiKey = useRef<String?>(null);
    final currentConfig = aiConfigAsync.value;

    // 统一同步内置配置输入框，避免在多个位置重复写 controller
    useEffect(() {
      final selectedConfig = isNewMode.value
          ? null
          : (editingConfig.value ?? currentConfig);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (selectedConfig != null && isBuiltinAiConfig(selectedConfig)) {
          if (lastLoadedBuiltinApiKey.value != selectedConfig.apiKey) {
            builtinApiKeyController.text = selectedConfig.apiKey;
            lastLoadedBuiltinApiKey.value = selectedConfig.apiKey;
          }
          return;
        }

        if (lastLoadedBuiltinApiKey.value != null ||
            builtinApiKeyController.text.isNotEmpty) {
          builtinApiKeyController.clear();
          lastLoadedBuiltinApiKey.value = null;
        }
      });
      return null;
    }, [isNewMode.value, editingConfig.value, currentConfig]);

    ref.listen(aiConfigActionProvider, (previous, next) {
      next.whenOrNull(
        error: (error, stack) => ToastMessage.show(error.toString()),
        data: (_) {
          if (previous?.isLoading ?? false) {
            if (context.mounted) {
              ToastMessage.show(context.l10n.saveSuccess);
            }
          }
        },
      );
    });

    return aiConfigAsync.when(
      loading: () => SizedBox(height: 200.h, child: const Loading()),
      error: (error, stack) => SingleChildScrollView(
        child: Container(
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(vertical: 40.h),
          child: RefError(
            error: error,
            onRetry: () => ref.invalidate(aiConfigProvider),
          ),
        ),
      ),
      data: (currentConfig) {
        return configListAsync.when(
          loading: () => SizedBox(height: 200.h, child: const Loading()),
          error: (error, stack) => SingleChildScrollView(
            child: Container(
              alignment: Alignment.center,
              padding: EdgeInsets.symmetric(vertical: 40.h),
              child: RefError(
                error: error,
                onRetry: () => ref.invalidate(aiConfigListProvider),
              ),
            ),
          ),
          data: (configList) {
            // 确定表单展示的配置：新建模式用空白，编辑模式用选中的，默认用当前配置
            final formConfig = isNewMode.value
                ? _emptyFormConfig()
                : (editingConfig.value ?? currentConfig);

            final initialValue = _formValuesFromConfig(formConfig);
            final isBuiltinEditing = isBuiltinAiConfig(formConfig);
            final builtinSpec = _builtinSpecOf(formConfig);

            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 配置列表头部
                  Row(
                    children: [
                      Text(
                        context.l10n.aiConfigList,
                        style: TextStyle(
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w600,
                          color: context.theme.hintColor,
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        icon: Icon(Icons.add, size: 16.sp),
                        label: Text(
                          context.l10n.aiConfigNew,
                          style: TextStyle(fontSize: 13.sp),
                        ),
                        onPressed: () {
                          isNewMode.value = true;
                          editingConfig.value = null;
                        },
                      ),
                    ],
                  ),
                  SizedBox(height: 4.h),

                  // 配置列表
                  if (configList.isNotEmpty)
                    Container(
                      decoration: BoxDecoration(
                        color: context.isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.grey[100],
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                      child: Column(
                        children: configList.asMap().entries.map((entry) {
                          final index = entry.key;
                          final config = entry.value;
                          final isCurrent = currentConfig.id == config.id;
                          final isBuiltin = isBuiltinAiConfig(config);
                          final isEditing =
                              !isNewMode.value &&
                              (editingConfig.value?.id == config.id ||
                                  (editingConfig.value == null && isCurrent));

                          return _ConfigListItem(
                            config: config,
                            builtinSpec: _builtinSpecOf(config),
                            isBuiltin: isBuiltin,
                            isCurrent: isCurrent,
                            isEditing: isEditing,
                            isFirst: index == 0,
                            onTap: () async {
                              try {
                                var selectedConfig = config;
                                if (!isCurrent) {
                                  await ref
                                      .read(aiConfigActionProvider.notifier)
                                      .switchConfig(config.id);
                                  ref.invalidate(aiStatusProvider);
                                  selectedConfig = await ref.read(
                                    aiConfigProvider.future,
                                  );
                                }

                                // 直接更新状态
                                editingConfig.value = selectedConfig;
                                isNewMode.value = false;
                              } catch (e) {
                                if (context.mounted) {
                                  ToastMessage.show(
                                    '${context.l10n.error}: ${e.toString()}',
                                  );
                                }
                              }
                            },
                            onDelete: isBuiltin
                                ? null
                                : () async {
                                    final confirmed = await showDialog<bool>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: Text(context.l10n.confirmDelete),
                                        content: Text(
                                          context.l10n.aiConfigDeleteConfirm(
                                            config.name,
                                          ),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.of(
                                              context,
                                            ).pop(false),
                                            child: Text(context.l10n.cancel),
                                          ),
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.of(context).pop(true),
                                            child: Text(
                                              context.l10n.delete,
                                              style: const TextStyle(
                                                color: Colors.red,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );

                                    if (confirmed == true) {
                                      try {
                                        await ref
                                            .read(
                                              aiConfigActionProvider.notifier,
                                            )
                                            .deleteConfig(config.id);
                                        if (editingConfig.value?.id ==
                                            config.id) {
                                          editingConfig.value = null;
                                          isNewMode.value = false;
                                        }
                                      } catch (e) {
                                        if (context.mounted) {
                                          ToastMessage.show(
                                            '${context.l10n.error}: ${e.toString()}',
                                          );
                                        }
                                      }
                                    }
                                  },
                          );
                        }).toList(),
                      ),
                    )
                  else
                    Container(
                      alignment: Alignment.center,
                      padding: EdgeInsets.symmetric(vertical: 12.h),
                      child: Text(
                        context.l10n.aiConfigEmpty,
                        style: TextStyle(
                          fontSize: 13.sp,
                          color: context.theme.hintColor,
                        ),
                      ),
                    ),

                  SizedBox(height: 20.h),

                  // 分隔线 + 编辑/新建标题
                  Row(
                    children: [
                      Text(
                        isNewMode.value
                            ? context.l10n.aiConfigNewTitle
                            : context.l10n.aiConfigEditTitle,
                        style: TextStyle(
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w600,
                          color: context.theme.hintColor,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8.h),

                  // 表单
                  if (isBuiltinEditing)
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(14.w),
                      decoration: BoxDecoration(
                        color: context.colorScheme.primary.withValues(
                          alpha: 0.08,
                        ),
                        borderRadius: BorderRadius.circular(12.r),
                        border: Border.all(
                          color: context.colorScheme.primary.withValues(
                            alpha: 0.2,
                          ),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            builtinSpec?.name ??
                                context.l10n.aiBuiltinConfigName,
                            style: TextStyle(
                              fontSize: 14.sp,
                              fontWeight: FontWeight.w600,
                              color: context.colorScheme.primary,
                            ),
                          ),
                          SizedBox(height: 8.h),
                          Text(
                            context.l10n.aiCurrentStatus(
                              formConfig.apiKey.trim().isNotEmpty
                                  ? context.l10n.aiApiKeyConfigured
                                  : context.l10n.aiApiKeyNotConfigured,
                            ),
                            style: TextStyle(
                              fontSize: 12.sp,
                              color: formConfig.apiKey.trim().isNotEmpty
                                  ? Colors.green
                                  : Colors.orange,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: 8.h),
                          CustomTextField(
                            controller: builtinApiKeyController,
                            labelText: 'API Key',
                            hintText: context.l10n.aiApiKeyHint,
                            keyboardType: TextInputType.visiblePassword,
                          ),
                          if (builtinSpec?.purchaseUrl
                              case final purchaseUrl?) ...[
                            SizedBox(height: 8.h),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: () => UrlHelper.openUrlInBrowser(
                                  url: purchaseUrl,
                                ),
                                icon: const Icon(Icons.shopping_cart_outlined),
                                label: Text(context.l10n.aiBuyCardSecret),
                              ),
                            ),
                          ],
                        ],
                      ),
                    )
                  else
                    KeyedSubtree(
                      key: ValueKey(
                        [
                          formConfig.id,
                          formConfig.name,
                          formConfig.apiUrl,
                          formConfig.apiKey,
                          formConfig.moduleName,
                          formConfig.maxToken,
                          formConfig.temperature,
                          formConfig.memoryRounds,
                          formConfig.apiType.name,
                        ].join('|'),
                      ),
                      child: FormBuilder(
                        key: formKey,
                        initialValue: initialValue,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CustomTextField.formBuilder(
                              name: 'name',
                              labelText: context.l10n.aiConfigName,
                              hintText: context.l10n.aiConfigNameHint,
                              validator: FormBuilderValidators.compose([
                                FormBuilderValidators.required(
                                  errorText: context.l10n.cannotBeEmpty(
                                    context.l10n.aiConfigName,
                                  ),
                                ),
                              ]),
                            ),
                            SizedBox(height: 12.h),
                            CustomTextField.formBuilder(
                              name: 'api',
                              labelText: context.l10n.aiBaseUrl,
                              hintText: context.l10n.aiBaseUrlHint,
                              keyboardType: TextInputType.url,
                              validator: FormBuilderValidators.compose([
                                FormBuilderValidators.required(
                                  errorText: context.l10n.cannotBeEmpty(
                                    context.l10n.aiBaseUrl,
                                  ),
                                ),
                                FormBuilderValidators.url(
                                  errorText: context.l10n.loadFailedMessage,
                                ),
                              ]),
                            ),
                            SizedBox(height: 12.h),
                            Text(
                              context.l10n.aiApiType,
                              style: TextStyle(
                                fontSize: 13.sp,
                                color: context.theme.hintColor,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            SizedBox(height: 8.h),
                            FormBuilderDropdown<String>(
                              name: 'api_type',
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12.r),
                                ),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12.w,
                                  vertical: 12.h,
                                ),
                              ),
                              initialValue: formConfig.apiType.name,
                              items: AiApiType.values.map((type) {
                                return DropdownMenuItem(
                                  value: type.name,
                                  child: Text(_apiTypeLabel(context, type)),
                                );
                              }).toList(),
                            ),
                            SizedBox(height: 12.h),
                            CustomTextField.formBuilder(
                              name: 'api_key',
                              labelText: 'API Key',
                              hintText: context.l10n.aiApiKeyHint,
                              keyboardType: TextInputType.visiblePassword,
                              validator: FormBuilderValidators.compose([
                                FormBuilderValidators.required(
                                  errorText: context.l10n.cannotBeEmpty(
                                    'API Key',
                                  ),
                                ),
                              ]),
                            ),
                            SizedBox(height: 12.h),
                            Row(
                              children: [
                                Expanded(
                                  child: CustomTextField.formBuilder(
                                    name: 'module_name',
                                    labelText: context.l10n.aiModelName,
                                    hintText: context.l10n.aiModelNameHint,
                                    validator: FormBuilderValidators.compose([
                                      FormBuilderValidators.required(
                                        errorText: context.l10n.cannotBeEmpty(
                                          context.l10n.aiModelName,
                                        ),
                                      ),
                                    ]),
                                  ),
                                ),
                                SizedBox(width: 12.w),
                                Expanded(
                                  child: CustomTextField.formBuilder(
                                    name: 'max_token',
                                    labelText: context.l10n.aiMaxTokens,
                                    hintText: context.l10n.aiMaxTokensHint,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                    ],
                                    validator: FormBuilderValidators.compose([
                                      FormBuilderValidators.required(
                                        errorText: context.l10n.cannotBeEmpty(
                                          context.l10n.aiMaxTokens,
                                        ),
                                      ),
                                    ]),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 20.h),
                            Text(
                              context.l10n.aiTemperature,
                              style: TextStyle(
                                fontSize: 13.sp,
                                color: context.theme.hintColor,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            FormBuilderSlider(
                              name: 'temperature',
                              min: 0.0,
                              max: 2.0,
                              initialValue: formConfig.temperature,
                              divisions: 20,
                              activeColor: context.colorScheme.primary,
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                            Text(
                              context.l10n.aiMemoryRounds,
                              style: TextStyle(
                                fontSize: 13.sp,
                                color: context.theme.hintColor,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            FormBuilderSlider(
                              name: 'memory_rounds',
                              min: 0.0,
                              max: 20.0,
                              initialValue: formConfig.memoryRounds,
                              divisions: 20,
                              activeColor: context.colorScheme.primary,
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  SizedBox(height: 24.h),
                  SizedBox(
                    width: double.infinity,
                    height: 52.h,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: context.colorScheme.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                      ),
                      onPressed: ref.watch(aiConfigActionProvider).isLoading
                          ? null
                          : () async {
                              if (isBuiltinEditing) {
                                final apiKey = builtinApiKeyController.text
                                    .trim();
                                if (apiKey.isEmpty) {
                                  ToastMessage.show(
                                    context.l10n.cannotBeEmpty('API Key'),
                                  );
                                  return;
                                }
                                final builtinConfig =
                                    builtinSpec?.toConfig(apiKey: apiKey) ??
                                    formConfig.copyWith(apiKey: apiKey);
                                ToastMessage.show(
                                  context.l10n.aiBuiltinSwitching,
                                );
                                try {
                                  await ref
                                      .read(
                                        aiChatActionProvider(
                                          packageName: 'temp',
                                        ).notifier,
                                      )
                                      .testConnection(builtinConfig);
                                  await ref
                                      .read(aiConfigActionProvider.notifier)
                                      .save(builtinConfig);
                                  ref.invalidate(aiStatusProvider);
                                  isNewMode.value = false;
                                  editingConfig.value = null;
                                } catch (e) {
                                  if (context.mounted) {
                                    ToastMessage.show(
                                      context.l10n.aiSaveFailed(e.toString()),
                                    );
                                  }
                                }
                                return;
                              }
                              if (formKey.currentState?.saveAndValidate() ??
                                  false) {
                                final values = formKey.currentState!.value;
                                final savedId = isNewMode.value
                                    ? const Uuid().v4()
                                    : (editingConfig.value?.id.isNotEmpty ==
                                              true
                                          ? editingConfig.value!.id
                                          : currentConfig.id);
                                final config = _buildConfigFromFormValues(
                                  values,
                                  savedId,
                                );

                                ToastMessage.show(
                                  context.l10n.aiSavingAndTesting,
                                );
                                try {
                                  await ref
                                      .read(
                                        aiChatActionProvider(
                                          packageName: 'temp',
                                        ).notifier,
                                      )
                                      .testConnection(config);

                                  final existsInList = configList.any(
                                    (item) => item.id == config.id,
                                  );
                                  if (isNewMode.value || !existsInList) {
                                    await ref
                                        .read(aiConfigActionProvider.notifier)
                                        .addConfig(config);
                                  } else {
                                    await ref
                                        .read(aiConfigActionProvider.notifier)
                                        .updateConfig(config);
                                  }

                                  await ref
                                      .read(aiConfigActionProvider.notifier)
                                      .save(config);

                                  ref.invalidate(aiStatusProvider);
                                  isNewMode.value = false;
                                  editingConfig.value = null;
                                } catch (e) {
                                  if (context.mounted) {
                                    ToastMessage.show(
                                      context.l10n.aiSaveFailed(e.toString()),
                                    );
                                  }
                                }
                              }
                            },
                      child: ref.watch(aiConfigActionProvider).isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              isBuiltinEditing
                                  ? context.l10n.aiBuiltinUseConfig
                                  : context.l10n.confirm,
                              style: TextStyle(
                                fontSize: 16.sp,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// 配置列表项组件
class _ConfigListItem extends ConsumerWidget {
  const _ConfigListItem({
    required this.config,
    required this.builtinSpec,
    required this.isBuiltin,
    required this.isCurrent,
    required this.isEditing,
    required this.isFirst,
    required this.onTap,
    this.onDelete,
  });

  final AiConfig config;
  final BuiltinAiConfigSpec? builtinSpec;
  final bool isBuiltin;
  final bool isCurrent;
  final bool isEditing;
  final bool isFirst;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: isEditing
            ? context.colorScheme.primary.withValues(alpha: 0.08)
            : null,
        border: !isFirst
            ? Border(
                top: BorderSide(
                  color: context.isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.grey[300]!,
                  width: 0.5,
                ),
              )
            : null,
      ),
      child: Row(
        children: [
          // 左侧：单选按钮
          IconButton(
            icon: Icon(
              isCurrent
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 22.sp,
              color: context.colorScheme.primary,
            ),
            tooltip: isCurrent
                ? context.l10n.aiConfigCurrent
                : context.l10n.aiConfigSwitch,
            onPressed: onTap, // 这里的按钮点击也走总的 onTap，确保效果一致
          ),
          // 中间：配置信息（可点击编辑）
          Expanded(
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(8.r),
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 4.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          config.name,
                          style: TextStyle(
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (isCurrent) ...[
                          SizedBox(width: 6.w),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 6.w,
                              vertical: 2.h,
                            ),
                            decoration: BoxDecoration(
                              color: context.colorScheme.primary,
                              borderRadius: BorderRadius.circular(4.r),
                            ),
                            child: Text(
                              context.l10n.aiConfigCurrent,
                              style: TextStyle(
                                fontSize: 10.sp,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                        if (isBuiltin)
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  for (
                                    var index = 0;
                                    index <
                                        (builtinSpec?.badgeLabels.length ?? 0);
                                    index++
                                  ) ...[
                                    SizedBox(width: 6.w),
                                    Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 6.w,
                                        vertical: 2.h,
                                      ),
                                      decoration: BoxDecoration(
                                        color: index == 0
                                            ? Colors.redAccent
                                            : Colors.blue,
                                        borderRadius: BorderRadius.circular(
                                          4.r,
                                        ),
                                      ),
                                      child: Text(
                                        builtinSpec!.badgeLabels[index],
                                        style: TextStyle(
                                          fontSize: 10.sp,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      isBuiltin
                          ? [
                              if ((builtinSpec?.statusLabel ?? '').isNotEmpty)
                                builtinSpec!.statusLabel,
                              config.apiKey.trim().isNotEmpty
                                  ? context.l10n.aiApiKeyConfigured
                                  : context.l10n.aiApiKeyNotConfigured,
                            ].join(' · ')
                          : config.moduleName,
                      style: TextStyle(
                        fontSize: 11.sp,
                        color: context.theme.hintColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 右侧：删除按钮
          if (onDelete != null)
            IconButton(
              icon: Icon(Icons.delete_outline, size: 20.sp, color: Colors.red),
              tooltip: context.l10n.aiConfigDelete,
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }
}
