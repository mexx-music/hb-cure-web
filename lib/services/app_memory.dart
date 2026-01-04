// lib/services/app_memory.dart
// Simple in-memory AppMemory singleton prepared for future persistence.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:yaml/yaml.dart' as yaml;
import '../models/ble_device_profile.dart';

import '../core/program_mode.dart';

class AppMemory extends ChangeNotifier {
  AppMemory._internal();

  static final AppMemory instance = AppMemory._internal();

  // Example fields
  int appLaunchCount = 0;
  final Map<String, dynamic> deviceProfilesCache = {};
  String? lastConnectedDeviceId;
  final Map<String, bool> featureFlags = {};
  // Program mode (beginner/advanced/expert) used by ProgramListPage
  // Backed by a private field so we can notify listeners on change.
  ProgramMode _programMode = ProgramMode.expert;

  ProgramMode get programMode => _programMode;

  set programMode(ProgramMode v) {
    if (_programMode == v) return;
    _programMode = v;
    notifyListeners();
  }

  bool _initialized = false;

  // BLE profiles loaded from doc/app_memory/40_ble_profiles.yaml
  final Map<String, BleDeviceProfile> bleProfilesById = {};

  /// Initialize AppMemory - placeholder for async init (SharedPreferences/Hive)
  Future<void> init() async {
    if (_initialized) return;
    // TODO: load persisted state from SharedPreferences / Hive
    // e.g. final prefs = await SharedPreferences.getInstance();
    // appLaunchCount = prefs.getInt('appLaunchCount') ?? 0;

    // Try to load BLE profiles from YAML documentation file
    try {
      final yamlText = await rootBundle.loadString('doc/app_memory/40_ble_profiles.yaml');
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
              debugPrint('AppMemory.init: failed to parse profile entry ${entry.key}: $e');
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

  void setLastDevice(String id) {
    lastConnectedDeviceId = id;
    // TODO: persist
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
