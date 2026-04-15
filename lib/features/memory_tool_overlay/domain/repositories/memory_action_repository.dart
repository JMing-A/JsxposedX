import 'package:JsxposedX/generated/memory_tool.g.dart';

abstract class MemoryActionRepository {
  Future<void> firstScan({required FirstScanRequest request});

  Future<void> nextScan({required NextScanRequest request});

  Future<void> cancelSearch();

  Future<void> resetSearchSession();

  Future<void> writeMemoryValue({required MemoryWriteRequest request});

  Future<void> setMemoryFreeze({required MemoryFreezeRequest request});

  Future<List<FrozenMemoryValue>> getFrozenMemoryValues();
}
