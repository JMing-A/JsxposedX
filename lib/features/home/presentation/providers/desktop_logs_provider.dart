import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:JsxposedX/core/transport/jsxposed_protocol.dart';
import 'package:JsxposedX/features/home/presentation/providers/desktop_connection_provider.dart';

/// 手机端推送的控制台日志条目，字段与 LogcatEntry 对齐
@immutable
class DesktopLogEntry {
  const DesktopLogEntry({
    required this.rawLine,
    required this.level,
    this.tag = '',
    this.message = '',
    this.timestamp = '',
    this.source = 'system',
    this.scriptName = '',
    this.runId = '',
    this.pid = '',
    this.stackTrace = '',
  });

  final String rawLine;
  final String level;
  final String tag;
  final String message;
  final String timestamp;
  final String source;
  final String scriptName;
  final String runId;
  final String pid;
  final String stackTrace;

  /// 展示用文本：结构化条目用 message，否则回退到原始行
  String get displayText => message.isEmpty ? rawLine : message;

  factory DesktopLogEntry.fromJson(Map<String, dynamic> json) =>
      DesktopLogEntry(
        rawLine: json['rawLine'] as String? ?? '',
        level: json['level'] as String? ?? 'I',
        tag: json['tag'] as String? ?? '',
        message: json['message'] as String? ?? '',
        timestamp: json['timestamp'] as String? ?? '',
        source: json['source'] as String? ?? 'system',
        scriptName: json['scriptName'] as String? ?? '',
        runId: json['runId'] as String? ?? '',
        pid: json['pid'] as String? ?? '',
        stackTrace: json['stackTrace'] as String? ?? '',
      );
}

/// PC 端控制台日志缓存，供输出面板渲染与复制
final desktopLogsProvider =
    NotifierProvider<DesktopLogsNotifier, List<DesktopLogEntry>>(
      DesktopLogsNotifier.new,
    );

class DesktopLogsNotifier extends Notifier<List<DesktopLogEntry>> {
  static const _maxEntries = 2000;

  StreamSubscription<JsxposedMessage>? _subscription;

  @override
  List<DesktopLogEntry> build() {
    final notifier = ref.read(desktopConnectionProvider.notifier);
    _subscription = notifier.events.listen(_handleEvent);
    ref.onDispose(() {
      unawaited(_subscription?.cancel());
      _subscription = null;
    });
    return const [];
  }

  void _handleEvent(JsxposedMessage message) {
    if (message.event != JsxposedEvent.logEntry) return;
    final payload = message.result;
    if (payload is! Map) return;
    final entry = DesktopLogEntry.fromJson(payload.cast<String, dynamic>());
    final combined = <DesktopLogEntry>[...state, entry];
    state = combined.length > _maxEntries
        ? combined.sublist(combined.length - _maxEntries)
        : combined;
  }

  void clear() {
    if (state.isNotEmpty) state = const [];
  }
}
