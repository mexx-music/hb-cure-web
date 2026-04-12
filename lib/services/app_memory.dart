// lib/services/app_memory.dart
// Simple in-memory AppMemory singleton prepared for future persistence.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:yaml/yaml.dart' as yaml;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/ble_device_profile.dart';
import '../core/program_mode.dart';

class AppMemory extends ChangeNotifier {
  AppMemory._internal() {
    // ensure notifier initial value matches the private field
    programModeNotifier.value = _programMode;
  }

  static final AppMemory instance = AppMemory._internal();

  static const String _kProgramModeKey = 'programMode';
  static const String _kReconnectEnabledKey = 'reconnectEnabled';
  static const String _kLastDeviceIdKey = 'lastDeviceId';

  // Example fields
  int appLaunchCount = 0;
  final Map<String, dynamic> deviceProfilesCache = {};
  String? lastConnectedDeviceId;
  final Map<String, bool> featureFlags = {};

  // Auto-reconnect toggle
  bool _reconnectEnabled = true;
  bool get reconnectEnabled => _reconnectEnabled;

  // Program mode (beginner/advanced/expert)
  // Backed by a private field so we can notify listeners on change.
  ProgramMode _programMode = ProgramMode.expert;

  // ValueNotifier for quick value-listenable rebuilds in widgets that prefer it
  // Consumers can use AppMemory.instance.programModeNotifier
  final ValueNotifier<ProgramMode> programModeNotifier =
  ValueNotifier<ProgramMode>(ProgramMode.expert);

  ProgramMode get programMode => _programMode;

  set programMode(ProgramMode v) {
    if (_programMode == v) return;
    _programMode = v;

    // update notifier for ValueListenableBuilders
    try {
      programModeNotifier.value = v;
    } catch (_) {}

    notifyListeners();
  }

  /// Persisted setter (minimal):
  /// - updates in-memory mode + notifiers
  /// - saves to SharedPreferences
  Future<void> setProgramMode(ProgramMode v) async {
    programMode = v;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kProgramModeKey, v.name);
    } catch (e) {
      debugPrint('AppMemory.setProgramMode: could not persist mode: $e');
    }
  }

  bool _initialized = false;

  // BLE profiles loaded from doc/app_memory/40_ble_profiles.yaml
  final Map<String, BleDeviceProfile> bleProfilesById = {};

  /// Initialize AppMemory
  /// - loads persisted ProgramMode first (so UI is consistent on first paint)
  /// - loads optional YAML profiles
  Future<void> init() async {
    if (_initialized) return;

    // 1) Load persisted program mode (if available)
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kProgramModeKey);
      if (raw != null && raw.trim().isNotEmpty) {
        final loaded = ProgramMode.values.firstWhere(
              (m) => m.name == raw,
          orElse: () => ProgramMode.expert,
        );
        _programMode = loaded;
        programModeNotifier.value = loaded;
        // no notifyListeners here; init usually happens before UI
      }

      // 1b) Load persisted reconnect settings
      final reconnectRaw = prefs.getBool(_kReconnectEnabledKey);
      if (reconnectRaw != null) {
        _reconnectEnabled = reconnectRaw;
      }

      final lastDeviceRaw = prefs.getString(_kLastDeviceIdKey);
      if (lastDeviceRaw != null && lastDeviceRaw.isNotEmpty) {
        lastConnectedDeviceId = lastDeviceRaw;
      }
    } catch (e) {
      debugPrint('AppMemory.init: could not load persisted mode: $e');
    }

    // 2) Try to load BLE profiles from YAML documentation file
    try {
      final yamlText =
      await rootBundle.loadString('doc/app_memory/40_ble_profiles.yaml');
      if (yamlText.trim().isNotEmpty) {
        final parsed = yaml.loadYaml(yamlText);
        if (parsed is yaml.YamlMap || parsed is Map) {
          final map = Map<dynamic, dynamic>.from(parsed as Map);
          for (final entry in map.entries) {
            try {
              final profileMap = entry.value as Map<dynamic, dynamic>;
              final profile = BleDeviceProfile.fromMap(profileMap);
              if (profile.id.isNotEmpty) {
                bleProfilesById[profile.id] = profile;
              }
            } catch (e) {
              // ignore single profile errors
              debugPrint(
                  'AppMemory.init: failed to parse profile entry ${entry.key}: $e');
            }
          }
        }
      }
    } catch (e) {
      // File missing or parse error -> continue without profiles
      debugPrint('AppMemory.init: could not load BLE profiles yaml: $e');
    }

    _initialized = true;
  }

  void incrementLaunchCount() {
    appLaunchCount++;
    // TODO: persist
  }

  Future<void> setReconnectEnabled(bool v) async {
    if (_reconnectEnabled == v) return;
    _reconnectEnabled = v;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kReconnectEnabledKey, v);
    } catch (e) {
      debugPrint('AppMemory.setReconnectEnabled: could not persist: $e');
    }
  }

  Future<void> setLastDevice(String id) async {
    lastConnectedDeviceId = id;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLastDeviceIdKey, id);
    } catch (e) {
      debugPrint('AppMemory.setLastDevice: could not persist: $e');
    }
  }

  void setFeatureFlag(String key, bool value) {
    featureFlags[key] = value;
    // TODO: persist
  }

  // Utility getters
  bool get isInitialized => _initialized;

  BleDeviceProfile? getBleProfile(String id) => bleProfilesById[id];

// If deviceProfilesCache was previously used for something else, keep it but document
// it's recommended to use bleProfilesById for static YAML-profiles.
}
