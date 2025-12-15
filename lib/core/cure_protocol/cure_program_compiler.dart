import 'dart:typed_data';

import 'cure_crc32.dart';
import 'cure_program_model.dart';

class CureInstructionId {
  static const int end = 0x00;
  static const int program = 0x01;
  static const int frequency = 0x02;
  static const int programId = 0x03;
  static const int waveForm = 0x04;
  static const int customName = 0x05;
}

/// Interner Helper zum Schreiben von Little-Endian-Daten.
class _ByteSink {
  final BytesBuilder _builder = BytesBuilder();

  void writeU8(int value) {
    _builder.addByte(value & 0xFF);
  }

  void writeU16LE(int value) {
    _builder.add([
      value & 0xFF,
      (value >> 8) & 0xFF,
    ]);
  }

  void writeU32LE(int value) {
    _builder.add([
      value & 0xFF,
      (value >> 8) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 24) & 0xFF,
    ]);
  }

  void writeF32LE(double value) {
    final bd = ByteData(4);
    bd.setFloat32(0, value, Endian.little);
    _builder.add(bd.buffer.asUint8List());
  }

  void writeBytes(List<int> bytes) {
    _builder.add(bytes);
  }

  Uint8List toBytes() => _builder.toBytes();
}

/// Compiler, der aus einem [CureProgram] das exakt erwartete
/// Binärformat der Firmware erzeugt.
///
/// Layout:
///   [0x03][u32 programLen][u32 crc32] + payload
/// payload:
///   [0x01 program] [0x04 waveForm] [0x05 customName] [0x02 frequency*] [0x00 end]
class CureProgramCompiler {
  Uint8List compile(CureProgram program) {
    // 1. Payload zusammenbauen.
    final payloadSink = _ByteSink();

    _writeProgramInstruction(payloadSink, program);
    _writeWaveFormInstruction(payloadSink, program.waveForms);
    _writeCustomNameInstruction(payloadSink, program.name);
    _writeFrequencyInstructions(payloadSink, program.steps);
    _writeEndInstruction(payloadSink);

    final payload = payloadSink.toBytes();

    // 2. CRC32 über Payload.
    final crc = CureCrc32.compute(payload);

    // 3. programId-Header davor.
    final fullSink = _ByteSink();
    fullSink.writeU8(CureInstructionId.programId);
    fullSink.writeU32LE(payload.length); // programLen
    fullSink.writeU32LE(crc); // CRC32

    // 4. Payload anhängen.
    fullSink.writeBytes(payload);

    return fullSink.toBytes();
  }

  void _writeProgramInstruction(_ByteSink sink, CureProgram program) {
    sink.writeU8(CureInstructionId.program);

    if (program.programUuid16.length != 16) {
      throw ArgumentError('programUuid16 must be exactly 16 bytes');
    }
    sink.writeBytes(program.programUuid16);

    // 4-Bit Intensitäten (0..15) wie in Programs.cpp.
    final eNibble = program.intensity.eNibble.clamp(0, 15);
    final hNibble = program.intensity.hNibble.clamp(0, 15);
    final packed = ((eNibble << 4) & 0xF0) | (hNibble & 0x0F);
    sink.writeU8(packed);
  }

  void _writeWaveFormInstruction(_ByteSink sink, CureWaveForms wf) {
    sink.writeU8(CureInstructionId.waveForm);

    final eCode = _encodeWaveForm(wf.e);
    final hCode = _encodeWaveForm(wf.h);
    final packed = ((eCode << 4) & 0xF0) | (hCode & 0x0F);
    sink.writeU8(packed);
  }

  int _encodeWaveForm(CureWaveForm wf) {
    switch (wf) {
      case CureWaveForm.sine:
        return 0;
      case CureWaveForm.square:
        return 1;
      case CureWaveForm.triangle:
        return 2;
      case CureWaveForm.sawtooth:
        return 3;
    }
  }

  void _writeCustomNameInstruction(_ByteSink sink, String name) {
    final bytes = name.codeUnits; // Legacy: raw Bytes, keine Base64
    if (bytes.length > 255) {
      throw ArgumentError('Program name too long (max 255 bytes)');
    }

    sink.writeU8(CureInstructionId.customName);
    sink.writeU8(bytes.length);
    sink.writeBytes(bytes);
  }

  void _writeFrequencyInstructions(
    _ByteSink sink,
    List<CureFrequencyStep> steps,
  ) {
    for (final step in steps) {
      sink.writeU8(CureInstructionId.frequency);
      sink.writeF32LE(step.frequencyHz);
      sink.writeU16LE(step.dwellSeconds);
    }
  }

  void _writeEndInstruction(_ByteSink sink) {
    sink.writeU8(CureInstructionId.end);
  }
}

