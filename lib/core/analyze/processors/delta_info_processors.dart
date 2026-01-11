import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';
import 'package:protobuf/protobuf.dart';

import '../../protocol/blue_protocol.dart';
import '../../models/attr_type.dart';
import '../../services/logger_service.dart';
import '../../state/data_storage.dart';
import '../../tools/entity_utils.dart';
import '../../tools/attr_parser.dart';
import 'message_processor.dart';

abstract class BaseDeltaInfoProcessor implements IMessageProcessor {
  final DataStorage _storage;
  final LoggerService _logger = LoggerService();

  BaseDeltaInfoProcessor(this._storage);

  void _processAoiSyncDelta(AoiSyncDelta? delta) {
    if (delta == null) return;

    final targetUuidRaw = delta.uuid;
    if (targetUuidRaw == Int64.ZERO) return;

    final isTargetPlayer = EntityUtils.isUuidPlayerRaw(targetUuidRaw);
    final targetUuid = EntityUtils.getPlayerUid(targetUuidRaw);
    final isTargetMonster = !isTargetPlayer && _storage.monsterInfoDatas.containsKey(targetUuid);

    bool hpUpdated = false;

    // Process Attributes
    if (delta.hasAttrs()) {
      final attrCollection = delta.attrs;
      if (attrCollection.attrs.isNotEmpty && (isTargetPlayer || isTargetMonster)) {
        if (isTargetPlayer) _storage.ensurePlayer(targetUuid);
        if (isTargetMonster) _storage.ensureMonster(targetUuid);

        for (var attr in attrCollection.attrs) {
          if (attr.id == 0 || attr.rawData.isEmpty) continue;

          // Handle Position (52)
          if (attr.id == 52) {
            final val = AttrParser.parse(52, attr.rawData);
            if (val is Map<String, double>) {
              if (isTargetPlayer) {
                _storage.setPlayerPosition(targetUuid, val);
              } else {
                _storage.setMonsterPosition(targetUuid, val);
              }
            }
            continue;
          }

          // Handle Rotation (374)
          if (attr.id == 374) {
            final val = AttrParser.parse(374, attr.rawData);
            if (val is Map<String, double>) {
              if (isTargetPlayer) {
                _storage.setPlayerRotation(targetUuid, val);
              } else {
                _storage.setMonsterRotation(targetUuid, val);
              }
            }
            continue;
          }

          // if (!isTargetPlayer) continue; // Removed to allow monster updates

          final reader = CodedBufferReader(attr.rawData);
          final attrType = AttrType.fromId(attr.id);

          // For generic attributes, check who they belong to
          try {
            switch (attrType) {
              case AttrType.attrName:
                if (isTargetPlayer) _storage.setPlayerName(targetUuid, reader.readString());
                break;
              case AttrType.attrProfessionId:
                if (isTargetPlayer) _storage.setPlayerProfessionId(targetUuid, reader.readInt32());
                break;
              case AttrType.attrFightPoint:
                if (isTargetPlayer) _storage.setPlayerCombatPower(targetUuid, reader.readInt32());
                break;
              case AttrType.attrLevel:
                if (isTargetPlayer) _storage.setPlayerLevel(targetUuid, reader.readInt32());
                break;
              case AttrType.attrHp:
                hpUpdated = true;
                final hpParsed = AttrParser.parse(11310, attr.rawData);
                int hpVal = 0;
                if (hpParsed is Int64) hpVal = hpParsed.toInt();
                else if (hpParsed is int) hpVal = hpParsed;
                
                if (isTargetPlayer) {
                  _storage.setPlayerHp(targetUuid, hpVal);
                } else if (isTargetMonster) {
                  _storage.setMonsterHp(targetUuid, Int64(hpVal));
                }
                break;
             case AttrType.attrMaxHp: // Handle MaxHP updates too (11320)
                final maxHpParsed = AttrParser.parse(11320, attr.rawData);
                int maxHpVal = 0;
                if (maxHpParsed is Int64) maxHpVal = maxHpParsed.toInt();
                else if (maxHpParsed is int) maxHpVal = maxHpParsed;

                if (isTargetPlayer) {
                   _storage.setPlayerMaxHp(targetUuid, maxHpVal);
                } else if (isTargetMonster) {
                   _storage.setMonsterMaxHp(targetUuid, Int64(maxHpVal));
                }
                break;
              default:
                break;
            }
          } catch (_) {
            // Ignore read errors
          }
        }
      }
    }

    // Process Skill Effects (Damage/Healing)
    if (delta.hasSkillEffects()) {
      final skillEffect = delta.skillEffects;
      if (skillEffect.damages.isNotEmpty) {
        for (var d in skillEffect.damages) {
          final skillId = d.ownerId;
          if (skillId == 0) continue;

          final attackerRaw = d.topSummonerId != Int64.ZERO ? d.topSummonerId : d.attackerUuid;
          if (attackerRaw == Int64.ZERO) continue;

          final isAttackerPlayer = EntityUtils.isUuidPlayerRaw(attackerRaw);
          final attackerUuid = EntityUtils.getPlayerUid(attackerRaw);

          // Only record if attacker or target is a player (or both)
          // Actually, usually we care if attacker is player (DPS) or target is player (Damage Taken)
          // But for DPS meter, we mostly care about players dealing damage.
          
          // Logic from C# (implied):
          // if (isAttackerPlayer) -> Add Damage Dealt
          // if (isTargetPlayer) -> Add Damage Taken
          
          // Also handle Healing.
          
          Int64 damageValue = Int64.ZERO;
          if (d.hasValue()) {
            damageValue = d.value;
          } else if (d.hasLuckyValue()) {
            damageValue = d.luckyValue;
          }
          
          if (damageValue == Int64.ZERO) continue;

          // Filter out entities that are not players for the DPS list
          // If attacker is not a player, we don't want to show them in the DPS list usually.
          // Unless it's a pet/summon?
          // d.ownerId might link to the summoner.
          
          // If attacker is NOT a player, check if it's a summon (topSummonerId).
          // If topSummonerId is set, use that as the attacker.
          
          // The logic above already does:
          // final attackerRaw = d.topSummonerId != Int64.ZERO ? d.topSummonerId : d.attackerUuid;
          // final isAttackerPlayer = _isUuidPlayerRaw(attackerRaw);
          
          // So if it's a summon, attackerRaw becomes the player's UUID.
          // And isAttackerPlayer becomes true.
          
          // If isAttackerPlayer is false, it means it's a mob/NPC attacking.
          // We only want to record this if the target is a player (Damage Taken).
          
          // Ghost entry issue:
          // If we have an entry with 0 DPS, it might be created but never updated with damage?
          // Or maybe `ensurePlayer` is called somewhere else?
          
          // `_processAoiSyncDelta` calls `_storage.ensurePlayer(targetUuid)` if attrs are present.
          // This is correct, we want to know about players around us.
          
          // But `addDamage` creates `DpsData`.
          
          if (d.type == EDamageType.heal) {
             // Handle Healing
             if (isAttackerPlayer) {
               _storage.addHealing(
                 attackerUuid, 
                 targetUuid, 
                 damageValue, 
                 DateTime.now().millisecondsSinceEpoch,
                 skillId: d.ownerId.toString(),
               );
             }
          } else {
             // Handle Damage
             
             if (d.type == EDamageType.normal || d.type == EDamageType.miss) { 
                // Speculatively update Monster HP locally if target is a monster
                // AND if HP wasn't already updated by an attribute in this packet (to prevent double counting)
                if (isTargetMonster && !hpUpdated) {
                  _storage.decreaseMonsterHp(targetUuid, damageValue);
                }

                if (isAttackerPlayer || isTargetPlayer) {
                  _storage.addDamage(
                    attackerUuid, 
                    targetUuid, 
                    damageValue, 
                    DateTime.now().millisecondsSinceEpoch,
                    skillId: d.ownerId.toString(),
                  );
                }
             }
          }
        }
      }
    }
  }
}

