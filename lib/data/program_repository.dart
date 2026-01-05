import 'dart:convert';
import 'package:flutter/foundation.dart' show compute, debugPrint;
import 'package:flutter/services.dart' show rootBundle;

import '../models/program_category.dart';
import '../models/program_subcategory.dart';
import '../models/program_item.dart';

import 'package:hbcure/services/program_catalog.dart';
import 'package:hbcure/services/app_memory.dart';

/// Repository that loads the programs catalog from `assets/programs.json`.
///
/// To avoid blocking the UI on devices (large JSON parsing), decoding is
/// performed in a background isolate via [compute], and results are cached
/// for subsequent calls.
class ProgramRepository {
  ProgramRepository();

  static List<ProgramCategory>? _cachedCategories;

  Future<List<ProgramCategory>> loadCategories() async {
    // Return cached result if available
    if (_cachedCategories != null) return _cachedCategories!;

    try {
      final jsonString = await rootBundle.loadString('assets/programs.json');
      // decode JSON on a background isolate
      final Map<String, dynamic> map = await compute(_decodeJson, jsonString);
      final catsJson = map['categories'] as List<dynamic>?;
      if (catsJson == null) {
        _cachedCategories = <ProgramCategory>[];
        return _cachedCategories!;
      }

      // Keep raw category JSON around so we can read extra fields like "internalId"
      // that are not part of ProgramCategory model (minimal approach).
      final rawCats = catsJson
          .whereType<Map<String, dynamic>>()
          .toList();

      // Ensure decoded catalog is loaded for enrichment + tree expansion
      await ProgramCatalog.instance.ensureLoaded();

      // Build categories from raw
      var categories = rawCats.map((c) => ProgramCategory.fromJson(c)).toList();

      // --- DEBUG: concise summary about loaded categories (mode + counts)
      try {
        final mode = AppMemory.instance.programMode;
        final yellow = categories.where((c) => (c.color ?? '').trim().toLowerCase() == 'yellow').length;
        final red = categories.where((c) => (c.color ?? '').trim().toLowerCase() == 'red').length;
        final empty = categories.where((c) => (c.programs.isEmpty) && (c.subcategories.isEmpty)).length;
        debugPrint('CATS_LOADED(pre) mode=$mode count=${categories.length} empty=$empty yellow=$yellow red=$red');
      } catch (_) {
        // ignore debug errors
      }

      // Normalize categories: inherit colors, remove empty entries, enrich items,
      // and IMPORTANT: expand empty categories from decoded if internalId is present.
      final normalized = <ProgramCategory>[];
      for (var i = 0; i < categories.length; i++) {
        final raw = rawCats[i];
        final c = categories[i];
        final nc = _normalizeCategory(c, raw: raw, parentColor: null);
        if (nc != null) normalized.add(nc);
      }

      // --- DEBUG: after normalization
      try {
        final mode = AppMemory.instance.programMode;
        final yellow = normalized.where((c) => (c.color ?? '').trim().toLowerCase() == 'yellow').length;
        final red = normalized.where((c) => (c.color ?? '').trim().toLowerCase() == 'red').length;
        final empty = normalized.where((c) => (c.programs.isEmpty) && (c.subcategories.isEmpty)).length;
        debugPrint('CATS_LOADED(post) mode=$mode count=${normalized.length} empty=$empty yellow=$yellow red=$red');
      } catch (_) {}

      _cachedCategories = normalized;
      return normalized;
    } catch (e, st) {
      // TODO: better error handling/logging; for now print and return empty list
      print('Error loading assets/programs.json: $e\n$st');
      _cachedCategories = <ProgramCategory>[];
      return _cachedCategories!;
    }
  }

  // Normalize a category (inherits parent color, normalizes subcategories and programs)
  // Also expands empty categories from decoded catalog when raw["internalId"] is present.
  ProgramCategory? _normalizeCategory(
      ProgramCategory c, {
        required Map<String, dynamic> raw,
        String? parentColor,
      }) {
    final own = (c.color ?? '').trim().toLowerCase();
    final effective = own.isNotEmpty ? own : (parentColor ?? 'green');

    // Normalize programs
    var progs = c.programs
        .map((p) => _normalizeProgram(p, parentColor: effective))
        .where((p) => p != null)
        .cast<ProgramItem>()
        .toList();

    // Normalize subcategories recursively
    var subs = c.subcategories
        .map((s) => _normalizeSubcategory(s, parentColor: effective))
        .where((s) => s != null)
        .cast<ProgramSubcategory>()
        .toList();

    // If category is empty from UI JSON, try to populate from decoded using raw["internalId"]
    if (progs.isEmpty && subs.isEmpty) {
      final expanded = _expandEmptyCategoryFromDecoded(raw: raw, effectiveColor: effective);
      if (expanded != null) {
        progs = expanded.programs;
        subs = expanded.subcategories;
      }
    }

    // If category still has no programs and no subcategories after expansion/normalization, drop it
    if (progs.isEmpty && subs.isEmpty) return null;

    return ProgramCategory(
      id: c.id,
      title: c.title,
      color: effective,
      subcategories: subs,
      programs: progs,
    );
  }

