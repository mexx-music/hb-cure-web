import 'dart:typed_data';

/// Waveform-Typen – Namen kannst du später an Qt/Firmware angleichen.
enum CureWaveForm {
  sine,
  square,
  triangle,
  sawtooth,
}

/// Ein einzelner Frequenz-Schritt.
class CureFrequencyStep {
  final double frequencyHz; // z.B. 1000.0
  final int dwellSeconds; // Dauer in Sekunden

  CureFrequencyStep({
    required this.frequencyHz,
    required this.dwellSeconds,
  });
}

/// Intensitäten (E/H) als 0..15-Nibble (intern).
class CureIntensity {
  /// 0..15 (wird im Compiler gekappt).
  final int eNibble;
  final int hNibble;

  CureIntensity({
    required this.eNibble,
    required this.hNibble,
  });
}

/// Waveforms für E- und H-Kanal.
class CureWaveForms {
  final CureWaveForm e;
  final CureWaveForm h;

  CureWaveForms({
    required this.e,
    required this.h,
  });
}

/// Vollständiges Cure-Programm für EIN Programm.
/// (Playlist/mehrere Programme können wir später drumherum bauen.)
class CureProgram {
  /// 16-Byte UUID – muss exakt 16 Bytes lang sein.
  final Uint8List programUuid16;

  /// Anzeigename des Programms (CustomName).
  final String name;

  /// Intensität (als Nibbles, wie in Programs.cpp).
  final CureIntensity intensity;

  /// Waveforms für E/H.
  final CureWaveForms waveForms;

  /// Liste der Frequenzen.
  final List<CureFrequencyStep> steps;

  CureProgram({
    required this.programUuid16,
    required this.name,
    required this.intensity,
    required this.waveForms,
    required this.steps,
  });
}

