import 'package:JsxposedX/core/enums/ai_api_type.dart';
import 'package:JsxposedX/features/ai/domain/constants/builtin_ai_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('builtin ai config', () {
    test('includes both builtin providers with expected protocol defaults', () {
      expect(
        builtinAiConfigSpecs.map((spec) => spec.id),
        containsAll([builtinAiConfigId, builtinKimiAiConfigId]),
      );

      final padiConfig = buildBuiltinAiConfig();
      expect(padiConfig.apiType, AiApiType.openaiResponses);
      expect(padiConfig.fullApiUrl, 'https://padi.closeai.hk/v1/responses');

      final kimiConfig = buildBuiltinAiConfig(id: builtinKimiAiConfigId);
      expect(kimiConfig.apiType, AiApiType.openai);
      expect(kimiConfig.moduleName, 'Pro/moonshotai/Kimi-K2.5');
      expect(
        kimiConfig.fullApiUrl,
        'https://kimi.closeai.hk/v1/chat/completions',
      );
    });

    test('enables padi options only for the responses builtin config', () {
      expect(shouldUseBuiltinPadiOptions(buildBuiltinAiConfig()), isTrue);
      expect(
        shouldUseBuiltinPadiOptions(
          buildBuiltinAiConfig(id: builtinKimiAiConfigId),
        ),
        isFalse,
      );
    });
  });
}
