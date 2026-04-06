import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class MemoryToolOverlay extends HookConsumerWidget {
  const MemoryToolOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(body: Text("data"));
  }
}
