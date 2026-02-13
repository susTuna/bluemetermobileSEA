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

    while (true) {
      final bytes = _buffer.toBytes();
      if (bytes.length < 4) break; // Need at least size header

      // Peek packet size (first 4 bytes)
      final packetSize = ByteData.sublistView(bytes, 0, 4).getUint32(0, Endian.big);

      // Check for handshake signature (00 63 33 53) which is 6499155
      if (packetSize == 0x00633353) {
        _logger.log("Handshake detected (00 63 33 53) — new connection/line.");
        if (bytes.length >= 6) {
          final remaining = bytes.sublist(6);
          _buffer.clear();
          _buffer.add(remaining);
          // Signal potential scene change — entities will be refreshed by SyncContainerData
          _storage.clearMonsters();
          continue;
        } else {
          break; // Wait for more data
        }
      }

      if (packetSize < 4 || packetSize > 10000000) {
        _logger.log("Invalid packet size: $packetSize. Buffer len: ${bytes.length}. Clearing buffer.");
        _buffer.clear();
        break;
      }

      // Check if we have the full packet
      if (bytes.length < packetSize) {
        break; // Wait for more data
      }

      // Extract the full packet body (excluding size header)
      // MessageAnalyzerV2 expects the body (Type + Payload)
      final packetBody = bytes.sublist(4, packetSize);

      // Remove processed bytes from buffer
      final remaining = bytes.sublist(packetSize);
      _buffer.clear();
      _buffer.add(remaining);

      // Process the extracted packet body
      try {
        _messageAnalyzer.process(packetBody);
      } catch (e) {
        _logger.error("Error processing packet", error: e);
      }
    }
  }
}
