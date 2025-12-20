// lib/core/cure_protocol/cure_program_compiler.dart

import 'dart:typed_data';
import 'dart:convert';
import 'package:hbcure/core/cure_protocol/cure_program_model.dart';

class CureProgramCompiler {
  Uint8List compile(CureProgram program) {
    // Qt-kompatibel: uuid16 muss 16 Bytes sein
    if (program.uuid16.length != 16) {
      throw ArgumentError('program.uuid16 must be exactly 16 bytes');
    }

    final programStream = BytesBuilder(copy: false);

    // Instruction: Program (0x01)
    programStream.add([0x01]);
    programStream.add(program.uuid16);

    // Qt-kompatibel: Intensities clamp 0..10 (nicht nur &0x0F)
    final eNib = _clamp0to10(program.eIntensity0to10);
    final hNib = _clamp0to10(program.hIntensity0to10);
    programStream.add([((hNib & 0x0F) << 4) | (eNib & 0x0F)]);

    // Instruction: Waveform (0x04)
    programStream.add([0x04]);
    programStream.add([
      (program.eWaveForm & 0x0F) | ((program.hWaveForm & 0x0F) << 4)
    ]);

    // Instruction: Custom Name (0x05)
    final nameBytes = utf8.encode(program.name);
    // Qt-kompatibel: NameLen ist 1 Byte
    if (nameBytes.length > 255) {
      throw ArgumentError('program.name too long (>255 bytes UTF-8)');
    }
    programStream.add([0x05, nameBytes.length]);
    programStream.add(nameBytes);

    // Steps
    for (final step in program.steps) {
      programStream.add([0x02]);
      programStream.add(_float32ToBytes(step.freqHz));
      programStream.add(_uint16ToBytes(step.dwellSec));
    }

    // Instruction: End (0x00)
    programStream.add([0x00]);

    // Program payload
    final programBytes = programStream.toBytes();
    final programLen = programBytes.length;

    // CRC32 over program stream
    final programId = _mzCrc32(programBytes);

    // Header: ProgramId (0x03) — Qt-kompatibel:
    // 0x03 + 8 bytes header:
    //   uint32(programLen) @0
    //   uint32(programId)  @4
    final header = BytesBuilder(copy: false);
    header.add([0x03]);

    final hd = ByteData(8);
    hd.setUint32(0, programLen, Endian.little);
    hd.setUint32(4, programId, Endian.little);

    header.add(hd.buffer.asUint8List());
    header.add(programBytes);

    return header.toBytes();
  }

  int _clamp0to10(int v) => v < 0 ? 0 : (v > 10 ? 10 : v);

  Uint8List _float32ToBytes(double value) {
    final byteData = ByteData(4);
    byteData.setFloat32(0, value, Endian.little);
    return byteData.buffer.asUint8List();
  }

  Uint8List _uint16ToBytes(int value) {
    final byteData = ByteData(2);
    byteData.setUint16(0, value & 0xFFFF, Endian.little);
    return byteData.buffer.asUint8List();
  }

  int _mzCrc32(Uint8List data) {
    final table = _crc32Table;
    int crc = 0xFFFFFFFF;

    for (final b in data) {
      crc = table[(crc ^ b) & 0xFF] ^ (crc >>> 8);
    }

    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }

  final List<int> _crc32Table = (() {
    const poly = 0xEDB88320;
    final t = List<int>.filled(256, 0);
    for (int i = 0; i < 256; i++) {
      int c = i;
      for (int k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? (poly ^ (c >>> 1)) : (c >>> 1);
      }
      t[i] = c & 0xFFFFFFFF;
    }
    return t;
  })();
}
