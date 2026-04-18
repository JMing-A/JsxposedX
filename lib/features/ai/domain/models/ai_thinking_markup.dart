class AiThinkingMarkup {
  AiThinkingMarkup._();

  static const String startTag = '<ai-thinking>';
  static const String endTag = '</ai-thinking>';

  static String compose({
    required String thinking,
    required String answer,
  }) {
    final normalizedThinking = thinking.trim();
    final normalizedAnswer = answer.trim();
    if (normalizedThinking.isEmpty) {
      return normalizedAnswer;
    }
    if (normalizedAnswer.isEmpty) {
      return '$startTag\n$normalizedThinking\n$endTag';
    }
    return '$startTag\n$normalizedThinking\n$endTag\n\n$normalizedAnswer';
  }

  static AiThinkingMarkupParts split(String content) {
    final startIndex = content.indexOf(startTag);
    final endIndex = content.indexOf(endTag);
    if (startIndex == -1 || endIndex == -1 || endIndex < startIndex) {
      return AiThinkingMarkupParts(
        answer: content,
      );
    }

    final thinking = content
        .substring(startIndex + startTag.length, endIndex)
        .trim();
    final answer = content.substring(endIndex + endTag.length).trimLeft();
    return AiThinkingMarkupParts(
      thinking: thinking,
      answer: answer,
    );
  }

  static String strip(String content) => split(content).answer.trim();
}

class AiThinkingMarkupParts {
  const AiThinkingMarkupParts({
    this.thinking = '',
    this.answer = '',
  });

  final String thinking;
  final String answer;

  bool get hasThinking => thinking.trim().isNotEmpty;
}