class SyncToMeDeltaInfoProcessor extends BaseDeltaInfoProcessor {
  SyncToMeDeltaInfoProcessor(super.storage);

  @override
  void process(Uint8List payload) {
    try {
      final msg = SyncToMeDeltaInfo.fromBuffer(payload);
      
      if (msg.hasDeltaInfo()) {
        final deltaInfo = msg.deltaInfo;
        final uuidRaw = deltaInfo.uuid;
        
        // Shift the UUID to get the player UID
        final playerUid = EntityUtils.getPlayerUid(uuidRaw);
        
        if (playerUid != Int64.ZERO && _storage.currentPlayerUuid != playerUid) {
          _storage.currentPlayerUuid = playerUid;
          _storage.ensurePlayer(playerUid);
          _logger.log("SyncToMeDeltaInfo - Set currentPlayerUuid to: $playerUid (from raw: $uuidRaw)");
          
          // If PlayerUID changed, it likely means a login or character switch.
          // Clear current monsters to avoid stale data.
          _storage.clearMonsters();
        }

        // Detect teleport / Map change via big position jump?
        // Check if we have position in baseDelta
        if (deltaInfo.hasBaseDelta() && deltaInfo.baseDelta.hasAttrs()) {
           for (var attr in deltaInfo.baseDelta.attrs.attrs) {
             if (attr.id == 52) { // AttrPos
               final val = AttrParser.parse(52, attr.rawData);
               if (val is Map<String, double>) {
                 final oldPos = _storage.playerInfoDatas[playerUid]?.position;
                 if (oldPos != null) {
                   final dist = _calculateDist(oldPos, val);
                   // If jump > 500 units, clear monsters
                   // User reported issues with "3m" residue.
                   // If units are Meters, 500m is a good threshold for teleport.
                   if (dist > 250000) { // 500 squared
                     _storage.clearMonsters();
                   }
                 }
               }
             }
           }
        }

        if (deltaInfo.hasBaseDelta()) {
          _processAoiSyncDelta(deltaInfo.baseDelta);
        }
      }
    } catch (e) {
      _logger.error("Error processing SyncToMeDeltaInfo", error: e);
    }
  }

  double _calculateDist(Map<String, double> p1, Map<String, double> p2) {
    final dx = (p1['x'] ?? 0) - (p2['x'] ?? 0);
    final dy = (p1['y'] ?? 0) - (p2['y'] ?? 0);
    final dz = (p1['z'] ?? 0) - (p2['z'] ?? 0);
    return (dx * dx + dy * dy + dz * dz); // Squared distance for perf
  }
}

class SyncNearDeltaInfoProcessor extends BaseDeltaInfoProcessor {
  SyncNearDeltaInfoProcessor(super.storage);

  @override
  void process(Uint8List payload) {
    try {
      final msg = SyncNearDeltaInfo.fromBuffer(payload);
      if (msg.deltaInfos.isNotEmpty) {
        for (var delta in msg.deltaInfos) {
          _processAoiSyncDelta(delta);
        }
      }
    } catch (e) {
      _logger.error("Error processing SyncNearDeltaInfo", error: e);
    }
  }
}
