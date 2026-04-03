import 'dart:convert';

import 'package:JsxposedX/core/providers/pinia_provider.dart';
import 'package:JsxposedX/feature/ai/data/models/ai_config_dto.dart';
import 'package:JsxposedX/feature/ai/domain/constants/builtin_ai_config.dart';

/// AI 配置操作数据源
class AiConfigActionDatasource {
  static const _currentConfigStorageKey = "ai_config";
  static const _configListStorageKey = "ai_config_list";
  static const _builtinApiKeyStorageKey = "ai_builtin_api_key";

  final PiniaStorage _storage;

  AiConfigActionDatasource({required PiniaStorage storage}) : _storage = storage;

  /// 保存当前 AI 配置
  Future<void> saveConfig(AiConfigDto config) async {
    if (config.id == builtinAiConfigId) {
      await _storage.setString(_builtinApiKeyStorageKey, config.apiKey);
    }
    await _storage.setString(
      _currentConfigStorageKey,
      jsonEncode(config.toJson()),
    );
  }

  /// 获取配置列表
  Future<List<AiConfigDto>> getConfigList() async {
    final configListStr = await _storage.getString(_configListStorageKey);
    if (configListStr.isEmpty) {
      return [];
    }
    try {
      final List<dynamic> jsonList = jsonDecode(configListStr);
      return jsonList
          .map((json) => AiConfigDto.fromJson(json))
          .where((config) => config.id != builtinAiConfigId)
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// 保存配置列表
  Future<void> saveConfigList(List<AiConfigDto> configs) async {
    await _storage.setString(
      _configListStorageKey,
      jsonEncode(configs.map((c) => c.toJson()).toList()),
    );
  }

  /// 添加新配置到列表
  Future<void> addConfig(AiConfigDto config) async {
    final list = await getConfigList();
    list.add(config);
    await saveConfigList(list);
  }

  /// 更新配置列表中的某个配置
  Future<void> updateConfig(AiConfigDto config) async {
    if (config.id == builtinAiConfigId) {
      await saveConfig(config);
      return;
    }
    final list = await getConfigList();
    final index = list.indexWhere((c) => c.id == config.id);
    if (index != -1) {
      list[index] = config;
      await saveConfigList(list);
    }
  }

  /// 删除配置
  Future<void> deleteConfig(String id) async {
    if (id == builtinAiConfigId) {
      return;
    }
    final list = await getConfigList();
    list.removeWhere((c) => c.id == id);
    await saveConfigList(list);
  }

  /// 切换配置（将指定配置设为当前配置）
  Future<void> switchConfig(String id) async {
    if (id == builtinAiConfigId) {
      final builtinApiKey = await _storage.getString(_builtinApiKeyStorageKey);
      await saveConfig(
        AiConfigDto(
          id: builtinAiConfigId,
          name: builtinAiConfigName,
          apiKey: builtinApiKey,
          apiUrl: builtinAiConfigBaseUrl,
          moduleName: 'gpt-5.4',
          maxToken: 4096,
          temperature: 1.0,
          memoryRounds: 6,
          apiType: 'openaiResponses',
        ),
      );
      return;
    }
    final list = await getConfigList();
    final config = list.firstWhere((c) => c.id == id);
    await saveConfig(config);
  }
}
