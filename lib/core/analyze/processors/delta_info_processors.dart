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

    final targetUuid = EntityUtils.getEntityUid(targetUuidRaw);
    
    // Use UUID-based entity type detection (like zdps does)
    final entityType = EntityUtils.getEntityType(targetUuidRaw);
    final isTargetPlayer = entityType == EEntityTypeId.char;
    final isTargetMonster = entityType == EEntityTypeId.monster;
    if (isTargetMonster && !_storage.monsterInfoDatas.containsKey(targetUuid)) {
      final isSummon = EntityUtils.isSummon(targetUuidRaw);
      _storage.ensureMonster(targetUuid, forceRespawn: true, isSummon: isSummon);
    }

    // Auto-create only for players (player data arrives incrementally via deltas)
    if (isTargetPlayer) {
      _storage.ensurePlayer(targetUuid);
    }

    bool hpUpdated = false;

    // Process Attributes
    if (delta.hasAttrs()) {
      final attrCollection = delta.attrs;
      if (attrCollection.attrs.isNotEmpty && (isTargetPlayer || isTargetMonster)) {

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
              case AttrType.attrCri:
              case AttrType.attrCriTotal:
                if (isTargetPlayer) _storage.setPlayerCritical(targetUuid, reader.readInt32());
                break;
              case AttrType.attrLucky:
              case AttrType.attrLuckyTotal:
                if (isTargetPlayer) _storage.setPlayerLucky(targetUuid, reader.readInt32());
                break;
              case AttrType.attrAttack:
              case AttrType.attrAttackTotal:
                if (isTargetPlayer) _storage.setPlayerAttack(targetUuid, reader.readInt32());
                break;
              case AttrType.attrDefense:
              case AttrType.attrDefenseTotal:
                if (isTargetPlayer) _storage.setPlayerDefense(targetUuid, reader.readInt32());
                break;
              case AttrType.attrHaste:
              case AttrType.attrHasteTotal:
                if (isTargetPlayer) _storage.setPlayerHaste(targetUuid, reader.readInt32());
                break;
              case AttrType.attrHastePct:
              case AttrType.attrHastePctTotal:
                if (isTargetPlayer) _storage.setPlayerHastePct(targetUuid, reader.readInt32());
                break;
              case AttrType.attrMastery:
              case AttrType.attrMasteryTotal:
                if (isTargetPlayer) _storage.setPlayerMastery(targetUuid, reader.readInt32());
                break;
              case AttrType.attrMasteryPct:
              case AttrType.attrMasteryPctTotal:
                if (isTargetPlayer) _storage.setPlayerMasteryPct(targetUuid, reader.readInt32());
                break;
              case AttrType.attrVersatility:
              case AttrType.attrVersatilityTotal:
                if (isTargetPlayer) _storage.setPlayerVersatility(targetUuid, reader.readInt32());
                break;
              case AttrType.attrVersatilityPct:
              case AttrType.attrVersatilityPctTotal:
                if (isTargetPlayer) _storage.setPlayerVersatilityPct(targetUuid, reader.readInt32());
                break;
              case AttrType.attrSeasonStrength:
              case AttrType.attrSeasonStrengthTotal:
                if (isTargetPlayer) _storage.setPlayerSeasonStrength(targetUuid, reader.readInt32());
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
                  // Auto-remove dead monsters when server confirms 0 HP
                  if (hpVal <= 0) {
                     _storage.removeMonster(targetUuid);
                  }
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

          final attackerUuid = EntityUtils.getEntityUid(attackerRaw);
          final attackerEntityType = EntityUtils.getEntityType(attackerRaw);
          bool isAttackerPlayer = attackerEntityType == EEntityTypeId.char;
          
          Int64 damageValue = Int64.ZERO;
          bool isLucky = false;
          bool isCrit = false;
          bool isCauseLucky = false;

          // Extract crit/lucky from typeFlag (same as zdps)
          if (d.hasTypeFlag()) {
            isCrit = (d.typeFlag & 1) == 1;
            isCauseLucky = (d.typeFlag & 0x4) == 0x4;
          }

          if (d.hasValue()) {
            damageValue = d.value;
          } else if (d.hasLuckyValue()) {
            damageValue = d.luckyValue;
            isLucky = true;
          }

          // Check if target is dead (monster killed)
          if (d.isDead && isTargetMonster) {
            _storage.setMonsterIsDead(targetUuid, true);
            _storage.removeMonster(targetUuid);
          }

          if (damageValue == Int64.ZERO) continue;

          if (d.type == EDamageType.heal) {
             if (isAttackerPlayer) {
               _storage.addHealing(
                 attackerUuid, 
                 targetUuid, 
                 damageValue, 
                 DateTime.now().millisecondsSinceEpoch,
                 skillId: d.ownerId.toString(),
                 isCrit: isCrit,
               );
             }
          } else {
             if (d.type == EDamageType.normal || d.type == EDamageType.miss) {
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
                    isLucky: isLucky || isCauseLucky,
                    isCrit: isCrit,
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
        }

        // Position jump detection (log only)
        if (deltaInfo.hasBaseDelta() && deltaInfo.baseDelta.hasAttrs()) {
           for (var attr in deltaInfo.baseDelta.attrs.attrs) {
             if (attr.id == 52) {
               final val = AttrParser.parse(52, attr.rawData);
               if (val is Map<String, double>) {
                 final oldPos = _storage.playerInfoDatas[playerUid]?.position;
                 if (oldPos != null && _calculateDist(oldPos, val) > 250000) {
                     _logger.log("Big position jump — ${_storage.monsterInfoDatas.length} monsters");
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