  ProgramSubcategory? _normalizeSubcategory(ProgramSubcategory s, {String? parentColor}) {
    final own = (s.color ?? '').trim().toLowerCase();
    final effective = own.isNotEmpty ? own : (parentColor ?? 'green');

    final progs = s.programs
        .map((p) => _normalizeProgram(p, parentColor: effective))
        .where((p) => p != null)
        .cast<ProgramItem>()
        .toList();

    if (progs.isEmpty) return null; // remove empty subcategories

    return ProgramSubcategory(
      id: s.id,
      title: s.title,
      color: effective,
      programs: progs,
    );
  }

  ProgramItem? _normalizeProgram(ProgramItem p, {String? parentColor}) {
    // Enrich from ProgramCatalog using uuid/internalId or fallbacks
    final catalog = ProgramCatalog.instance;
    Map<String, dynamic>? entry;

    if (p.uuid != null && p.uuid!.isNotEmpty) {
      entry = catalog.byUuid(p.uuid!);
    }
    if (entry == null && p.internalId != null) {
      entry = catalog.byInternalId(p.internalId!);
    }
    if (entry == null) {
      // Try fallback by id string
      final asInt = int.tryParse(p.id);
      entry = catalog.byUuid(p.id) ?? (asInt != null ? catalog.byInternalId(asInt) : null);
    }

    String? uuid = p.uuid;
    int? internalId = p.internalId;
    int level = p.level;

    if (entry != null) {
      final u = (entry['ProgramUUID'] ?? '').toString();
      if ((uuid == null || uuid!.isEmpty) && u.isNotEmpty) uuid = u;

      // internalID in decoded is commonly a string; handle both
      final iidStr = (entry['internalID'] ?? '').toString();
      final iid = int.tryParse(iidStr);
      if (internalId == null && iid != null) internalId = iid;

      final l = entry['level'];
      if (l is num) level = l.toInt();
      else if (l is String) level = int.tryParse(l) ?? level;
    }

    // Return new ProgramItem with enriched fields (preserve original name)
    return ProgramItem(
      id: p.id,
      name: p.name,
      uuid: uuid,
      internalId: internalId,
      level: level,
    );
  }

  /// If a UI category is empty (programs/subcategories empty), but has raw["internalId"],
  /// we treat it as a pointer to a decoded root-node and derive children from decoded.
  _ExpandedCategory? _expandEmptyCategoryFromDecoded({
    required Map<String, dynamic> raw,
    required String effectiveColor,
  }) {
    final internalId = raw['internalId'] is int
        ? raw['internalId'] as int
        : int.tryParse('${raw['internalId']}');

    if (internalId == null) return null;

    final root = ProgramCatalog.instance.byInternalId(internalId);
    if (root == null) return null;

    final rootUuid = (root['ProgramUUID'] ?? '').toString();
    if (rootUuid.isEmpty) return null;

    final children = ProgramCatalog.instance.childrenOfUuid(rootUuid);
    if (children.isEmpty) return null;

    final progs = <ProgramItem>[];
    final subs = <ProgramSubcategory>[];

    for (final child in children) {
      if (_isDecodedProgram(child)) {
        final pi = _programItemFromDecoded(child);
        final np = _normalizeProgram(pi, parentColor: effectiveColor);
        if (np != null) progs.add(np);
      } else {
        final subId = _decodedInternalId(child)?.toString() ?? _decodedUuid(child);
        final subTitle = _decodedTitleEn(child);
        subs.add(
          ProgramSubcategory(
            id: subId.isNotEmpty ? subId : 'sub_${subs.length}',
            title: subTitle.isNotEmpty ? subTitle : 'Category',
            color: effectiveColor,
            programs: const [],
          ),
        );
      }
    }

    // NOTE: This builds only one level of children. That's enough to make the
    // yellow roots non-empty and visible. We can deepen later if needed.
    return _ExpandedCategory(programs: progs, subcategories: subs);
  }

  bool _isDecodedProgram(Map<String, dynamic> e) {
    final freqs = e['Frequencies'];
    return freqs is List && freqs.isNotEmpty;
  }

  String _decodedTitleEn(Map<String, dynamic> e) {
    final prog = e['Program'];
    if (prog is Map) return (prog['EN'] ?? '').toString();
    return '';
  }

  String _decodedUuid(Map<String, dynamic> e) => (e['ProgramUUID'] ?? '').toString();

  int? _decodedInternalId(Map<String, dynamic> e) {
    final s = (e['internalID'] ?? '').toString();
    return int.tryParse(s);
  }

  ProgramItem _programItemFromDecoded(Map<String, dynamic> e) {
    final iid = _decodedInternalId(e);
    final uuid = _decodedUuid(e);
    final id = iid?.toString() ?? (uuid.isNotEmpty ? uuid : 'unknown');

    return ProgramItem(
      id: id,
      name: _decodedTitleEn(e),
      uuid: uuid.isNotEmpty ? uuid : null,
      internalId: iid,
      level: (() {
        final s = (e['level'] ?? '1').toString();
        return int.tryParse(s) ?? 1;
      })(),
    );
  }
}

class _ExpandedCategory {
  final List<ProgramItem> programs;
  final List<ProgramSubcategory> subcategories;

  _ExpandedCategory({required this.programs, required this.subcategories});
}

// Top-level function for compute() to decode JSON string into Map
Map<String, dynamic> _decodeJson(String jsonString) {
  return jsonDecode(jsonString) as Map<String, dynamic>;
}
