import 'package:JsxposedX/features/ai/domain/environments/apk_reverse_tool_definitions.dart';
import 'package:JsxposedX/features/ai/domain/services/ai_chat_tool_catalog.dart';

class ApkReverseChatToolsSpec extends AiChatToolCatalog {
  ApkReverseChatToolsSpec({
    this.includeSoTools = true,
  }) : super(
         definitions: includeSoTools
             ? ApkReverseToolDefinitions.allWithSo
             : ApkReverseToolDefinitions.all,
       );

  final bool includeSoTools;
}
