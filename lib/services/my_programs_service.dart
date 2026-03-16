import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:hbcure/services/clients_store.dart';

/// Singleton service to manage the user's saved program IDs.
class MyProgramsService extends ChangeNotifier {
  // legacy key (old single global list)
  static const _legacyKey = 'my_program_ids';
  // new per-client prefix
  static const _keyPrefix = 'my_program_ids__';

  static final MyProgramsService instance = MyProgramsService._internal();

  factory MyProgramsService() => instance;

  MyProgramsService._internal();

  // Broadcast stream to notify legacy listeners when the saved IDs change
  // Keep this for backward compatibility
  final StreamController<void> _changes = StreamController<void>.broadcast(sync: true);
  Stream<void> get onChange => _changes.stream;

  // Determine the SharedPreferences key for the currently active client
  Future<String> _keyForActiveClient() async {
    final activeId = await ClientsStore.instance.loadActiveClientId();
    return activeId == null ? '${_keyPrefix}default' : '$_keyPrefix$activeId';
  }

  // Migrate legacy data (only if needed): move from old global key to the new per-client key
  Future<void> _migrateLegacyIfNeeded(SharedPreferences prefs, String newKey) async {
    final legacy = prefs.getStringList(_legacyKey);
    final current = prefs.getStringList(newKey);
    if ((current == null || current.isEmpty) && legacy != null && legacy.isNotEmpty) {
      await prefs.setStringList(newKey, legacy);
      await prefs.remove(_legacyKey);
    }
  }

  Future<List<String>> loadIds() async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _keyForActiveClient();
    await _migrateLegacyIfNeeded(prefs, key);
    final list = prefs.getStringList(key);
    return list ?? <String>[];
  }

  Future<void> saveIds(List<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _keyForActiveClient();
    await _migrateLegacyIfNeeded(prefs, key);
    // Save as-is (preserve order). Uniqueness should be handled by callers.
    await prefs.setStringList(key, ids);
    _changes.add(null);
    notifyListeners();
  }

  Future<void> add(String programId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _keyForActiveClient();
    await _migrateLegacyIfNeeded(prefs, key);
    final list = prefs.getStringList(key) ?? <String>[];
    if (!list.contains(programId)) {
      list.add(programId);
      await prefs.setStringList(key, list);
      _changes.add(null);
      notifyListeners();
    }
  }

  Future<void> remove(String programId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _keyForActiveClient();
    await _migrateLegacyIfNeeded(prefs, key);
    final list = prefs.getStringList(key) ?? <String>[];
    if (list.contains(programId)) {
      list.remove(programId);
      await prefs.setStringList(key, list);
      _changes.add(null);
      notifyListeners();
    }
  }

  Future<bool> contains(String programId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _keyForActiveClient();
    await _migrateLegacyIfNeeded(prefs, key);
    final list = prefs.getStringList(key) ?? <String>[];
    return list.contains(programId);
  }
}
