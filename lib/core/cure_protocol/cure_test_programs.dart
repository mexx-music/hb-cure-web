import 'dart:typed_data';

import 'package:hbcure/core/cure_protocol/cure_program_model.dart';

/// Helper factory functions for simple test CurePrograms used in development/tests.
CureProgram buildSimpleTestProgram() {
  final uuid = Uint8List.fromList(List<int>.generate(16, (i) => i + 1));

  return CureProgram(
    programUuid16: uuid,
    name: 'Test 1 kHz / 60s',
    intensity: CureIntensity(eNibble: 5, hNibble: 3),
    waveForms: CureWaveForms(e: CureWaveForm.sine, h: CureWaveForm.square),
    steps: [CureFrequencyStep(frequencyHz: 1000.0, dwellSeconds: 60)],
  );
}

