import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:hbcure/services/program_language_controller.dart';

class ProgramCatalog {
  ProgramCatalog._();
  static final ProgramCatalog instance = ProgramCatalog._();

  List<dynamic>? _raw;
  // Indexes populated from Programs_decoded_full.json
  Map<String, Map<String, dynamic>> _byUuid = {}; // uuid -> entry map
  Map<int, Map<String, dynamic>> _byInternalId = {}; // internalID -> entry map
  Map<String, List<Map<String, dynamic>>> _childrenByParentUuid = {}; // parent uuid -> children list

  Future<void> ensureLoaded() async {
    if (_raw != null) return;

    final s = await rootBundle.loadString('assets/programs/Programs_decoded_full.json');
    final list = jsonDecode(s);
    if (list is! List) {
      throw StateError('Programs JSON is not a List');
    }
    _raw = list;

    // clear any existing indexes
    _byUuid.clear();
    _byInternalId.clear();
    _childrenByParentUuid.clear();

    for (final raw in list) {
      if (raw is! Map) continue;
      // normalize to a mutable map with String keys
      final e = Map<String, dynamic>.from(raw as Map);

      final uuid = (e['ProgramUUID'] ?? '').toString();
      if (uuid.isNotEmpty) {
        _byUuid[uuid] = e;
      }

      final internal = e['internalID'];
      final id = internal is int ? internal : int.tryParse('${internal}');
      if (id != null) {
        _byInternalId[id] = e;
      }

      final parent = (e['Parent'] ?? '').toString();
      if (parent.isNotEmpty) {
        (_childrenByParentUuid[parent] ??= <Map<String, dynamic>>[]).add(e);
      }
    }
  }

  Map<String, dynamic>? byUuid(String uuid) => _byUuid[uuid];
  Map<String, dynamic>? byInternalId(int id) => _byInternalId[id];

  // Return a copy of the internal children list (never null) so callers
  // cannot mutate ProgramCatalog's internal state.
  List<Map<String, dynamic>> childrenByParentUuid(String parentUuid) =>
      List<Map<String, dynamic>>.from(_childrenByParentUuid[parentUuid] ?? const []);

  // Alias used by ProgramRepository (keeps naming consistent)
  List<Map<String, dynamic>> childrenOfUuid(String parentUuid) {
    final list = _childrenByParentUuid[parentUuid];
    if (list == null) return const [];
    return List<Map<String, dynamic>>.from(list);
  }

  String name(Map<String, dynamic> entry, {String lang = 'DE'}) {
    final p = entry['Program'];
    if (p is Map) {
      // Use central ProgramLangController to decide preferred language
      final pref = ProgramLangController.instance.lang;
      if (pref == ProgramLang.de) {
        final v = p['DE'] ?? p['EN'] ?? p.values.first;
        return '$v';
      } else {
        final v = p['EN'] ?? p['DE'] ?? p.values.first;
        return '$v';
      }
    }
    return '(unnamed)';
  }
}
