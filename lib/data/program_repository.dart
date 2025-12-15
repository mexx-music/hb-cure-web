import 'dart:convert';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart' show rootBundle;

import '../models/program_category.dart';
import '../models/program_subcategory.dart';
import '../models/program_item.dart';

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
      final categories = catsJson.map((c) => ProgramCategory.fromJson(c as Map<String, dynamic>)).toList();
      _cachedCategories = categories;
      return categories;
    } catch (e, st) {
      // TODO: better error handling/logging; for now print and return empty list
      print('Error loading assets/programs.json: $e\n$st');
      _cachedCategories = <ProgramCategory>[];
      return _cachedCategories!;
    }
  }
}

// Top-level function for compute() to decode JSON string into Map
Map<String, dynamic> _decodeJson(String jsonString) {
  return jsonDecode(jsonString) as Map<String, dynamic>;
}
