import 'package:JsxposedX/core/enums/ai_api_type.dart';

abstract class AiChatToolsSpec {
  List<Map<String, dynamic>> buildToolsJson({
    required AiApiType apiType,
  });
}
