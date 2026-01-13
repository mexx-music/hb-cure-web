// New playlist item settings model with waveform support

enum Waveform {
  sine,
  triangle,
  rectangle,
  sawtooth,
}

class PlaylistItemSettings {
  final int durationMinutes;
  final int intensity;

  final bool electric;
  final Waveform electricWaveform;

  final bool magnetic;
  final Waveform magneticWaveform;

  const PlaylistItemSettings({
    required this.durationMinutes,
    required this.intensity,
    required this.electric,
    required this.electricWaveform,
    required this.magnetic,
    required this.magneticWaveform,
  });

  static const defaults = PlaylistItemSettings(
    durationMinutes: 15,
    intensity: 100,
    electric: true,
    electricWaveform: Waveform.sine,
    magnetic: true,
    magneticWaveform: Waveform.sine,
  );

  PlaylistItemSettings copyWith({
    int? durationMinutes,
    int? intensity,
    bool? electric,
    Waveform? electricWaveform,
    bool? magnetic,
    Waveform? magneticWaveform,
  }) {
    return PlaylistItemSettings(
      durationMinutes: durationMinutes ?? this.durationMinutes,
      intensity: intensity ?? this.intensity,
      electric: electric ?? this.electric,
      electricWaveform: electricWaveform ?? this.electricWaveform,
      magnetic: magnetic ?? this.magnetic,
      magneticWaveform: magneticWaveform ?? this.magneticWaveform,
    );
  }
}

