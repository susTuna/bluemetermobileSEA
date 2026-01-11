import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';

import '../../protocol/blue_protocol.dart';
import '../../services/logger_service.dart';
import '../../state/data_storage.dart';
import '../../tools/entity_utils.dart';
import 'message_processor.dart';

class SyncContainerDataProcessor implements IMessageProcessor {
  final DataStorage _storage;
  final LoggerService _logger = LoggerService();

  SyncContainerDataProcessor(this._storage);

  @override
  void process(Uint8List payload) {
    try {
      final syncContainerData = SyncContainerData.fromBuffer(payload);
      if (!syncContainerData.hasVData()) return;
      
      final vData = syncContainerData.vData;
      if (vData.charId == Int64.ZERO) return;

      // CharId in SyncContainerData seems to be the already shifted UID (or direct ID) 
      // based on reference implementation (bpsr-meter) using .toNumber() directly.
      // If we shift it again, we get 0.
      // We check if it looks like a Raw UUID (ends in 640) vs a UID.
      
      Int64 playerUid = vData.charId;
      if (playerUid > Int64(0xFFFFFFFF)) {
         // It's likely a raw UUID, so shift it
         playerUid = EntityUtils.getPlayerUid(playerUid);
      }
      
      _logger.log("SyncContainerData received. RawID: ${vData.charId}, PlayerUID: $playerUid");

      // Update current player UID if not set or different? 
      // Usually SyncContainerData is for "Me".
      _storage.currentPlayerUuid = playerUid;
      _storage.ensurePlayer(playerUid);

      if (vData.hasRoleLevel() && vData.roleLevel.level != 0) {
        _storage.setPlayerLevel(playerUid, vData.roleLevel.level);
      }

      if (vData.hasAttr()) {
        if (vData.attr.curHp != Int64.ZERO) {
          _storage.setPlayerHp(playerUid, vData.attr.curHp.toInt());
        }
        if (vData.attr.maxHp != Int64.ZERO) {
          _storage.setPlayerMaxHp(playerUid, vData.attr.maxHp.toInt());
        }
      }

      if (vData.hasCharBase()) {
        _logger.log("SyncContainerData Name: '${vData.charBase.name}'");
        if (vData.charBase.name.isNotEmpty) {
          _storage.setPlayerName(playerUid, vData.charBase.name);
        } else {
          _logger.log("SyncContainerData received but Name is empty!");
        }
        if (vData.charBase.fightPoint != 0) {
          _storage.setPlayerCombatPower(playerUid, vData.charBase.fightPoint);
        }
      } else {
        _logger.log("SyncContainerData received but CharBase is missing!");
      }

      if (vData.hasProfessionList() && vData.professionList.curProfessionId != 0) {
        _storage.setPlayerProfessionId(playerUid, vData.professionList.curProfessionId);
      }

    } catch (e) {
      _logger.error("Error processing SyncContainerData", error: e);
    }
  }
}
