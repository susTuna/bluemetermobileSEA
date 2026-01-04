import 'package:fixnum/fixnum.dart';

class EntityUtils {
  static bool isUuidPlayerRaw(Int64 uuidRaw) {
    return (uuidRaw & 0xFFFF) == 640;
  }

  static Int64 getPlayerUid(Int64 uuidRaw) {
    return uuidRaw >> 16;
  }
}
