import 'package:flutter/foundation.dart';

import 'custom_frequencies_store.dart' as store;

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
  bool _loaded = false;
  Future<void>? _loading;

  List<CustomFrequencyEntry> get items => List.unmodifiable(_items);

  /// Hydrate the in-memory list from the persistent store. Safe to call
  /// multiple times; the first call performs the load and subsequent calls
  /// either await the in-flight future or no-op.
  Future<void> ensureLoaded() {
    if (_loaded) return Future.value();
    return _loading ??= _loadFromStore();
  }

  Future<void> _loadFromStore() async {
    try {
      final persisted = await store.CustomFrequenciesStore.instance.loadAll();
      // Merge: keep any items already added in this session, then add
      // persisted ones that aren't present yet. This preserves entries
      // created before ensureLoaded() finishes.
      final existingIds = _items.map((e) => e.id).toSet();
      for (final p in persisted) {
        if (existingIds.contains(p.id)) continue;
        _items.add(CustomFrequencyEntry(
          id: p.id,
          name: p.name,
          frequencyHz: p.frequencyHz,
          durationMin: p.durationMin,
          intensityPct: p.intensityPct,
          useElectric: p.useElectric,
          electricWaveform: p.electricWaveform,
          useMagnetic: p.useMagnetic,
          magneticWaveform: p.magneticWaveform,
        ));
      }
    } catch (_) {
      // best-effort: leave list as-is on failure
    } finally {
      _loaded = true;
      _loading = null;
      notifyListeners();
    }
  }

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
