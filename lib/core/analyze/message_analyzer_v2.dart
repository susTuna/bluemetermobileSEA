import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:zstd/zstd.dart';

import '../protocol/blue_protocol.dart';
import '../services/logger_service.dart';
import '../state/data_storage.dart';
import '../tools/byte_reader.dart';
import 'message_handler_registry.dart';

class MessageAnalyzerV2 {
  final MessageHandlerRegistry _registry;
  final DataStorage _storage;
  final ZstdCodec _zstd = ZstdCodec();
  final LoggerService _logger = LoggerService();
  final String tag;

  // Message Types
  static const int _msgTypeCall = 1;
  static const int _msgTypeNotify = 2;
  static const int _msgTypeReturn = 3;
  static const int _msgTypeFrameDown = 6;

  // Service UUID for Combat (0x0000000063335342)
  static final BigInt _combatServiceUuid = BigInt.parse("63335342", radix: 16);

  MessageAnalyzerV2(DataStorage storage, {this.tag = 'game'}) : _storage = storage, _registry = MessageHandlerRegistry(storage);

  void process(Uint8List packetData) {
    if (packetData.isEmpty) return;

    final reader = ByteReader(packetData);
    if (reader.remaining < 2) return;

    final packetType = reader.readUInt16BE();
    final isZstdCompressed = (packetType & 0x8000) != 0;
    final msgTypeId = packetType & 0x7FFF;

    final payload = reader.readBytes(reader.remaining);

    switch (msgTypeId) {
      case _msgTypeCall:
        _processCallMsg(payload, isZstdCompressed);
        break;
      case _msgTypeNotify:
        _processNotifyMsg(payload, isZstdCompressed);
        break;
      case _msgTypeFrameDown:
        _processFrameDown(payload, isZstdCompressed);
        break;
      case _msgTypeReturn:
        _processReturnMsg(payload, isZstdCompressed);
        break;
      default:
        // _logger.log("Unknown Message Type: $msgTypeId");
        break;
    }
  }

  void _processNotifyMsg(Uint8List data, bool isCompressed) {
    final reader = ByteReader(data);
    if (reader.remaining < 16) return; // 8 + 4 + 4

    final serviceUuid = reader.readUInt64BE();
    reader.skip(4); // stubId
    final methodId = reader.readUInt32BE();

    final isCombat = serviceUuid == _combatServiceUuid;
    final hasProcessor = _registry.getProcessor(methodId) != null;

    if (!isCombat && !hasProcessor) {
      // Unknown service AND unknown method — skip
      return;
    }

    if (!isCombat && hasProcessor) {
      // Non-combat service with same methodId — only process if from combat tag
      // Port 5003 sends methodId=0x6 (same as SyncNearEntities) but different protobuf format
      if (tag == 'port5003') {
        return; // Skip — different service, different format
      }
      debugPrint("[BM] Notify non-combat svc=0x${serviceUuid.toRadixString(16)} method=0x${methodId.toRadixString(16)} — processing anyway");
    }

    Uint8List msgPayload = reader.readBytes(reader.remaining);
    if (isCompressed) {
      try {
        msgPayload = Uint8List.fromList(_zstd.decode(msgPayload));
      } catch (e) {
        _logger.error("Zstd decompression failed", error: e);
        return;
      }
    }

    debugPrint("[BM][$tag] WorldNtf methodId=0x${methodId.toRadixString(16)} (${msgPayload.length} bytes)");

    // Only log 0x15 and 0x16 prominently
    if (methodId == 0x15) {
      debugPrint("[BM][$tag] ========== SyncContainerData (0x15) RECEIVED! ${msgPayload.length}B ==========");
    }

    final processor = _registry.getProcessor(methodId);
    if (processor != null) {
      processor.process(msgPayload);
    }
  }

