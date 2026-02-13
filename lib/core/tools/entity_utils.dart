import 'package:fixnum/fixnum.dart';

/// Entity type constants matching the game's EEntityType enum.
class EEntityTypeId {
  static const int monster = 1;
  static const int npc = 2;
  static const int char = 10;
  static const int gather = 11;
  static const int object = 12;
}

class EntityUtils {
  /// Checks if the UUID belongs to a player (EntChar, type 10).
  /// Player UUIDs have lower 16 bits = (10 << 6) = 640.
  static bool isUuidPlayerRaw(Int64 uuidRaw) {
    return getEntityType(uuidRaw) == EEntityTypeId.char;
  }

  /// Checks if the UUID belongs to a monster (EntMonster, type 1).
  static bool isUuidMonster(Int64 uuidRaw) {
    return getEntityType(uuidRaw) == EEntityTypeId.monster;
  }

  /// Extracts entity type from UUID.
  /// The entity type is encoded in bits 6-10 of the UUID.
  /// Returns: Monster=1, NPC=2, Char=10, Gather=11, Object=12
  static int getEntityType(Int64 uuidRaw) {
    return ((uuidRaw >> 6) & Int64(0x1F)).toInt();
  }

  /// Extracts entity UID from UUID (works for all entity types).
  static Int64 getEntityUid(Int64 uuidRaw) {
    return uuidRaw >> 16;
  }

  /// Alias for getEntityUid - kept for backward compatibility.
  static Int64 getPlayerUid(Int64 uuidRaw) {
    return uuidRaw >> 16;
  }

  /// Checks if the UUID represents a summon entity.
  static bool isSummon(Int64 uuidRaw) {
    return ((uuidRaw >> 15) & Int64.ONE) == Int64.ONE;
  }
}
