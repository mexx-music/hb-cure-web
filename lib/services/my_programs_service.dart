import 'dart:async';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:hbcure/services/clients_store.dart';

/// Extracts the base programId from a slot key.
/// e.g. "pain_abdominal_pain_1__slot_abc123" -> "pain_abdominal_pain_1"
/// Plain IDs are returned as-is.
String baseIdFromSlotKey(String slotKey) {
  const sep = '__slot_';
  final idx = slotKey.indexOf(sep);
  if (idx < 0) return slotKey;
  return slotKey.substring(0, idx);
}

/// Returns true if the given id is a slot key (i.e. a duplicate entry).
bool isSlotKey(String id) => id.contains('__slot_');

String _generateShortId() {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final rng = math.Random();
  return String.fromCharCodes(
    List.generate(6, (_) => chars.codeUnitAt(rng.nextInt(chars.length))),
  );
}

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

  /// Duplicates [originalId] by inserting a new slot-keyed entry directly
  /// after the original in the list.
  /// Returns the newly generated slot key so the caller can copy settings.
  Future<String> duplicate(String originalId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _keyForActiveClient();
    await _migrateLegacyIfNeeded(prefs, key);
    final list = prefs.getStringList(key) ?? <String>[];

    final baseId = baseIdFromSlotKey(originalId);
    // Build a unique slot key
    String slotKey;
    do {
      slotKey = '${baseId}__slot_${_generateShortId()}';
    } while (list.contains(slotKey));

    final insertAt = list.indexOf(originalId);
    if (insertAt >= 0) {
      list.insert(insertAt + 1, slotKey);
    } else {
      list.add(slotKey);
    }

    await prefs.setStringList(key, list);
    _changes.add(null);
    notifyListeners();
    return slotKey;
  }
}
