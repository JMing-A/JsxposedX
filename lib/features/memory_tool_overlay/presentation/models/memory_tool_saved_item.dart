import 'dart:typed_data';

import 'package:JsxposedX/generated/memory_tool.g.dart';

class MemoryToolSavedItem {
  const MemoryToolSavedItem({
    required this.pid,
    required this.address,
    required this.regionStart,
    required this.regionTypeKey,
    required this.type,
    required this.rawBytes,
    required this.displayValue,
    required this.isFrozen,
  });

  final int pid;
  final int address;
  final int regionStart;
  final String regionTypeKey;
  final SearchValueType type;
  final Uint8List rawBytes;
  final String displayValue;
  final bool isFrozen;

  factory MemoryToolSavedItem.fromSearchResult({
    required int pid,
    required SearchResult result,
    MemoryValuePreview? preview,
    required bool isFrozen,
  }) {
    return MemoryToolSavedItem(
      pid: pid,
      address: result.address,
      regionStart: result.regionStart,
      regionTypeKey: result.regionTypeKey,
      type: preview?.type ?? result.type,
      rawBytes: preview?.rawBytes ?? result.rawBytes,
      displayValue: preview?.displayValue ?? result.displayValue,
      isFrozen: isFrozen,
    );
  }

  MemoryToolSavedItem copyWith({
    int? pid,
    int? address,
    int? regionStart,
    String? regionTypeKey,
    SearchValueType? type,
    Uint8List? rawBytes,
    String? displayValue,
    bool? isFrozen,
  }) {
    return MemoryToolSavedItem(
      pid: pid ?? this.pid,
      address: address ?? this.address,
      regionStart: regionStart ?? this.regionStart,
      regionTypeKey: regionTypeKey ?? this.regionTypeKey,
      type: type ?? this.type,
      rawBytes: rawBytes ?? this.rawBytes,
      displayValue: displayValue ?? this.displayValue,
      isFrozen: isFrozen ?? this.isFrozen,
    );
  }

  SearchResult toSearchResult() {
    return SearchResult(
      address: address,
      regionStart: regionStart,
      regionTypeKey: regionTypeKey,
      type: type,
      rawBytes: rawBytes,
      displayValue: displayValue,
    );
  }
}
