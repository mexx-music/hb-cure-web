import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:hbcure/services/program_language_controller.dart';

class ProgramCatalog {
  ProgramCatalog._();
  static final ProgramCatalog instance = ProgramCatalog._();

  List<dynamic>? _raw;
  Map<String, dynamic>? _byUuid; // uuid -> entry map
  Map<int, dynamic>? _byInternalId; // internalID -> entry map

  Future<void> ensureLoaded() async {
    if (_raw != null) return;

    final s = await rootBundle.loadString('assets/programs/Programs_decoded_full.json');
    final list = jsonDecode(s);
    if (list is! List) {
      throw StateError('Programs JSON is not a List');
    }
    _raw = list;

    _byUuid = {};
    _byInternalId = {};

    for (final e in list) {
      if (e is! Map) continue;

      final uuid = e['ProgramUUID'];
      if (uuid is String && uuid.isNotEmpty) {
        _byUuid![uuid] = e;
      }

      final internal = e['internalID'];
      final id = internal is int ? internal : int.tryParse('$internal');
      if (id != null) {
        _byInternalId![id] = e;
      }
    }
  }

  Map<String, dynamic>? byUuid(String uuid) => _byUuid?[uuid] as Map<String, dynamic>?;
  Map<String, dynamic>? byInternalId(int id) => _byInternalId?[id] as Map<String, dynamic>?;

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
