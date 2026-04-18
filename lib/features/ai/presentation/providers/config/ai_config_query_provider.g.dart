// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_config_query_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(aiConfigQueryRepository)
const aiConfigQueryRepositoryProvider = AiConfigQueryRepositoryProvider._();

final class AiConfigQueryRepositoryProvider
    extends
        $FunctionalProvider<
          AiConfigQueryRepository,
          AiConfigQueryRepository,
          AiConfigQueryRepository
        >
    with $Provider<AiConfigQueryRepository> {
  const AiConfigQueryRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aiConfigQueryRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aiConfigQueryRepositoryHash();

  @$internal
  @override
  $ProviderElement<AiConfigQueryRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AiConfigQueryRepository create(Ref ref) {
    return aiConfigQueryRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AiConfigQueryRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AiConfigQueryRepository>(value),
    );
  }
}

String _$aiConfigQueryRepositoryHash() =>
    r'9f9a2644f60b0b37a2c53b41c57fef64b8ad5f6f';

/// 获取 AI 配置

@ProviderFor(aiConfig)
const aiConfigProvider = AiConfigProvider._();

/// 获取 AI 配置

final class AiConfigProvider
    extends
        $FunctionalProvider<AsyncValue<AiConfig>, AiConfig, FutureOr<AiConfig>>
    with $FutureModifier<AiConfig>, $FutureProvider<AiConfig> {
  /// 获取 AI 配置
  const AiConfigProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aiConfigProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aiConfigHash();

  @$internal
  @override
  $FutureProviderElement<AiConfig> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<AiConfig> create(Ref ref) {
    return aiConfig(ref);
  }
}

String _$aiConfigHash() => r'd995c18765bdcfd24a5d23105fd893ae53468374';

/// 获取 AI 配置列表

@ProviderFor(aiConfigList)
const aiConfigListProvider = AiConfigListProvider._();

/// 获取 AI 配置列表

final class AiConfigListProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<AiConfig>>,
          List<AiConfig>,
          FutureOr<List<AiConfig>>
        >
    with $FutureModifier<List<AiConfig>>, $FutureProvider<List<AiConfig>> {
  /// 获取 AI 配置列表
  const AiConfigListProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aiConfigListProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aiConfigListHash();

  @$internal
  @override
  $FutureProviderElement<List<AiConfig>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<AiConfig>> create(Ref ref) {
    return aiConfigList(ref);
  }
}

String _$aiConfigListHash() => r'53c0732611eceedb4400f8121edd8b58c76bf3bd';
