import 'dart:convert';
import 'dart:typed_data';

const int kInstrEnd = 0x00;
const int kInstrProgram = 0x01;
const int kInstrFrequency = 0x02;
const int kInstrProgramId = 0x03;
const int kInstrWaveForm = 0x04;
const int kInstrCustomName = 0x05;

Uint8List encodeQtProgramBytes({
  required Uint8List uuid16,
  required String name,
  required int eIntensity0to10,
  required int hIntensity0to10,
  required int eWaveForm,
  required int hWaveForm,
  required List<({double freqHz, int dwellSec})> steps,
}) {
  if (uuid16.length != 16) {
    throw ArgumentError('uuid16 must be exactly 16 bytes');
  }

  final stream = BytesBuilder(copy: false);

  // INSTRUCTIN_programm (0x01)
  stream.addByte(kInstrProgram);
  stream.add(uuid16);
  final eNib = _clamp0to10(eIntensity0to10);
  final hNib = _clamp0to10(hIntensity0to10);
  stream.addByte(((hNib & 0x0F) << 4) | (eNib & 0x0F));

  // INSTRUCTIN_waveForm (0x04)
  stream.addByte(kInstrWaveForm);
  stream.addByte(((hWaveForm & 0x0F) << 4) | (eWaveForm & 0x0F));

  // INSTRUCTIN_customName (0x05)
  final nameBytes = utf8.encode(name);
  if (nameBytes.length > 255) {
    throw ArgumentError('name too long (>255 bytes UTF-8)');
  }
  stream.addByte(kInstrCustomName);
  stream.addByte(nameBytes.length);
  stream.add(nameBytes);

  // INSTRUCTIN_frequency (0x02)
  for (final step in steps) {
    stream.addByte(kInstrFrequency);
    final bd = ByteData(6);
    bd.setFloat32(0, step.freqHz, Endian.little);
    bd.setUint16(4, step.dwellSec & 0xFFFF, Endian.little);
    stream.add(bd.buffer.asUint8List());
  }

  // INSTRUCTIN_end (0x00)
  stream.addByte(kInstrEnd);

  final programStream = stream.toBytes();
  final programLen = programStream.length;

  // CRC32 calculation
  final programId = _mzCrc32(programStream);

  // INSTRUCTIN_programId (0x03)
  final header = BytesBuilder(copy: false);
  header.addByte(kInstrProgramId);
  final hd = ByteData(8);
  hd.setUint32(0, programLen, Endian.little);
  hd.setUint32(4, programId, Endian.little);
  header.add(hd.buffer.asUint8List());

  header.add(programStream);
  return header.toBytes();
}

int _clamp0to10(int v) => v < 0 ? 0 : (v > 10 ? 10 : v);

int _mzCrc32(Uint8List data) {
  const poly = 0xEDB88320;
  final table = List<int>.generate(256, (i) {
    var c = i;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? (poly ^ (c >>> 1)) : (c >>> 1);
    }
    return c & 0xFFFFFFFF;
  });

  var crc = 0xFFFFFFFF;
  for (final b in data) {
    crc = table[(crc ^ b) & 0xFF] ^ (crc >>> 8);
  }
  return crc ^ 0xFFFFFFFF;
}
