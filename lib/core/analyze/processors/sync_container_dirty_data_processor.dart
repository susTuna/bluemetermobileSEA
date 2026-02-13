import 'dart:convert';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';

import '../../protocol/blue_protocol.dart';
import '../../services/logger_service.dart';
import '../../state/data_storage.dart';
import 'message_processor.dart';

/// Processes SyncContainerDirtyData (methodId 0x16) — incremental player data updates.
///
/// VData is a BufferStream containing blob-encoded CharSerialize bytes.
/// Blob format (zdps BlobType.Read):
///   [-2 tag][pad][SIZE][pad][field1_idx][pad][data1]...[field_N_idx][pad][dataN][-3 tag][pad]
///
/// Each ReadInt/ReadUInt: 4 bytes data + 4 bytes padding = 8 bytes.
/// ReadLong: 8 bytes data + 4 bytes padding = 12 bytes.
/// ReadString: ReadUInt(length) + data(length bytes) + 4 bytes padding.
/// Sub-blobs: same recursive [-2][pad][SIZE][pad]...[- 3][pad] format.
class SyncContainerDirtyDataProcessor implements IMessageProcessor {
  final DataStorage _storage;
  final LoggerService _logger = LoggerService();

  SyncContainerDirtyDataProcessor(this._storage);

  @override
  void process(Uint8List payload) {
    try {
      if (_storage.currentPlayerUuid == Int64.ZERO) return;

      final dirty = SyncContainerDirtyData.fromBuffer(payload);
      if (!dirty.hasVData() || !dirty.vData.hasBufferS() || dirty.vData.bufferS.isEmpty) return;

      final buf = Uint8List.fromList(dirty.vData.bufferS);
      final reader = _BlobReader(buf);

      final playerUid = _storage.currentPlayerUuid;
      _storage.ensurePlayer(playerUid);

      // Parse top-level CharSerialize blob using zdps BlobType.Read() format
      _parseBlobFields(reader, (index) {
        switch (index) {
          case 1: // CharId (int32 in blob format)
            reader.readInt(); // consume charId, we already know it
            return true;
          case 2: // CharBase sub-blob
            return _parseCharBase(reader, playerUid);
          case 3: // SceneData sub-blob
            return _parseSceneData(reader);
          case 16: // UserFightAttr sub-blob
            return _parseAttr(reader, playerUid);
          case 61: // ProfessionList sub-blob
            return _parseProfessionList(reader, playerUid);
          default:
            return false; // Unknown field → skip rest of blob
        }
      });
    } catch (e) {
      _logger.error("Error processing SyncContainerDirtyData", error: e);
    }
  }

  // ---------------------------------------------------------------------------
  // Sub-blob parsers
  // ---------------------------------------------------------------------------

  bool _parseCharBase(_BlobReader reader, Int64 playerUid) {
    return _parseBlobFields(reader, (index) {
      switch (index) {
        case 1: // CharId (long in CharBase)
          reader.readLong();
          return true;
        case 2: // AccountId (string)
          reader.readString();
          return true;
        case 3: // ShowId (long)
          reader.readLong();
          return true;
        case 4: // ServerId (uint)
          reader.readInt();
          return true;
        case 5: // Name (string)
          final name = reader.readString();
          _logger.log("SyncContainerDirtyData Name: '$name'");
          if (name.isNotEmpty) {
            _storage.setPlayerName(playerUid, name);
          }
          return true;
        case 6: // Gender (int)
          reader.readInt();
          return true;
        case 35: // FightPoint (int)
          final fp = reader.readInt();
          if (fp != 0) {
            _storage.setPlayerCombatPower(playerUid, fp);
          }
          return true;
        default:
          return false; // Unknown → skip rest
      }
    });
  }

  bool _parseSceneData(_BlobReader reader) {
    int? lineId;
    int? mapId;
    int? channelId;

    final ok = _parseBlobFields(reader, (index) {
      switch (index) {
        case 1: // MapId
          mapId = reader.readInt();
          return true;
        case 2: // ChannelId
          channelId = reader.readInt();
          return true;
        case 3: // Pos (sub-blob)
          return _skipSubBlob(reader);
        case 4: // LevelUuid (long)
          reader.readLong();
          return true;
        case 5: // LevelPos (sub-blob)
          return _skipSubBlob(reader);
        case 6: // LevelMapId (uint)
          reader.readInt();
          return true;
        case 7: // LevelReviveId (uint)
          reader.readInt();
          return true;
        case 8: // RecordId (HashMap) — too complex, skip rest
          return false;
        case 9: // PlaneId (uint)
          reader.readInt();
          return true;
        case 12: // BeforeFallPos (sub-blob)
          return _skipSubBlob(reader);
        case 13: // SceneGuid (string)
          reader.readString();
          return true;
        case 14: // DungeonGuid (string)
          reader.readString();
          return true;
        case 15: // LineId
          lineId = reader.readInt();
          return true;
        case 16: // VisualLayerConfigId (uint)
          reader.readInt();
          return true;
        case 18: // SceneAreaId (int)
          reader.readInt();
          return true;
        case 19: // LevelAreaId (int)
          reader.readInt();
          return true;
        case 20: // BeforeFallSceneAreaId (int)
          reader.readInt();
          return true;
        default:
          return false; // Unknown → skip rest
      }
    });

    _logger.log("SyncContainerDirtyData SceneData — mapId=$mapId, channelId=$channelId, lineId=$lineId");
    _storage.onSceneUpdate(lineId: lineId, mapId: mapId, channelId: channelId);
    return ok;
  }

