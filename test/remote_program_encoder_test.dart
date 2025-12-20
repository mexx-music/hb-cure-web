import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:hbcure/services/qt_remote_program_encoder.dart';

void main() {
  test('mzCrc32 matches known vector', () {
    final data = Uint8List.fromList('123456789'.codeUnits);
    final crc = _mzCrc32(data);
    // expected 0xCBF43926
    expect(crc, 0xCBF43926);
  });
}

