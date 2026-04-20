import 'package:JsxposedX/features/memory_tool_overlay/domain/memory_ai_overlay_environment_adapter.dart';
import 'package:JsxposedX/generated/memory_tool.g.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'memory_ai_overlay_environment_provider.g.dart';

class MemoryAiOverlayEnvironmentArgs {
  const MemoryAiOverlayEnvironmentArgs({
    required this.processInfo,
    required this.isZh,
  });

  final ProcessInfo processInfo;
  final bool isZh;

  @override
  bool operator ==(Object other) {
    return other is MemoryAiOverlayEnvironmentArgs &&
        other.processInfo == processInfo &&
        other.isZh == isZh;
  }

  @override
  int get hashCode => Object.hash(processInfo, isZh);
}

@riverpod
MemoryAiOverlayEnvironmentAdapter memoryAiOverlayEnvironment(
  Ref ref,
  MemoryAiOverlayEnvironmentArgs args,
) {
  return MemoryAiOverlayEnvironmentAdapter(
    processInfo: args.processInfo,
    isZh: args.isZh,
  );
}
