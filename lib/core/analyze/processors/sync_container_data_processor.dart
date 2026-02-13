import 'dart:convert';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';

import '../../protocol/blue_protocol.dart';
import '../../services/logger_service.dart';
import '../../state/data_storage.dart';
import '../../tools/entity_utils.dart';
import 'message_processor.dart';

/// Processes SyncContainerData (methodId 0x15) — full player data on login/map change.
///
/// VData is a BufferStream wrapping blob-encoded CharSerialize bytes.
/// Blob format (Little-Endian): each read = dataSize + 4 bytes padding.
///   - int32/uint32: 4 data + 4 pad = 8 byte advance
///   - int64:        8 data + 4 pad = 12 byte advance
///   - Sub-blob:     starts with tag -2 (0xFFFFFFFE), size (int32), fields, end tag -3
///   - String:       4-byte length + 4 pad + N chars + 4 pad
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
      if (!vData.hasBufferS() || vData.bufferS.isEmpty) return;

      final buf = Uint8List.fromList(vData.bufferS);
      final reader = _BinaryReader(buf);

      // Top-level CharSerialize blob: starts with -2 tag and size
      if (!_readBlobHeader(reader)) return;

      // Parsed values
      Int64 charId = Int64.ZERO;
      String? playerName;
      int? fightPoint;
      int? lineId;
      int? mapId;
      int? channelId;
      int? curHp;
      int? maxHp;
      int? level;
      int? professionId;

      // Parse fields in order. On unknown field: skip if possible, else bail.
      while (reader.remaining >= 8) {
        final fieldIndex = reader.readUInt32();
        reader.readInt32(); // padding

        // End tag -3 (0xFFFFFFFD) or other special marker
        if (fieldIndex >= 0x80000000) break;

        switch (fieldIndex) {
          case 1: // CharId (int64 = 8 data + 4 pad = 12 bytes)
            if (reader.remaining < 12) return;
            charId = reader.readInt64();
            reader.readInt32(); // padding
            break;

          case 2: // CharBase sub-blob — extract name (field 5) and fightPoint (field 35)
            final result = _parseSubBlob(reader, (r, fi) {
              switch (fi) {
                case 5: // Name (string)
                  playerName = _readString(r);
                  return true;
                case 35: // FightPoint (uint32)
                  fightPoint = r.readUInt32();
                  r.readInt32();
                  return true;
                default:
                  return false;
              }
            });
            if (!result) return;
            break;

          case 3: // SceneData sub-blob — extract mapId, channelId, lineId
            final result = _parseSubBlob(reader, (r, fi) {
              switch (fi) {
                case 1: // MapId
                  mapId = r.readUInt32();
                  r.readInt32();
                  return true;
                case 2: // ChannelId
                  channelId = r.readUInt32();
                  r.readInt32();
                  return true;
                case 15: // LineId
                  lineId = r.readUInt32();
                  r.readInt32();
                  return true;
                default:
                  return false;
              }
            });
            if (!result) return;
            break;

          case 16: // UserFightAttr sub-blob — curHp (1), maxHp (2)
            final result = _parseSubBlob(reader, (r, fi) {
              switch (fi) {
                case 1: // curHp (uint32)
                  curHp = r.readUInt32();
                  r.readInt32();
                  return true;
                case 2: // maxHp (uint32)
                  maxHp = r.readUInt32();
                  r.readInt32();
                  return true;
                default:
                  return false;
              }
            });
            if (!result) return;
            break;

          case 22: // RoleLevel sub-blob — level (field 1)
            final result = _parseSubBlob(reader, (r, fi) {
              switch (fi) {
                case 1: // level
                  level = r.readUInt32();
                  r.readInt32();
                  return true;
                default:
                  return false;
              }
            });
            if (!result) return;
            break;

          case 61: // ProfessionList sub-blob — curProfessionId (field 1)
            final result = _parseSubBlob(reader, (r, fi) {
              switch (fi) {
                case 1: // curProfessionId
                  professionId = r.readUInt32();
                  r.readInt32();
                  return true;
                default:
                  return false;
              }
            });
            if (!result) return;
            break;

          default:
            // Unknown field — try to skip it
            if (!_trySkipUnknownField(reader)) {
              // Can't safely skip — stop parsing but use what we have
              break;
            }
            continue; // Don't break out of while, try next field
        }
      }

      // --- Apply parsed data to storage ---

      if (charId == Int64.ZERO) {
        _logger.log("SyncContainerData: charId is 0, ignoring");
        return;
      }

      Int64 playerUid = charId;
      if (playerUid > Int64(0xFFFFFFFF)) {
        // Likely a raw UUID — shift to get UID
        playerUid = EntityUtils.getPlayerUid(playerUid);
      }

      _logger.log("SyncContainerData: charId=$charId, uid=$playerUid, name=$playerName, "
          "line=$lineId, map=$mapId, ch=$channelId, hp=$curHp/$maxHp, lv=$level, prof=$professionId, fp=$fightPoint");

      _storage.currentPlayerUuid = playerUid;
      _storage.ensurePlayer(playerUid);

      if (playerName != null && playerName!.isNotEmpty) {
        _storage.setPlayerName(playerUid, playerName!);
      }
      if (fightPoint != null && fightPoint! > 0) {
        _storage.setPlayerCombatPower(playerUid, fightPoint!);
      }
      if (level != null && level! > 0) {
        _storage.setPlayerLevel(playerUid, level!);
      }
      if (curHp != null && curHp! > 0) {
        _storage.setPlayerHp(playerUid, curHp!);
      }
      if (maxHp != null && maxHp! > 0) {
        _storage.setPlayerMaxHp(playerUid, maxHp!);
      }
      if (professionId != null && professionId! > 0) {
        _storage.setPlayerProfessionId(playerUid, professionId!);
      }

      // SceneData: always call onSceneUpdate (even with nulls) so line changes are detected
      if (lineId != null || mapId != null || channelId != null) {
        _storage.onSceneUpdate(lineId: lineId, mapId: mapId, channelId: channelId);
      } else {
        _logger.log("SyncContainerData: no SceneData found in blob, clearing monsters");
        _storage.clearMonsters();
      }

    } catch (e) {
      _logger.error("Error processing SyncContainerData", error: e);
    }
  }

  // ---------------------------------------------------------------------------
  // Blob parsing helpers
  // ---------------------------------------------------------------------------

  /// Read the -2 marker + size at the start of a blob section.
  /// Consumes 16 bytes (marker 4 + pad 4 + size 4 + pad 4).
  /// Returns true if the marker is valid. Stores the blob size in [_lastBlobSize].
  int _lastBlobSize = 0;

  bool _readBlobHeader(_BinaryReader reader) {
    if (reader.remaining < 16) return false;
    final marker = reader.readUInt32();
    reader.readInt32(); // padding
    _lastBlobSize = reader.readInt32(); // size in bytes (or -3 if empty)
    reader.readInt32(); // padding
    if (marker != 0xFFFFFFFE) return false;
    if (_lastBlobSize < 0) return false; // empty blob (-3 etc.)
    return true;
  }

  /// Parse a sub-blob. Reads the -2/size header, then iterates field indices.
  /// [fieldHandler] receives the reader and field index: return true if handled.
  /// On unknown field -> jump to end of sub-blob using its size.
  /// Returns false if blob is malformed (caller should stop).
  bool _parseSubBlob(_BinaryReader reader, bool Function(_BinaryReader r, int fieldIndex) fieldHandler) {
    if (reader.remaining < 16) return true; // No sub-blob data, not an error
    final startOffset = reader.offset;

    final marker = reader.readUInt32();
    reader.readInt32(); // padding
    if (marker != 0xFFFFFFFE) {
      // Not a sub-blob — maybe a simple value. Rewind and let caller handle.
      reader.setOffset(startOffset);
      // Try to skip as simple value (8 bytes for uint32 value already partially read)
      return _trySkipSimpleValue(reader);
    }

    final blobSize = reader.readInt32();
    reader.readInt32(); // padding

    if (blobSize <= 0) return true; // Empty sub-blob (-3), nothing to parse

    final blobEndOffset = reader.offset + blobSize;

    while (reader.offset < blobEndOffset && reader.remaining >= 8) {
      final fi = reader.readUInt32();
      reader.readInt32(); // padding

      if (fi >= 0x80000000) break; // End tag -3 or special marker

      if (!fieldHandler(reader, fi)) {
        // Unknown sub-field — jump to end of this sub-blob
        reader.setOffset(blobEndOffset);
        return true;
      }
    }

    // Ensure we're at or past the blob end
    if (reader.offset < blobEndOffset) {
      reader.setOffset(blobEndOffset);
    }

    return true;
  }

  /// Try to skip an unknown field at the current reader position.
  /// Heuristic: peek at the next 4 bytes — if 0xFFFFFFFE, it's a sub-blob with known size.
  /// Otherwise, assume it's a simple 8-byte value (uint32 + pad).
  bool _trySkipUnknownField(_BinaryReader reader) {
    if (reader.remaining < 8) return false;

    final peek = reader.peekUInt32();
    if (peek == 0xFFFFFFFE) {
      // Sub-blob: read header and skip by size
      reader.readUInt32(); // -2
      reader.readInt32(); // padding
      if (reader.remaining < 8) return false;
      final size = reader.readInt32();
      reader.readInt32(); // padding
      if (size > 0 && reader.remaining >= size) {
        reader.skip(size);
        return true;
      } else if (size <= 0) {
        return true; // Empty sub-blob
      }
      return false; // Not enough data
    } else {
      // Assume simple uint32 value: 4 data + 4 pad = 8 bytes
      reader.readUInt32();
      reader.readInt32();
      return true;
    }
  }

  bool _trySkipSimpleValue(_BinaryReader reader) {
    if (reader.remaining < 8) return false;
    reader.readUInt32();
    reader.readInt32();
    return true;
  }

  /// Read a blob-encoded string: [4B length][4B pad][N chars][4B pad]
  String? _readString(_BinaryReader reader) {
    if (reader.remaining < 8) return null;
    final length = reader.readUInt32();
    reader.readInt32(); // padding

    if (length == 0 || length > 200) {
      // Sanity check: name shouldn't be > 200 chars
      if (reader.remaining >= 4) reader.readInt32(); // skip trailing pad
      return length == 0 ? '' : null;
    }
    if (reader.remaining < length + 4) return null;
    final bytes = reader.readBytes(length);
    reader.readInt32(); // trailing padding
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return null;
    }
  }
}

