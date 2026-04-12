import 'package:pigeon/pigeon.dart';

@HostApi()
abstract class MemoryToolNative {
  @async
  int getPid({required String packageName});
}
