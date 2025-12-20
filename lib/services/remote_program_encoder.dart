import 'dart:convert';
import 'dart:typed_data';

/// Qt / Firmware compatible instruction IDs (Programs.h)
const int kInstrEnd = 0x00;
const int kInstrProgram = 0x01;
const int kInstrFrequency = 0x02;
const int kInstrProgramId = 0x03;
const int kInstrWaveForm = 0x04;
const int kInstrCustomName = 0x05;

/// Matches CureProgram::WaveForm_t values (Programs.h)
enum QtWaveForm {
  sine(0x00),
  triangle(0x01),
  rectangular(0x02),
  sawTooth(0x03);

  final int v;
  const QtWaveForm(this.v);
}

/// A minimal input model that matches what Programs.cpp actually encodes.
///
/// One "segment" starts with:
///   program(uuid + intensities) + waveform + customName
/// then one or more frequency steps,
/// and final program ends with END instruction.
/// Then header with programLen + CRC32 is prepended (INSTRUCTIN_programId).
class QtRemoteProgram {
  QtRemoteProgram({
    required this.programUuid16,
    required this.name,
    required this.eIntensityNibble0to10,
    required this.hIntensityNibble0to10,
    required this.eWaveForm,
    required this.hWaveForm,
    required this.steps,
  });

  final Uint8List programUuid16; // exactly 16 bytes
  final String name; // UTF-8
  final int eIntensityNibble0to10; // 0..10
  final int hIntensityNibble0to10; // 0..10
  final QtWaveForm eWaveForm;
  final QtWaveForm hWaveForm;

  /// Each step -> one INSTRUCTIN_frequency entry.
  final List<QtFreqStep> steps;
}

class QtFreqStep {
  QtFreqStep({required this.frequencyHz, required this.dwellSeconds});
  final double frequencyHz;
  final int dwellSeconds; // will be cast to uint16 (truncate like C++)
}

/// Build the exact byte stream produced by CureProgramPlaylist::compileProgram()
/// (Programs.cpp), including the INSTRUCTIN_programId header:
///   [0x03][u32 programLen][u32 crc32][programBytes...]
Uint8List encodeQtRemoteProgramBytes(QtRemoteProgram p) {
  if (p.programUuid16.length != 16) {
    throw ArgumentError('programUuid16 must be exactly 16 bytes');
  }

  final program = BytesBuilder(copy: false);

  // --- INSTRUCTIN_programm (0x01): cmd + uuid[16] + 1 byte (E nibble + H nibble)
  program.addByte(kInstrProgram);
  program.add(p.programUuid16);

  final eNib = _clampNibble(p.eIntensityNibble0to10);
  final hNib = _clampNibble(p.hIntensityNibble0to10);

  // Bitfield order in C is compiler dependent. In practice (Qt/Firmware),
  // it's treated as low nibble = E, high nibble = H.
  program.addByte(((hNib & 0x0F) << 4) | (eNib & 0x0F));

  // --- INSTRUCTIN_waveForm (0x04): cmd + 1 byte (E nibble + H nibble)
  program.addByte(kInstrWaveForm);
  final eW = p.eWaveForm.v & 0x0F;
  final hW = p.hWaveForm.v & 0x0F;
  program.addByte(((hW & 0x0F) << 4) | (eW & 0x0F));

  // --- INSTRUCTIN_customName (0x05): cmd + len + bytes
  // Qt: name is UTF-8, len stored in 1 byte.
  final nameBytes = utf8.encode(p.name);
  if (nameBytes.length > 255) {
    // Qt stores length in uint8, so it would overflow; we hard-fail.
    throw ArgumentError('Program name too long (>255 bytes UTF-8)');
  }
  program.addByte(kInstrCustomName);
  program.addByte(nameBytes.length);
  program.add(nameBytes);

  // --- Frequencies: INSTRUCTIN_frequency (0x02): cmd + float32 + uint16 dwelltime
  for (final s in p.steps) {
    program.addByte(kInstrFrequency);

    final bd = ByteData(6);
    bd.setFloat32(0, s.frequencyHz.toDouble(), Endian.little);
    // C++ assigns double -> uint16 (trunc)
    final dwell = s.dwellSeconds & 0xFFFF;
    bd.setUint16(4, dwell, Endian.little);

    program.add(bd.buffer.asUint8List());
  }

  // --- End (0x00)
  program.addByte(kInstrEnd);

  final programBytes = program.toBytes();
  final programLen = programBytes.length;

  // CRC32 exactly like mz_crc32(crc=0, data, len)
  final crc = _mzCrc32(programBytes);

  // Header: INSTRUCTIN_programId (0x03) + u32 len + u32 crc
  final header = BytesBuilder(copy: false);
  header.addByte(kInstrProgramId);

  final hd = ByteData(8);
  hd.setUint32(0, programLen, Endian.little);
  hd.setUint32(4, crc, Endian.little);
  header.add(hd.buffer.asUint8List());

  header.add(programBytes);
  return header.toBytes();
}

int _clampNibble(int v) {
  if (v < 0) return 0;
  if (v > 10) return 10;
  return v;
}

/// zlib/miniz compatible CRC32 (same behavior as mz_crc32).
int _mzCrc32(Uint8List data) {
  // Standard CRC-32 (IEEE) table
  final table = _crc32Table;
  int crc = 0xFFFFFFFF;

  for (final b in data) {
    crc = table[(crc ^ b) & 0xFF] ^ (crc >>> 8);
  }

  crc = crc ^ 0xFFFFFFFF;
  // Ensure uint32
  return crc & 0xFFFFFFFF;
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
