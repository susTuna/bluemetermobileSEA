import 'dart:typed_data';

import '../services/logger_service.dart';
import '../state/data_storage.dart';
import 'message_analyzer_v2.dart';

class PacketAnalyzerV2 {
  final BytesBuilder _buffer = BytesBuilder();
  final MessageAnalyzerV2 _messageAnalyzer;
  final LoggerService _logger = LoggerService();
  final DataStorage _storage;

  PacketAnalyzerV2(DataStorage storage) 
      : _storage = storage,
        _messageAnalyzer = MessageAnalyzerV2(storage);

  void processPacket(Uint8List chunk) {
    _buffer.add(chunk);
    _drainBuffer();
  }

  /// Drain fully-received packets from the internal buffer.
  void _drainBuffer() {
    while (true) {
      final bytes = _buffer.toBytes();
      if (bytes.length < 4) break;

      final packetSize = ByteData.sublistView(bytes, 0, 4).getUint32(0, Endian.big);

      // Detect handshake at buffer head: first 4 bytes == 0x00633353
      // Full signature is 6 bytes: 00 63 33 53 42 00
      if (packetSize == 0x00633353) {
        _logger.log("Handshake detected — new session. Skipping 6 bytes.");
        if (bytes.length >= 6) {
          final remaining = bytes.sublist(6);
          _buffer.clear();
          _buffer.add(remaining);
          _storage.clearMonsters();
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
