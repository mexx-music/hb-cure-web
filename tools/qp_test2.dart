import 'dart:typed_data';
import '../lib/services/cure_program_compiler.dart';
import '../lib/core/cure_protocol/cure_program_model.dart';

void main() {
  final uuid16 = Uint8List.fromList(List.generate(16, (i) => i + 1));
  final program = CureProgram(
    programUuid16: uuid16,
    name: 'Test 1kHz 60s',
    intensity: CureIntensity(eNibble: 5, hNibble: 3),
    waveForms: CureWaveForms(e: CureWaveForm.sine, h: CureWaveForm.rectangular),
    steps: [CureFrequencyStep(frequencyHz: 1000.0, dwellSeconds: 60)],
  );

  final compiler = CureProgramCompiler();
  final bytes = compiler.compile(program);

  final hdrLen = 1 + 12; // as compiler uses 0x03 + 12 bytes header
  final programLen = bytes[1] | (bytes[2] << 8) | (bytes[3] << 16) | (bytes[4] << 24);
  final first16 = bytes.sublist(hdrLen, hdrLen + 16);
  final first16hex = first16.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  print('UPLOAD first=${bytes.length} hdrLen=$hdrLen programLen=$programLen');
  print('UPLOAD first16=$first16hex');
  print('payload OK: ${bytes.length == hdrLen + programLen}');
}

