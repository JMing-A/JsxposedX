import 'dart:convert';

import 'package:JsxposedX/core/providers/pinia_provider.dart';
import 'package:JsxposedX/features/ai/data/models/ai_config_dto.dart';
import 'package:JsxposedX/features/ai/domain/constants/builtin_ai_config.dart';
import 'package:uuid/uuid.dart';

/// AI 配置查询数据源
class AiConfigQueryDatasource {
  static const _currentConfigStorageKey = "ai_config";

  final PiniaStorage _storage;

  AiConfigQueryDatasource({required PiniaStorage storage}) : _storage = storage;

  Future<AiConfigDto> getBuiltinConfig([String id = builtinAiConfigId]) async {
    final spec = getBuiltinAiConfigSpecById(id) ?? defaultBuiltinAiConfigSpec;
    final builtinApiKey = await _storage.getString(spec.apiKeyStorageKey);
    return _builtinConfigDto(spec, apiKey: builtinApiKey);
  }

  Future<List<AiConfigDto>> getBuiltinConfigs() async {
    final result = <AiConfigDto>[];
    for (final spec in builtinAiConfigSpecs) {
      result.add(await getBuiltinConfig(spec.id));
    }
    return result;
  }

  /// 获取 AI 配置
  Future<AiConfigDto> getConfig() async {
    final configStr = await _storage.getString(_currentConfigStorageKey);
    if (configStr.isNotEmpty) {
      try {
        final config = AiConfigDto.fromJson(jsonDecode(configStr));
        if (isBuiltinAiConfigId(config.id)) {
          final builtinConfig = await getBuiltinConfig(config.id);
          return builtinConfig.copyWith(
            apiKey: builtinConfig.apiKey.isNotEmpty
                ? builtinConfig.apiKey
                : config.apiKey,
          );
        }
        // 如果配置没有 id，生成一个默认的
        if (config.id.isEmpty) {
          final hasCustomContent =
              config.apiUrl.isNotEmpty ||
              config.apiKey.isNotEmpty ||
              config.moduleName.isNotEmpty ||
              config.name.isNotEmpty;
          if (hasCustomContent) {
            return config.copyWith(
              id: const Uuid().v4(),
              name: config.name.isEmpty ? '迁移配置' : config.name,
            );
          }
          return getBuiltinConfig();
        }
        return config;
      } catch (e) {
        return getBuiltinConfig();
      }
    }
    return getBuiltinConfig();
  }

  AiConfigDto _builtinConfigDto(
    BuiltinAiConfigSpec spec, {
    String apiKey = '',
  }) {
    return AiConfigDto(
      id: spec.id,
      name: spec.name,
      apiKey: apiKey,
      apiUrl: spec.apiUrl,
      moduleName: spec.moduleName,
      maxToken: spec.maxToken,
      temperature: spec.temperature,
      memoryRounds: spec.memoryRounds,
      apiType: spec.apiType.name,
    );
  }
}