// ---------------------------------------------------------------------------
// Minimal binary reader for blob format (Little-Endian, 4-byte padding)
// ---------------------------------------------------------------------------
class _BinaryReader {
  final ByteData _view;
  int _offset;
  final int _length;

  _BinaryReader(Uint8List buffer)
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

  int peekUInt32() {
    if (remaining < 4) return 0;
    return _view.getUint32(_offset, Endian.little);
  }

  int readUInt32() {
    if (remaining < 4) throw Exception("EndOfStream");
    final value = _view.getUint32(_offset, Endian.little);
    _offset += 4;
    return value;
  }

  int readInt32() {
    if (remaining < 4) throw Exception("EndOfStream");
    final value = _view.getInt32(_offset, Endian.little);
    _offset += 4;
    return value;
  }

  /// Read int64 (8 bytes LE). Blob format: advances 8 data bytes (no implicit padding here;
  /// caller is responsible for reading the 4-byte padding after).
  Int64 readInt64() {
    if (remaining < 8) throw Exception("EndOfStream");
    final lo = _view.getUint32(_offset, Endian.little);
    final hi = _view.getUint32(_offset + 4, Endian.little);
    _offset += 8;
    return (Int64(hi) << 32) | Int64(lo);
  }

  Uint8List readBytes(int length) {
    if (remaining < length) throw Exception("EndOfStream");
    final bytes = Uint8List.view(_view.buffer, _view.offsetInBytes + _offset, length);
    _offset += length;
    return bytes;
  }
}
