import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'logcat_provider.g.dart';

class LogcatEntry {
  final String rawLine;
  final String level;
  final String tag;
  final String message;
  final String timestamp;

  LogcatEntry({
    required this.rawLine,
    required this.level,
    this.tag = '',
    this.message = '',
    this.timestamp = '',
  });
}

@riverpod
class Logcat extends _$Logcat {
  Process? _process;
  bool _isAutoScroll = true;
  String _targetPackage = '';
  String _searchQuery = '';
  bool _isDisposed = false;

  @override
  List<LogcatEntry> build() {
    _isDisposed = false;
    ref.onDispose(() {
      _isDisposed = true;
      _process?.kill();
    });
    return [];
  }

  bool get isAutoScroll => _isAutoScroll;
  String get searchQuery => _searchQuery;

  void setAutoScroll(bool value) {
    _isAutoScroll = value;
    // Just trigger rebuild for consumers if needed
    state = [...state];
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    state = [...state];
  }

  Future<void> start(String packageName) async {
    _targetPackage = packageName;
    if (_process != null) return;

    // Auto clear on start
    state = [];

    try {
      _process = await Process.start('su', ['-c', 'logcat -v time']);
      _process!.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen((line) {
            if (_isDisposed) return;
            if (_passesFilter(line)) {
              final entry = _parseLine(line);
              final updated = [...state, entry];
              // Limit memory to 500 lines to prevent scrolling lag
              if (updated.length > 500) {
                updated.removeRange(0, updated.length - 300);
              }
              state = updated;
            }
          });
      // We ignore stderr to avoid clutter
    } catch (e) {
      debugPrint("Logcat error: $e");
    }
  }

  void stop() {
    _process?.kill();
    _process = null;
  }

  void clear() {
    state = [];
  }

  bool _passesFilter(String line) {
    if (line.isEmpty) return false;

    // Core filter for JsxposedX 业务日志
    bool isRelevant =
        line.contains('JsxposedX') ||           // LogX 统一日志
        line.contains('FridaInjectTest') ||     // Frida 注入日志
        line.contains('HookJsXposed') ||        // Xposed Hook 日志
        line.contains('JsxposedProvider') ||    // Provider 日志
        line.contains('AttachHooker') ||        // Hook 附加日志
        line.contains('StatusManagement') ||    // 状态管理日志
        line.contains('AuditLogProvider');      // 审计日志

    // 包含目标应用包名的日志也显示
    if (_targetPackage.isNotEmpty && line.contains(_targetPackage)) {
      isRelevant = true;
    }

    return isRelevant;
  }

  static final _logcatRegex = RegExp(
    r'^(\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+)\s+\d+\s+\d+\s+([A-Z])\/([^:]+):\s*(.*)$',
  );

  LogcatEntry _parseLine(String line) {
    final match = _logcatRegex.firstMatch(line);
    if (match != null) {
      return LogcatEntry(
        rawLine: line,
        level: match.group(2) ?? 'I',
        timestamp: match.group(1) ?? '',
        tag: match.group(3)?.trim() ?? '',
        message: match.group(4) ?? '',
      );
    }
    // Fallback for non-standard lines
    String level = 'I';
    if (line.contains(' W/')) {
      level = 'W';
    } else if (line.contains(' E/') ||
        line.contains('Exception') ||
        line.contains('Error')) {
      level = 'E';
    } else if (line.contains(' F/')) {
      level = 'F';
    } else if (line.contains(' D/')) {
      level = 'D';
    }
    return LogcatEntry(rawLine: line, level: level, message: line);
  }
}
