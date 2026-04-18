import 'package:JsxposedX/core/models/ai_config.dart';
import 'package:JsxposedX/core/providers/pinia_provider.dart';
import 'package:JsxposedX/features/ai/data/datasources/config/ai_config_action_datasource.dart';
import 'package:JsxposedX/features/ai/data/repositories/config/ai_config_action_repository_impl.dart' as impl;
import 'package:JsxposedX/features/ai/domain/repositories/config/ai_config_action_repository.dart';
import 'package:JsxposedX/features/ai/presentation/providers/config/ai_config_query_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'ai_config_action_provider.g.dart';

@riverpod
AiConfigActionRepository aiConfigActionRepository(Ref ref) {
  final storage = ref.watch(piniaStorageLocalProvider);
  final dataSource = AiConfigActionDatasource(storage: storage);
  return impl.AiConfigActionRepositoryImpl(dataSource: dataSource);
}

/// 保存 AI 配置 Action Provider
@riverpod
class AiConfigAction extends _$AiConfigAction {
  @override
  AsyncValue<void> build() => const AsyncValue.data(null);

  Future<void> save(AiConfig config) async {
    state = const AsyncValue.loading();
    try {
      await ref.read(aiConfigActionRepositoryProvider).saveConfig(config);
      state = const AsyncValue.data(null);
      // 刷新查询 provider
      ref.invalidate(aiConfigProvider);
      ref.invalidate(aiConfigListProvider);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> addConfig(AiConfig config) async {
    state = const AsyncValue.loading();
    try {
      await ref.read(aiConfigActionRepositoryProvider).addConfig(config);
      state = const AsyncValue.data(null);
      ref.invalidate(aiConfigListProvider);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> updateConfig(AiConfig config) async {
    state = const AsyncValue.loading();
    try {
      await ref.read(aiConfigActionRepositoryProvider).updateConfig(config);
      state = const AsyncValue.data(null);
      ref.invalidate(aiConfigListProvider);
      // 如果更新的是当前配置，也刷新当前配置
      ref.invalidate(aiConfigProvider);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> deleteConfig(String id) async {
    state = const AsyncValue.loading();
    try {
      await ref.read(aiConfigActionRepositoryProvider).deleteConfig(id);
      state = const AsyncValue.data(null);
      ref.invalidate(aiConfigListProvider);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> switchConfig(String id) async {
    state = const AsyncValue.loading();
    try {
      await ref.read(aiConfigActionRepositoryProvider).switchConfig(id);
      state = const AsyncValue.data(null);
      // 刷新当前配置
      ref.invalidate(aiConfigProvider);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