  bool _parseAttr(_BlobReader reader, Int64 playerUid) {
    return _parseBlobFields(reader, (index) {
      switch (index) {
        case 1: // CurHp
          final hp = reader.readInt();
          _storage.setPlayerHp(playerUid, hp);
          return true;
        case 2: // MaxHp
          final mhp = reader.readInt();
          _storage.setPlayerMaxHp(playerUid, mhp);
          return true;
        default:
          return false;
      }
    });
  }

  bool _parseProfessionList(_BlobReader reader, Int64 playerUid) {
    return _parseBlobFields(reader, (index) {
      switch (index) {
        case 1: // CurProfessionId
          final pid = reader.readInt();
          if (pid != 0) {
            _storage.setPlayerProfessionId(playerUid, pid);
          }
          return true;
        default:
          return false;
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Core blob parser — matches zdps BlobType.Read() exactly
  // ---------------------------------------------------------------------------

  /// Parse a blob: reads [-2][pad][size][pad], then iterates field indices.
  /// [fieldHandler] returns true if the field was consumed, false to skip to end.
  /// Returns true if blob was successfully parsed.
  bool _parseBlobFields(_BlobReader reader, bool Function(int fieldIndex) fieldHandler) {
    if (reader.remaining < 8) return false;

    final tag = reader.readInt(); // should be -2
    if (tag != -2) return false;

    if (reader.remaining < 8) return false;
    final size = reader.readInt(); // data size (or -3 if empty)
    if (size == -3) return true; // empty blob
    if (size < 0) return false; // invalid

    final dataStart = reader.offset;

    if (reader.remaining < 8) return true;
    var index = reader.readInt(); // first field index

    while (index > 0) {
      if (!fieldHandler(index)) {
        // Unknown field → skip to end of blob data
        reader.setOffset(dataStart + size);
        // Fall through to read the -3 end tag below
        break;
      }
      if (reader.remaining < 8) break;
      index = reader.readInt(); // next field index or -3
    }

    // If we broke out due to skip, read the -3 end tag
    if (reader.offset == dataStart + size && reader.remaining >= 8) {
      final endTag = reader.readInt();
      if (endTag != -3) {
        _logger.log("BlobType: unexpected end tag $endTag");
      }
    }
    // If we exited the while because index was -3 (read by readInt),
    // reader is already past the -3 tag. ✓

    return true;
  }

  /// Skip a sub-blob entirely by reading its header and jumping past its data + end tag.
  bool _skipSubBlob(_BlobReader reader) {
    if (reader.remaining < 8) return false;

    final tag = reader.readInt();
    if (tag != -2) return false;

    if (reader.remaining < 8) return false;
    final size = reader.readInt();
    if (size == -3) return true; // empty
    if (size < 0) return false;

    // Skip past data
    if (reader.remaining < size + 8) return false; // data + -3 end tag
    reader.skip(size);

    // Consume -3 end tag
    reader.readInt();
    return true;
  }
}

// ---------------------------------------------------------------------------
// Binary reader for blob format — matches zdps BlobReader exactly.
// Each Read*() reads data + 4 bytes padding (like BlobReader.ReadInt = offset += 8).
// ---------------------------------------------------------------------------
class _BlobReader {
  final ByteData _view;
  int _offset;
  final int _length;

  _BlobReader(Uint8List buffer)
      : _view = ByteData.sublistView(buffer),
        _offset = 0,
        _length = buffer.length;

  int get remaining => _length - _offset;
  int get offset => _offset;

  void setOffset(int o) {
    _offset = o.clamp(0, _length);
  }

  void skip(int n) {
    _offset = (_offset + n).clamp(0, _length);
  }

  /// Read int32 LE, advance 8 bytes (4 data + 4 pad). Matches zdps ReadInt().
  int readInt() {
    if (remaining < 8) throw Exception("BlobReader: EndOfStream (readInt)");
    final value = _view.getInt32(_offset, Endian.little);
    _offset += 8;
    return value;
  }

  /// Read uint32 LE, advance 8 bytes. Matches zdps ReadUInt().
  int readUInt() {
    if (remaining < 8) throw Exception("BlobReader: EndOfStream (readUInt)");
    final value = _view.getUint32(_offset, Endian.little);
    _offset += 8;
    return value;
  }

  /// Read int64 LE, advance 12 bytes (8 data + 4 pad). Matches zdps ReadLong().
  int readLong() {
    if (remaining < 12) throw Exception("BlobReader: EndOfStream (readLong)");
    final value = _view.getInt64(_offset, Endian.little);
    _offset += 12;
    return value;
  }

  /// Read string: ReadUInt(length) then data(length) + 4 pad. Matches zdps ReadString().
  String readString() {
    final length = readUInt(); // 8 bytes consumed (length + pad)
    if (length == 0) {
      _offset += 4; // padding after empty string
      return '';
    }
    if (remaining < length + 4) throw Exception("BlobReader: EndOfStream (readString)");
    final bytes = Uint8List.view(_view.buffer, _view.offsetInBytes + _offset, length);
    _offset += length + 4; // data + 4 pad
    return utf8.decode(bytes, allowMalformed: true);
  }
}
