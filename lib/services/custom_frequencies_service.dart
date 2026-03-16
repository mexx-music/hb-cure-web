import 'package:flutter/foundation.dart';

class CustomFrequencyEntry {
  final String id;
  final String name;
  final double frequencyHz;
  final int durationMin;
  final int intensityPct;
  final bool useElectric;
  final String electricWaveform;
  final bool useMagnetic;
  final String magneticWaveform;

  const CustomFrequencyEntry({
    required this.id,
    required this.name,
    required this.frequencyHz,
    required this.durationMin,
    required this.intensityPct,
    required this.useElectric,
    required this.electricWaveform,
    required this.useMagnetic,
    required this.magneticWaveform,
  });

  CustomFrequencyEntry copyWith({
    String? name,
    double? frequencyHz,
    int? durationMin,
    int? intensityPct,
    bool? useElectric,
    String? electricWaveform,
    bool? useMagnetic,
    String? magneticWaveform,
  }) {
    return CustomFrequencyEntry(
      id: id,
      name: name ?? this.name,
      frequencyHz: frequencyHz ?? this.frequencyHz,
      durationMin: durationMin ?? this.durationMin,
      intensityPct: intensityPct ?? this.intensityPct,
      useElectric: useElectric ?? this.useElectric,
      electricWaveform: electricWaveform ?? this.electricWaveform,
      useMagnetic: useMagnetic ?? this.useMagnetic,
      magneticWaveform: magneticWaveform ?? this.magneticWaveform,
    );
  }
}

class CustomFrequenciesService extends ChangeNotifier {
  static final CustomFrequenciesService instance = CustomFrequenciesService._();
  CustomFrequenciesService._();

  final List<CustomFrequencyEntry> _items = [];

  List<CustomFrequencyEntry> get items => List.unmodifiable(_items);

  CustomFrequencyEntry? getById(String id) {
    for (final e in _items) {
      if (e.id == id) return e;
    }
    return null;
  }

  void upsert(CustomFrequencyEntry entry) {
    final idx = _items.indexWhere((e) => e.id == entry.id);
    if (idx >= 0) {
      _items[idx] = entry;
    } else {
      _items.insert(0, entry);
    }
    notifyListeners();
  }

  void removeById(String id) {
    _items.removeWhere((e) => e.id == id);
    notifyListeners();
  }
}
