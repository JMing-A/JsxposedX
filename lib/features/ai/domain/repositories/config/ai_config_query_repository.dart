import 'package:JsxposedX/core/models/ai_config.dart';

/// AI 配置查询仓储接口
abstract class AiConfigQueryRepository {
  /// 获取当前配置
  Future<AiConfig> getConfig();
}
