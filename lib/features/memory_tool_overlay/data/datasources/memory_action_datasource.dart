import 'package:JsxposedX/generated/memory_tool.g.dart';

class MemoryActionDatasource {
  final _native = MemoryToolNative();

  Future<void> firstScan({required FirstScanRequest request}) async {
    await _native.firstScan(request);
  }

  Future<void> nextScan({required NextScanRequest request}) async {
    await _native.nextScan(request);
  }

  Future<void> cancelSearch() async {
    await _native.cancelSearch();
  }

  Future<void> resetSearchSession() async {
    await _native.resetSearchSession();
  }

  Future<void> writeMemoryValue({required MemoryWriteRequest request}) async {
    await _native.writeMemoryValue(request);
  }

  Future<void> setMemoryFreeze({required MemoryFreezeRequest request}) async {
    await _native.setMemoryFreeze(request);
  }

  Future<List<FrozenMemoryValue>> getFrozenMemoryValues() async {
    return await _native.getFrozenMemoryValues();
  }
}
