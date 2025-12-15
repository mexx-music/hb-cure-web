import 'dart:typed_data';

/// CRC32 Implementierung, kompatibel zu zlib / miniz (mz_crc32).
///
/// Wichtig: Initialwert = 0 (wie mz_crc32(0, data, len)).
class CureCrc32 {
  static const int _polynomial = 0xEDB88320;
  static final List<int> _table = _createTable();

  static List<int> _createTable() {
    final table = List<int>.filled(256, 0);
    for (int i = 0; i < 256; i++) {
      int c = i;
      for (int j = 0; j < 8; j++) {
        if ((c & 1) != 0) {
          c = _polynomial ^ (c >>> 1);
        } else {
          c = c >>> 1;
        }
      }
      table[i] = c;
    }
    return table;
  }

  static int compute(Uint8List data) {
    int crc = 0; // WICHTIG: 0, nicht 0xFFFFFFFF
    for (final b in data) {
      final index = (crc ^ b) & 0xFF;
      crc = _table[index] ^ (crc >>> 8);
    }
    return crc & 0xFFFFFFFF;
  }
}

