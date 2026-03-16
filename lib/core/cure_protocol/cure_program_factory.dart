import 'dart:convert';
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

  // Minimal helper to build a single-frequency CureProgram for custom entries.
  // This method is intentionally small and defensive: it creates a CureProgram
  // with a single step (frequencyHz and dwellSeconds) and fills the fields
  // used by uploadProgramAndStart. Adjust field names if your CureProgram
  // constructor differs.
  static CureProgram singleFrequency({
    required String customId,
    required String name,
    required double frequencyHz,
    required Duration duration,
    required int intensityPct, // 0..100
    required bool powerMode,
    required bool useElectric,
    required String electricWaveform,
    required bool useMagnetic,
    required String magneticWaveform,
  }) {
    // Normalize intensity to expected internal nibbles/flags if needed.
    final intBase = (intensityPct / 10.0).round().clamp(0, 10);
    final eNibble = useElectric ? intBase : 0;
    final hNibble = useMagnetic ? intBase : 0;

    // Map waveform strings to enum/values used in CureProgram.
    CureWaveForm _parseWave(String w) {
      final n = w.toLowerCase().trim();
      if (n.contains('sine')) return CureWaveForm.sine;
      if (n.contains('triangle')) return CureWaveForm.triangle;
      if (n.contains('square') || n.contains('rect') || n.contains('rectangle')) return CureWaveForm.square;
      if (n.contains('saw')) return CureWaveForm.sawtooth;
      return CureWaveForm.sine;
    }

    final eWave = _parseWave(electricWaveform);
    final hWave = _parseWave(magneticWaveform);

    // Build a single-step list. Ensure dwell is an int between 1 and 65535.
    int dwell = duration.inSeconds;
    if (dwell < 1) dwell = 1;
    if (dwell > 65535) dwell = 65535;

    final step = CureFrequencyStep(
      frequencyHz: frequencyHz,
      dwellSeconds: dwell,
    );

    // Construct CureProgram using the proper constructor fields.
    final uuid16 = _uuid16FromString('custom:$customId');
    final cp = CureProgram(
      programUuid16: uuid16,
      name: name,
      intensity: CureIntensity(eNibble: eNibble, hNibble: hNibble),
      waveForms: CureWaveForms(e: eWave, h: hWave),
      steps: [step],
    );

    return cp;
  }

  // Helper: produce a deterministic 16-byte id from an arbitrary string.
  // Uses two FNV-1a 64-bit hashes (different seeds) and concatenates them
  // as little-endian 8-byte words to produce a pseudo-UUID16. This is purely
  // deterministic and avoids pulling in UUID libraries or network calls.
  static Uint8List _uuid16FromString(String s) {
    // BigInt-based FNV-1a 64-bit implementation (web-safe)
    BigInt fnv1a64(List<int> bytes, BigInt seed) {
      final BigInt fnvPrime = BigInt.parse('100000001b3', radix: 16);
      final BigInt mask64 = BigInt.parse('FFFFFFFFFFFFFFFF', radix: 16);
      BigInt hash = seed & mask64;
      for (final b in bytes) {
        hash = (hash ^ BigInt.from(b));
        hash = (hash * fnvPrime) & mask64;
      }
      return hash;
    }

    final bytes = utf8.encode(s);
    final h1 = fnv1a64(bytes, BigInt.parse('cbf29ce484222325', radix: 16));
    final h2 = fnv1a64(bytes, BigInt.parse('84222325cbf29ce4', radix: 16));

    final out = ByteData(16);
    // write little-endian 8 bytes from BigInt values
    for (int i = 0; i < 8; i++) {
      out.setUint8(i, ((h1 >> (8 * i)) & BigInt.from(0xFF)).toInt());
    }
    for (int i = 0; i < 8; i++) {
      out.setUint8(8 + i, ((h2 >> (8 * i)) & BigInt.from(0xFF)).toInt());
    }
    return out.buffer.asUint8List();
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
