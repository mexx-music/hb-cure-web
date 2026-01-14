// Composite program payload types for Qt-compatible upload

import 'dart:typed_data';

/// One frequency step in the program payload.
/// freqHz: frequency in Hz (double)
/// dwellSec: dwell time in seconds (int)
class CompositeStep {
  final double freqHz;
  final int dwellSec;

  const CompositeStep({required this.freqHz, required this.dwellSec});

  Map<String, Object> toJson() => {'freqHz': freqHz, 'dwellSec': dwellSec};

  @override
  String toString() => 'CompositeStep(freqHz: $freqHz, dwellSec: $dwellSec)';
}

/// Immutable payload describing one program to be encoded in Qt format.
/// uuid16 must be exactly 16 bytes (UUID v4 / 128-bit) used by the firmware.
class CompositeItemPayload {
  /// Exactly 16 bytes UUID (raw bytes) expected by the encoder.
  final Uint8List uuid16;

  /// Human-readable program name (used for metadata / logs only).
  final String name;

  /// Intensities: expected 0..10 (4-bit nibble each)
  final int eInt0to10;
  final int hInt0to10;

  /// Waveform ids: expected 0..15 (4-bit each)
  final int eWave0to15;
  final int hWave0to15;

  /// Frequency steps making up the program body.
  final List<CompositeStep> steps;

  const CompositeItemPayload({
    required this.uuid16,
    required this.name,
    required this.eInt0to10,
    required this.hInt0to10,
    required this.eWave0to15,
    required this.hWave0to15,
    required this.steps,
  }) : assert(uuid16.length == 16, 'uuid16 must be exactly 16 bytes');

  Map<String, Object?> toJson() => {
    'uuid16': uuid16,
    'name': name,
    'eInt0to10': eInt0to10,
    'hInt0to10': hInt0to10,
    'eWave0to15': eWave0to15,
    'hWave0to15': hWave0to15,
    'steps': steps.map((s) => s.toJson()).toList(),
  };

  @override
  String toString() =>
      'CompositeItemPayload(name: $name, uuid16(len=${uuid16.length}), eInt=$eInt0to10, hInt=$hInt0to10, eWave=$eWave0to15, hWave=$hWave0to15, steps=${steps.length})';
}
