import 'dart:typed_data';
import 'dart:convert';

// Use relative import to avoid package resolution issues during standalone run
import '../lib/services/qt_remote_program_encoder.dart';

void main() {
  try {
    // sample program: uuid 1..16, name, intensities, waveforms, one step 1000Hz 60s
    final uuid16 = Uint8List.fromList(List.generate(16, (i) => i + 1));
    final name = 'Test 1kHz 60s';
    final eIntensity = 5;
    final hIntensity = 3;
    final eWave = 0; // sine
    final hWave = 2; // rectangular
    final steps = <({double freqHz, int dwellSec})>[(freqHz: 1000.0, dwellSec: 60)];

    final payload = encodeQtProgramBytes(
      uuid16: uuid16,
      name: name,
      eIntensity0to10: eIntensity,
      hIntensity0to10: hIntensity,
      eWaveForm: eWave,
      hWaveForm: hWave,
      steps: steps,
    );

    final hdrLen = 9;
    // program length is little-endian at payload[1..4]
    int programLen = payload[1] | (payload[2] << 8) | (payload[3] << 16) | (payload[4] << 24);

    final first16 = payload.sublist(hdrLen, hdrLen + 16);
    String first16hex = first16.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    print('payloadLen=${payload.length} hdrLen=$hdrLen programLen=$programLen');
    print('first16=$first16hex');
    print('payload.length == hdrLen + programLen ? ${payload.length == hdrLen + programLen}');
  } catch (e, st) {
    print('ERROR: $e');
    print(st);
  }
}
