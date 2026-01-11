import 'dart:typed_data';
import 'dart:convert';
import 'package:protobuf/protobuf.dart';

class AttrParser {
  static dynamic parse(int id, List<int> rawData) {
    if (rawData.isEmpty) return null;
    final bytes = Uint8List.fromList(rawData);
    
    // Attempt to use CodedBufferReader for complex types that are likely Protobuf messages
    if (id == 52 || id == 374) {
      try {
        final reader = CodedBufferReader(rawData);
        double x = 0, y = 0, z = 0, w = 0;
        
        while (!reader.isAtEnd()) {
          final tag = reader.readTag();
          final fieldNum = getTagFieldNumber(tag);
          
          if (fieldNum == 0) break; // Should not happen in valid proto
          
          switch (fieldNum) {
            case 1:
              x = reader.readFloat();
              break;
            case 2:
              y = reader.readFloat();
              break;
            case 3:
              z = reader.readFloat();
              break;
            case 4: 
              w = reader.readFloat(); // For Rotation (Quaternion)
              break;
            default:
              reader.skipField(tag);
              break;
          }
        }
        
        if (id == 52) {
          return {'x': x, 'y': y, 'z': z};
        } else {
          return {'x': x, 'y': y, 'z': z, 'w': w};
        }

      } catch (e) {
        // Fallback to raw incorrect parsing if proto fails (unlikely if it's proto)
        // Or maybe it IS raw but with offset? 
        // Let's stick to Proto first as it matches the "Garbage Billions" symptom best.
      }
    }

    final buffer = bytes.buffer;
    final data = ByteData.view(buffer);

    switch (id) {
      // 52 and 374 removed from here as they are handled above
      case 11310: // AttrHp
      case 11320: // AttrMaxHp
        // Try reading as Varint first if size is small/odd, or just prioritize Varint reading
        // The previous strict size check failed for varints.
        try {
           final reader = CodedBufferReader(rawData);
           return reader.readInt64();
        } catch (_) {
           // Fallback to Fixed Little Endian if Varint fails or looks wrong?
        }
        
        if (bytes.length == 8) {
           return data.getInt64(0, Endian.little);
        }
        if (bytes.length == 4) {
           return data.getInt32(0, Endian.little);
        }
        
        // If neither, return 0 or null?
        return 0;
      case 1: // AttrName
        try {
            return utf8.decode(bytes);
        } catch (e) {
            return String.fromCharCodes(bytes);
        }
      default:
        // Generic fallback
        return rawData;
    }
  }
}
