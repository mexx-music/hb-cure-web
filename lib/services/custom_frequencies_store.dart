import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class CustomFrequenciesStore {
  static const _key = 'custom_freq_entries_v1';
  static final CustomFrequenciesStore instance = CustomFrequenciesStore._();
  CustomFrequenciesStore._();

  Future<List<CustomFrequencyEntry>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return list.map(CustomFrequencyEntry.fromJson).toList(growable: false);
  }

  Future<void> saveAll(List<CustomFrequencyEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(entries.map((e) => e.toJson()).toList());
    await prefs.setString(_key, raw);
  }

  Future<CustomFrequencyEntry?> getById(String id) async {
    final all = await loadAll();
    for (final e in all) {
      if (e.id == id) return e;
    }
    return null;
  }

  Future<void> upsert(CustomFrequencyEntry entry) async {
    final all = (await loadAll()).toList(growable: true);
    final idx = all.indexWhere((e) => e.id == entry.id);
    if (idx >= 0) {
      all[idx] = entry;
    } else {
      all.insert(0, entry);
    }
    await saveAll(all);
  }

  Future<void> remove(String id) async {
    final all = (await loadAll()).toList(growable: true);
    all.removeWhere((e) => e.id == id);
    await saveAll(all);
  }
}

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

  Map<String, dynamic> toJson() => {
        "id": id,
        "name": name,
        "frequencyHz": frequencyHz,
        "durationMin": durationMin,
        "intensityPct": intensityPct,
        "useElectric": useElectric,
        "electricWaveform": electricWaveform,
        "useMagnetic": useMagnetic,
        "magneticWaveform": magneticWaveform,
      };

  static CustomFrequencyEntry fromJson(Map<String, dynamic> j) => CustomFrequencyEntry(
        id: j["id"] as String,
        name: j["name"] as String,
        frequencyHz: (j["frequencyHz"] as num).toDouble(),
        durationMin: (j["durationMin"] as num).toInt(),
        intensityPct: (j["intensityPct"] as num).toInt(),
        useElectric: j["useElectric"] as bool? ?? true,
        electricWaveform: j["electricWaveform"] as String? ?? "sine",
        useMagnetic: j["useMagnetic"] as bool? ?? true,
        magneticWaveform: j["magneticWaveform"] as String? ?? "sine",
      );
}

