import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Snapshot of the last playlist that was uploaded to a specific Cure Clip
/// device. Used to recognize a still-running playlist after reconnect and
/// restore the player UI (queue, titles, position).
@immutable
class DevicePlaylistSnapshot {
  final String deviceId;
  final String? clientId;
  final String? clientName;
  final String mergedUuidHex;
  final List<String> ids;
  final Map<String, String> titleKeyEnById;
  final Map<String, int> durationsMin;
  final int totalSec;
  final DateTime uploadedAt;

  const DevicePlaylistSnapshot({
    required this.deviceId,
    required this.mergedUuidHex,
    required this.ids,
    required this.titleKeyEnById,
    required this.durationsMin,
    required this.totalSec,
    required this.uploadedAt,
    this.clientId,
    this.clientName,
  });

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'clientId': clientId,
        'clientName': clientName,
        'mergedUuidHex': mergedUuidHex,
        'ids': ids,
        'titleKeyEnById': titleKeyEnById,
        'durationsMin': durationsMin,
        'totalSec': totalSec,
        'uploadedAt': uploadedAt.toUtc().toIso8601String(),
      };

  static DevicePlaylistSnapshot? fromJson(Map<String, dynamic> j) {
    try {
      final ids = (j['ids'] as List<dynamic>?)?.cast<String>() ?? const <String>[];
      final titles = <String, String>{};
      final rawTitles = j['titleKeyEnById'];
      if (rawTitles is Map) {
        rawTitles.forEach((k, v) => titles[k.toString()] = v.toString());
      }
      final durations = <String, int>{};
      final rawDur = j['durationsMin'];
      if (rawDur is Map) {
        rawDur.forEach((k, v) {
          final iv = (v is int) ? v : int.tryParse(v.toString()) ?? 0;
          durations[k.toString()] = iv;
        });
      }
      return DevicePlaylistSnapshot(
        deviceId: (j['deviceId'] ?? '').toString(),
        clientId: j['clientId']?.toString(),
        clientName: j['clientName']?.toString(),
        mergedUuidHex: (j['mergedUuidHex'] ?? '').toString(),
        ids: ids,
        titleKeyEnById: titles,
        durationsMin: durations,
        totalSec: (j['totalSec'] is int)
            ? j['totalSec'] as int
            : int.tryParse('${j['totalSec']}') ?? 0,
        uploadedAt: DateTime.tryParse('${j['uploadedAt']}')?.toLocal() ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
    } catch (_) {
      return null;
    }
  }
}

/// SharedPreferences-backed store for the last uploaded playlist per device.
/// Strictly keyed by deviceId – never use a global "last playlist".
class DevicePlaylistStore {
  DevicePlaylistStore._();
  static final DevicePlaylistStore instance = DevicePlaylistStore._();

  static const _kPrefix = 'last_playlist_per_device__';

  static String _keyFor(String deviceId) => '$_kPrefix$deviceId';

  Future<void> save(DevicePlaylistSnapshot snapshot) async {
    if (snapshot.deviceId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _keyFor(snapshot.deviceId),
        jsonEncode(snapshot.toJson()),
      );
    } catch (e) {
      debugPrint('[DevicePlaylistStore] save error: $e');
    }
  }

  Future<DevicePlaylistSnapshot?> load(String deviceId) async {
    if (deviceId.isEmpty) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyFor(deviceId));
      if (raw == null || raw.isEmpty) return null;
      final map = jsonDecode(raw);
      if (map is! Map<String, dynamic>) return null;
      return DevicePlaylistSnapshot.fromJson(map);
    } catch (e) {
      debugPrint('[DevicePlaylistStore] load error: $e');
      return null;
    }
  }

  Future<void> clear(String deviceId) async {
    if (deviceId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyFor(deviceId));
    } catch (e) {
      debugPrint('[DevicePlaylistStore] clear error: $e');
    }
  }

  /// Normalize a hex string for case-insensitive UUID comparison.
  /// Strips whitespace and non-hex characters, returns lowercase.
  static String normalizeHex(String s) {
    final cleaned = s.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
    return cleaned.toLowerCase();
  }
}
