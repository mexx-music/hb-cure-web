// lib/i18n/program_name_localizer.dart
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

class ProgramNameLocalizer {
  ProgramNameLocalizer._();
  static final ProgramNameLocalizer instance = ProgramNameLocalizer._();

  bool _loaded = false;
  final Map<String, String> _enToDe = HashMap<String, String>();
  // DE -> EN fallback map (populated alongside EN->DE)
  final Map<String, String> _deToEn = HashMap<String, String>();

  /// Loads the CSV once.
  /// Asset path must match pubspec.yaml exactly.
  Future<void> ensureLoaded() async {
    if (_loaded) return;

    final csvText =
        await rootBundle.loadString('assets/program_names_DE_EN.csv');
    debugPrint('ProgramNameLocalizer: CSV loaded chars=${csvText.length}');

    final lines = csvText.split(RegExp(r'\r?\n'));
    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) continue;

      // Skip header ("DE;EN" or "DE,EN")
      final lower = line.toLowerCase();
      if (lower == 'de;en' || lower == 'de,en') continue;

      // Your CSV uses semicolon, but keep comma as fallback.
      final idx = line.contains(';') ? line.indexOf(';') : line.indexOf(',');
      if (idx <= 0) continue;

      final de = _unquote(line.substring(0, idx).trim());
      final en = _unquote(line.substring(idx + 1).trim());

      final enKey = en.trim();
      if (enKey.isEmpty) continue;

      final deVal = de.isEmpty ? enKey : de.trim();
      _enToDe[enKey] = deVal;
      // populate reverse mapping for cases where the UI provides DE but we need EN
      if (deVal.isNotEmpty && deVal != enKey) {
        _deToEn[deVal] = enKey;
      }
    }

    _loaded = true;
    debugPrint('ProgramNameLocalizer: map size=${_enToDe.length}');
    debugPrint("ProgramNameLocalizer: test('Seven Chakras') => '${_enToDe['Seven Chakras']}'");
  }

  /// Returns display name for the given EN key.
  /// - langCode: 'de' shows DE if available; otherwise falls back to EN.
  /// - any other langCode returns EN key.
  String displayName({
    required String keyEn,
    required String langCode, // 'de' | 'en'
  }) {
    final key = keyEn.trim();

    if (langCode.toLowerCase() == 'en') {
      return _deToEn[key] ?? key;
    }
    return _enToDe[key] ?? key;
  }

  String _unquote(String s) {
    if (s.length >= 2 &&
        ((s.startsWith('"') && s.endsWith('"')) ||
            (s.startsWith("'") && s.endsWith("'")))) {
      return s.substring(1, s.length - 1);
    }
    return s;
  }
}
