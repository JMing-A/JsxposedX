import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/features/ai/presentation/widgets/ai_chat_compact_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

class ToolCallingIndicator extends HookWidget {
  final String content;

  const ToolCallingIndicator({super.key, required this.content});

  @override
  Widget build(BuildContext context) {
    final scale = AiChatCompactScope.scaleOf(context);
    final animationController = useAnimationController(
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    final toolName = content.contains('get_manifest')
        ? context.l10n.aiToolNameManifest
        : content.contains('decompile')
        ? context.l10n.aiToolNameDecompile
        : content.contains('smali')
        ? context.l10n.aiToolNameSmali
        : content.contains('search')
        ? context.l10n.aiToolNameSearch
        : content.contains('package')
        ? context.l10n.aiToolNamePackages
        : content.contains('class')
        ? context.l10n.aiToolNameClasses
        : null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        RotationTransition(
          turns: animationController,
          child: Icon(
            Icons.settings_outlined,
            size: 16 * scale,
            color: context.colorScheme.primary,
          ),
        ),
        SizedBox(width: 8 * scale),
        Text(
          toolName != null
              ? context.l10n.aiToolReading(toolName)
              : context.l10n.aiToolCalling,
          style: TextStyle(
            fontSize: 13 * scale,
            color: context.colorScheme.primary,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}
