import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

/// Singleton service to manage the user's saved program IDs.
class MyProgramsService {
  static const _key = 'my_program_ids';
  static final MyProgramsService _instance = MyProgramsService._internal();

  factory MyProgramsService() => _instance;

  MyProgramsService._internal();

  // Broadcast stream to notify listeners when the saved IDs change
  // Use a synchronous broadcast controller so listeners get notified immediately
  final StreamController<void> _changes = StreamController<void>.broadcast(sync: true);
  Stream<void> get onChange => _changes.stream;

  Future<List<String>> loadIds() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key);
    return list ?? <String>[];
  }

  Future<void> saveIds(List<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    // Save as-is (preserve order). Uniqueness should be handled by callers.
    await prefs.setStringList(_key, ids);
    _changes.add(null);
  }

  Future<void> add(String programId) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? <String>[];
    if (!list.contains(programId)) {
      list.add(programId);
      await prefs.setStringList(_key, list);
      _changes.add(null);
    }
  }

  Future<void> remove(String programId) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? <String>[];
    if (list.contains(programId)) {
      list.remove(programId);
      await prefs.setStringList(_key, list);
      _changes.add(null);
    }
  }

  Future<bool> contains(String programId) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? <String>[];
    return list.contains(programId);
  }
}
