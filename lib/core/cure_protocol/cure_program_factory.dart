import 'dart:typed_data';

import 'cure_program_model.dart';

/// Simple factory to build a CureProgram from a catalog JSON entry.
class CureProgramFactory {
  CureProgramFactory._();

  static CureProgram fromCatalogEntry({
    required Map<String, dynamic> entry,
    required Duration duration,
    required bool powerMode,
  }) {
    // 1) UUID
    final uuidHex = entry['ProgramUUID'] as String;
    final uuidBytes = _uuidToBytes(uuidHex);

    // 2) Frequencies -> Steps
    final rawFreqs = entry['Frequencies'];
    final List<dynamic> freqs = (rawFreqs is List) ? rawFreqs : <dynamic>[];
    final steps = <CureFrequencyStep>[];
    if (freqs.isNotEmpty) {
      final perStepDwell = (duration.inSeconds / freqs.length).round().clamp(1, duration.inSeconds);
      for (final f in freqs) {
        if (f is Map) {
          final freqHz = (f['FrequencyHz'] as num?)?.toDouble() ?? (f['frequencyHz'] as num?)?.toDouble() ?? 0.0;
          final dwell = (f['Seconds'] as num?)?.toInt() ?? (f['seconds'] as num?)?.toInt() ?? perStepDwell;
          steps.add(CureFrequencyStep(frequencyHz: freqHz, dwellSeconds: dwell));
        } else if (f is num) {
          steps.add(CureFrequencyStep(frequencyHz: f.toDouble(), dwellSeconds: perStepDwell));
        } else {
          // ignore unknown entry types
        }
      }
    } else {
      // Fallback: single step filling whole duration at 1 kHz
      steps.add(CureFrequencyStep(frequencyHz: 1000.0, dwellSeconds: duration.inSeconds));
    }

    return CureProgram(
      programUuid16: uuidBytes,
      name: entry['Program']?['EN'] ?? 'Program',
      intensity: CureIntensity(eNibble: 5, hNibble: 5),
      waveForms: CureWaveForms(
        e: CureWaveForm.sine,
        h: CureWaveForm.sine,
      ),
      steps: steps,
    );
  }

  static Uint8List _uuidToBytes(String uuid) {
    final hex = uuid.replaceAll('-', '');
    final bytes = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(bytes);
  }
}
