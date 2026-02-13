import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';
import 'package:protobuf/protobuf.dart';
import 'dart:typed_data';

import '../../protocol/blue_protocol.dart';
import '../../models/attr_type.dart';
import '../../state/data_storage.dart';
import '../../tools/attr_parser.dart';
import '../../tools/entity_utils.dart';
import 'message_processor.dart';

class SyncNearEntitiesProcessor implements IMessageProcessor {
  final DataStorage _storage;

  SyncNearEntitiesProcessor(this._storage);

  @override
  void process(Uint8List payload) {
    try {
      final syncNearEntities = SyncNearEntities.fromBuffer(payload);
      
      if (syncNearEntities.appear.isNotEmpty) {
        for (var entity in syncNearEntities.appear) {
          if (entity.entType != EEntityType.entChar && entity.entType != EEntityType.entMonster) continue;

          final uid = EntityUtils.getEntityUid(entity.uuid);
          if (uid == Int64.ZERO) continue;
          
          final attrCollection = entity.attrs;
          if (attrCollection.attrs.isEmpty) continue;

          if (entity.entType == EEntityType.entChar) {
            _processPlayerAttrs(uid, attrCollection.attrs);
          } else if (entity.entType == EEntityType.entMonster) {
            _processMonsterAttrs(uid, attrCollection.attrs);
          }
        }
      }

      if (syncNearEntities.disappear.isNotEmpty) {
        for (var entity in syncNearEntities.disappear) {
           final uid = EntityUtils.getEntityUid(entity.uuid);
           if (uid == Int64.ZERO) continue;
           
           // Use UUID-based entity type detection
           final entityType = EntityUtils.getEntityType(entity.uuid);
           if (entityType == EEntityTypeId.char) {
              _storage.removePlayer(uid);
           } else if (entityType == EEntityTypeId.monster) {
              // TransferPassLineLeave indicates line change — already handled by onSceneUpdate
              _storage.removeMonster(uid);
           }
        }
      }
    } catch (e) {
      debugPrint("Error processing SyncNearEntities: $e");
    }
  }

  void _processMonsterAttrs(Int64 uid, List<Attr> attrs) {
    // Temporary storage to validate entity before creation
    Map<String, double>? pos;
    Map<String, double>? rot;
    String? name;
    int? level;
    Int64? hp;
    Int64? maxHp;
    int? templateId;

    for (var attr in attrs) {
      if (attr.id == 0 || attr.rawData.isEmpty) continue;
      
      // Handle complex types via AttrParser
      if (attr.id == 52) { // AttrPos
         final val = AttrParser.parse(52, attr.rawData);
         if (val is Map<String, dynamic>) {
           pos = val.map((k, v) => MapEntry(k, (v as num).toDouble()));
         }
         continue;
      }
      if (attr.id == 374) { // AttrRotation
         final val = AttrParser.parse(374, attr.rawData);
         if (val is Map<String, dynamic>) {
           rot = val.map((k, v) => MapEntry(k, (v as num).toDouble()));
         }
         continue;
      }
      if (attr.id == 11320) { // AttrMaxHp
        final val = AttrParser.parse(11320, attr.rawData);
        if (val is Int64) maxHp = val;
        else if (val is int) maxHp = Int64(val);
        continue;
      }
      if (attr.id == 11310) { // AttrHp
        final val = AttrParser.parse(11310, attr.rawData);
        if (val is Int64) hp = val;
        else if (val is int) hp = Int64(val);
        continue;
      }

      // Handle primitives via Reader
      final reader = CodedBufferReader(attr.rawData);
      final attrType = AttrType.fromId(attr.id);

      try {
        switch (attrType) {
          case AttrType.attrName: // 1
            name = reader.readString();
            break;
          case AttrType.attrLevel: // 10000
            level = reader.readInt32();
            break;
          case AttrType.attrId: // Template ID (10)
             templateId = reader.readInt32();
             break;
          default:
            break;
        }
      } catch (e) {
        // Ignore read errors
      }
    }

    // Filter: Only add if it looks like a real monster
    // Should have Position AND (MaxHP > 0 OR Level > 0 OR Name != null)
    // Objects/Gatherables often lack Battle Stats.
    if ((maxHp != null && maxHp > Int64.ZERO) || 
        (level != null && level > 0) || 
        (name != null && name.isNotEmpty)) {
       
       // CRITICAL: Do NOT respawn if HP is explicitly 0 (Dead body lingering)
       if (hp != null && hp <= Int64.ZERO) {
          _storage.removeMonster(uid);
          return;
       }

       _storage.ensureMonster(uid, forceRespawn: true);
       
       if (pos != null) _storage.setMonsterPosition(uid, pos);
       if (rot != null) _storage.setMonsterRotation(uid, rot);
       if (name != null) _storage.setMonsterName(uid, name);
       if (level != null) _storage.setMonsterLevel(uid, level);
       if (hp != null) _storage.setMonsterHp(uid, hp);
       if (maxHp != null) _storage.setMonsterMaxHp(uid, maxHp);
       if (templateId != null) _storage.setMonsterTemplateId(uid, templateId);
    }
  }

  void _processPlayerAttrs(Int64 playerUid, List<Attr> attrs) {
    _storage.ensurePlayer(playerUid);

    for (var attr in attrs) {
      if (attr.id == 0 || attr.rawData.isEmpty) continue;
      
      // Handle complex types first
      if (attr.id == 52) { // AttrPos
         final val = AttrParser.parse(52, attr.rawData);
         if (val is Map<String, double>) {
           _storage.setPlayerPosition(playerUid, val);
         }
         continue;
      }
      if (attr.id == 374) { // AttrRotation
         final val = AttrParser.parse(374, attr.rawData);
         if (val is Map<String, double>) {
           _storage.setPlayerRotation(playerUid, val);
         }
         continue;
      }
      if (attr.id == 11320) { // AttrMaxHp
        // Try reading as Int32/Int64 via parser or reader
         final reader = CodedBufferReader(attr.rawData);
         try {
            _storage.setPlayerMaxHp(playerUid, reader.readInt64().toInt());
         } catch (_) {
            // Fallback
         }
         continue;
      }
      
      final reader = CodedBufferReader(attr.rawData);
      final attrType = AttrType.fromId(attr.id);
      if (attrType == AttrType.unknown) continue;

      try {
        switch (attrType) {
          case AttrType.attrName:
            final name = reader.readString();
            _storage.setPlayerName(playerUid, name);
            break;
          case AttrType.attrProfessionId:
            _storage.setPlayerProfessionId(playerUid, reader.readInt32());
            break;
          case AttrType.attrFightPoint:
            _storage.setPlayerCombatPower(playerUid, reader.readInt32());
            break;
          case AttrType.attrLevel:
            _storage.setPlayerLevel(playerUid, reader.readInt32());
            break;
          case AttrType.attrHp:
            _storage.setPlayerHp(playerUid, reader.readInt32());
            break;
          default:
            break;
        }
      } catch (e) {
        // Ignore read errors for individual attributes
      }
    }
  }
}