  void _processReturnMsg(Uint8List data, bool isCompressed) {
    // Return format: [seqId 4B][callSeqId 4B][retCode 4B][protobuf...]
    if (data.length < 12) return;

    if (data.length <= 12) return; // No protobuf payload

    Uint8List protobuf = data.sublist(12);
    if (isCompressed) {
      try {
        protobuf = Uint8List.fromList(_zstd.decode(protobuf));
      } catch (e) {
        return;
      }
    }

    if (protobuf.length <= 10) return;

    // 1) Try as SyncContainerData (wrapper with VData at field 1)
    try {
      final syncData = SyncContainerData.fromBuffer(protobuf);
      if (syncData.hasVData()) {
        final vData = syncData.vData;
        if (vData.hasSceneData() && vData.sceneData.lineId > 0) {
          debugPrint("[BM] >>>>>> SCENE DATA via SyncContainerData! lineId=${vData.sceneData.lineId}, "
              "mapId=${vData.sceneData.mapId}, channelId=${vData.sceneData.channelId}");
          _registry.getProcessor(0x15)?.process(protobuf);
          return;
        }
        if (vData.charId.toInt() > 0 && (vData.hasCharBase() || vData.hasProfessionList())) {
          _registry.getProcessor(0x15)?.process(protobuf);
          return;
        }
      }
    } catch (_) {}

    // 2) Try as raw VData directly (Return payload may not be wrapped in SyncContainerData)
    try {
      final vData = VData.fromBuffer(protobuf);
      // Only trust SceneData from raw VData if the serialized SceneData is small
      // (real SceneData is ~10-30 bytes; false-positive protobuf parses produce 1-9KB blobs)
      if (vData.hasSceneData()) {
        final sd = vData.sceneData;
        final sceneBytes = sd.writeToBuffer();
        if (sceneBytes.length < 100 && sd.lineId > 0) {
          debugPrint("[BM] >>>>>> SCENE DATA via raw VData! lineId=${sd.lineId}, "
              "mapId=${sd.mapId}, channelId=${sd.channelId}");
          _storage.onSceneUpdate(
            lineId: sd.lineId,
            mapId: sd.mapId > 0 ? sd.mapId : null,
            channelId: sd.channelId > 0 ? sd.channelId : null,
          );
          return;
        }
      }
      if (vData.charId.toInt() > 0 && vData.hasCharBase()) {
        debugPrint("[BM] Return raw VData: charId=${vData.charId}, hasSceneData=${vData.hasSceneData()}, "
            "hasCharBase=${vData.hasCharBase()}");
      }
    } catch (_) {}
  }

  void _processCallMsg(Uint8List data, bool isCompressed) {
    // Parse Call format: [serviceUuid 8B][callSeqId 4B][stubId 4B][methodId 4B][payload]
    final reader = ByteReader(data);
    if (reader.remaining < 20) return;

    final serviceUuid = reader.readUInt64BE();
    final callSeqId = reader.readUInt32BE();
    reader.skip(4); // stubId
    final methodId = reader.readUInt32BE();
    final payloadLen = reader.remaining;

    debugPrint("[BM][$tag] Call svc=0x${serviceUuid.toRadixString(16)} seq=$callSeqId method=0x${methodId.toRadixString(16)} payload=${payloadLen}B");
  }

  void _processFrameDown(Uint8List data, bool isCompressed) {
    final reader = ByteReader(data);
    if (reader.remaining < 4) return;

    reader.skip(4); // serverSequenceId

    if (reader.remaining == 0) return;

    Uint8List innerPayload = reader.readBytes(reader.remaining);

    if (isCompressed) {
      try {
        innerPayload = Uint8List.fromList(_zstd.decode(innerPayload));
      } catch (e) {
        debugPrint("[BM] Zstd decompression failed in FrameDown: $e");
        return;
      }
    }
    
    _processPacketStream(innerPayload);
  }

  void _processPacketStream(Uint8List streamData) {
    var offset = 0;
    final view = ByteData.sublistView(streamData);
    
    while (offset + 4 <= streamData.length) {
      final packetSize = view.getUint32(offset, Endian.big);
      if (packetSize < 6) break;
      if (offset + packetSize > streamData.length) break;
      
      // Extract body (skip size 4 bytes)
      // packetSize includes the size header itself.
      // process() expects the body (Type + Payload).
      // So we pass streamData.sublist(offset + 4, offset + packetSize)
      
      final body = streamData.sublist(offset + 4, offset + packetSize);
      process(body);
      
      offset += packetSize;
    }
  }
}
