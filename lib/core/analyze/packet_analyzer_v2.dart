import 'dart:typed_data';

import '../services/logger_service.dart';
import '../state/data_storage.dart';
import 'message_analyzer_v2.dart';

class PacketAnalyzerV2 {
  final BytesBuilder _buffer = BytesBuilder();
  final MessageAnalyzerV2 _messageAnalyzer;
  final LoggerService _logger = LoggerService();
  final String tag;

  PacketAnalyzerV2(DataStorage storage, {this.tag = 'game'}) 
      : _messageAnalyzer = MessageAnalyzerV2(storage, tag: tag);

  void processPacket(Uint8List chunk) {
    // Detect reset marker (0xFFFFFFFF) sent by Kotlin when port 5003 session changes.
    // The marker can appear at the beginning of a chunk.
    if (chunk.length >= 4) {
      final marker = ByteData.sublistView(chunk, 0, 4).getUint32(0, Endian.big);
      if (marker == 0xFFFFFFFF) {
        _buffer.clear();
        if (chunk.length > 4) {
          _buffer.add(chunk.sublist(4));
          _drainBuffer();
        }
        return;
      }
    }
    _buffer.add(chunk);
    _drainBuffer();
  }

  /// Clear the internal reassembly buffer (e.g. when the upstream "other" session changes).
  void clearBuffer() {
    _buffer.clear();
  }

  /// Drain fully-received packets from the internal buffer.
  void _drainBuffer() {
    while (true) {
      final bytes = _buffer.toBytes();
      if (bytes.length < 4) break;

      final packetSize = ByteData.sublistView(bytes, 0, 4).getUint32(0, Endian.big);

      // Detect server signature at buffer head: first 4 bytes == 0x00633353
      // Full signature is 6 bytes: 00 63 33 53 42 00
      // This marks the start of the authenticated game protocol stream.
      // Entity data (monsters, boss) arrives BEFORE this signature, so we
      // must NOT clear monsters here — just skip the 6 signature bytes.
      if (packetSize == 0x00633353) {
        if (bytes.length >= 6) {
          final remaining = bytes.sublist(6);
          _buffer.clear();
          _buffer.add(remaining);
          continue;
        } else {
          break; // Wait for more data
        }
      }

      if (packetSize < 4 || packetSize > 10000000) {
        _logger.log("Invalid packet size: $packetSize (0x${packetSize.toRadixString(16)}). "
            "Buffer len: ${bytes.length}. Clearing buffer.");
        _buffer.clear();
        break;
      }

      if (bytes.length < packetSize) {
        // Log when waiting for data (only for non-tiny waits)
          break; // Wait for more data
      }

      final packetBody = bytes.sublist(4, packetSize);

      final remaining = bytes.sublist(packetSize);
      _buffer.clear();
      _buffer.add(remaining);

      try {
        _messageAnalyzer.process(packetBody);
      } catch (e) {
        _logger.error("Error processing packet", error: e);
      }
    }
  }
}
