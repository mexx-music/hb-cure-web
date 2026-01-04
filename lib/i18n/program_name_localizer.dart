// lib/i18n/program_name_localizer.dart
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

class ProgramNameLocalizer {
  ProgramNameLocalizer._();
  static final ProgramNameLocalizer instance = ProgramNameLocalizer._();

  bool _loaded = false;
  final Map<String, String> _enToDe = HashMap<String, String>();

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

      // Normalize EN key so lookups are tolerant to extra spaces, NBSP and BOM.
      final enKeyRaw = en;
      final enKey = _normKey(enKeyRaw);
      if (enKey.isEmpty) continue;

      final deValRaw = de.trim();
      final deVal = deValRaw.isEmpty ? enKey : _normKey(deValRaw);

      final existing = _enToDe[enKey];

      final isRealDe = deVal.isNotEmpty && deVal != enKey;

      if (existing == null) {
        _enToDe[enKey] = isRealDe ? deVal : enKey;
      } else {
        final existingIsRealDe = existing.isNotEmpty && existing != enKey;
        if (!existingIsRealDe && isRealDe) {
          _enToDe[enKey] = deVal;
        }
      }

      // store lowercase/alternate key for case-insensitive lookup
      final mapped = _enToDe[enKey];
      if (mapped != null) {
        _enToDe[enKey.toLowerCase()] = mapped;
      } else {
        _enToDe[enKey.toLowerCase()] = deVal;
      }
    }

    _loaded = true;
    debugPrint('ProgramNameLocalizer: map size=${_enToDe.length}');
    debugPrint('SANITY Animals => ${_enToDe["Animals"]}');
    debugPrint('SANITY Antiparasitic => ${_enToDe["Antiparasitic"]}');
    debugPrint('SANITY Available Programs => ${_enToDe["Available Programs"]}');
  }

  /// Returns display name for the given EN key.
  /// - langCode: 'de' shows DE if available; otherwise falls back to EN.
  /// - any other langCode returns EN key.
  String displayName({
    required String keyEn,
    required String langCode, // 'de' | 'en'
  }) {
    final key = _normKey(keyEn);

    if (langCode.toLowerCase() != 'de') {
      return keyEn.trim();
    }

    // direct lookup
    final hit = _enToDe[key] ?? _enToDe[key.toLowerCase()];
    if (hit != null) return hit;

    // Fallback: try to match by normalizing stored keys (tolerant matching)
    for (final storedKey in _enToDe.keys) {
      try {
        if (_normKey(storedKey) == key) {
          final found = _enToDe[storedKey];
          if (found != null) {
            debugPrint('ProgramNameLocalizer: fallback matched "$keyEn" -> "$found" (storedKey="$storedKey")');
            return found;
          }
        }
      } catch (_) {}
    }

    // final fallback: return trimmed EN key
    return keyEn.trim();
  }

  String _unquote(String s) {
    if (s.length >= 2 &&
        ((s.startsWith('"') && s.endsWith('"')) ||
            (s.startsWith("'") && s.endsWith("'")))) {
      return s.substring(1, s.length - 1);
    }
    return s;
  }

  String _normKey(String s) {
    // Remove BOM and NBSP, normalize CR, collapse whitespace, remove
    // optional spaces around slashes so "A / B" == "A/ B" etc.
    var t = s.replaceAll('\uFEFF', '') // BOM
        .replaceAll('\u00A0', ' ') // NBSP -> space
        .replaceAll('\r', '')
        .trim();
    // collapse whitespace into single spaces
    t = t.replaceAll(RegExp(r'\s+'), ' ');
    // remove spaces around '/'
    t = t.replaceAll(' / ', '/').replaceAll('/ ', '/').replaceAll(' /', '/');
    return t;
  }
}
