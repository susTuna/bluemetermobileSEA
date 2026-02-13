import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';

import '../../protocol/blue_protocol.dart';
import '../../services/logger_service.dart';
import '../../state/data_storage.dart';
import '../../tools/entity_utils.dart';
import 'message_processor.dart';

/// Processes SyncContainerData (methodId 0x15) — full player data on login/map change.
///
/// VData is a standard protobuf CharSerialize message (confirmed by zdps reference).
/// Fields: charId(1), charBase(2), sceneData(3), attr(16), roleLevel(22), professionList(61).
class SyncContainerDataProcessor implements IMessageProcessor {
  final DataStorage _storage;
  final LoggerService _logger = LoggerService();

  SyncContainerDataProcessor(this._storage);

  @override
  void process(Uint8List payload) {
    try {
      final syncContainerData = SyncContainerData.fromBuffer(payload);
      if (!syncContainerData.hasVData()) {
        _logger.log("SyncContainerData: no VData");
        return;
      }

      final vData = syncContainerData.vData;

      debugPrint("[BM] SyncContainerData — charId=${vData.charId}, "
          "hasCharBase=${vData.hasCharBase()}, hasSceneData=${vData.hasSceneData()}, "
          "hasAttr=${vData.hasAttr()}, hasRoleLevel=${vData.hasRoleLevel()}, "
          "hasProfessionList=${vData.hasProfessionList()}");

      if (vData.charId == Int64.ZERO) {
        _logger.log("SyncContainerData: charId is 0, ignoring");
        return;
      }

      // Determine the player UID from charId
      Int64 playerUid = vData.charId;
      if (playerUid > Int64(0xFFFFFFFF)) {
        // Raw UUID — extract UID
        playerUid = EntityUtils.getPlayerUid(playerUid);
      }

      _storage.currentPlayerUuid = playerUid;
      _storage.ensurePlayer(playerUid);

      // CharBase → name, combat power
      if (vData.hasCharBase()) {
        if (vData.charBase.name.isNotEmpty) {
          _storage.setPlayerName(playerUid, vData.charBase.name);
        }
        if (vData.charBase.fightPoint != 0) {
          _storage.setPlayerCombatPower(playerUid, vData.charBase.fightPoint);
        }
      }

      // SceneData → lineId, mapId, channelId
      if (vData.hasSceneData()) {
        final scene = vData.sceneData;
        debugPrint("[BM] SyncContainerData SceneData — mapId=${scene.mapId}, "
            "channelId=${scene.channelId}, planeId=${scene.planeId}, lineId=${scene.lineId}, "
            "hasLineId=${scene.hasLineId()}, hasMapId=${scene.hasMapId()}");
        _storage.onSceneUpdate(
          lineId: scene.lineId > 0 ? scene.lineId : null,
          mapId: scene.mapId > 0 ? scene.mapId : null,
          channelId: scene.channelId > 0 ? scene.channelId : null,
        );
      } else {
        _logger.log("SyncContainerData: SceneData absent — clearing monsters");
        _storage.clearMonsters();
      }

      // Attr → HP
      if (vData.hasAttr()) {
        if (vData.attr.curHp != Int64.ZERO) {
          _storage.setPlayerHp(playerUid, vData.attr.curHp.toInt());
        }
        if (vData.attr.maxHp != Int64.ZERO) {
          _storage.setPlayerMaxHp(playerUid, vData.attr.maxHp.toInt());
        }
      }

      // RoleLevel → level
      if (vData.hasRoleLevel() && vData.roleLevel.level != 0) {
        _storage.setPlayerLevel(playerUid, vData.roleLevel.level);
      }

      // ProfessionList → class
      if (vData.hasProfessionList() && vData.professionList.curProfessionId != 0) {
        _storage.setPlayerProfessionId(playerUid, vData.professionList.curProfessionId);
      }

    } catch (e) {
      _logger.error("Error processing SyncContainerData", error: e);
    }
  }
}
