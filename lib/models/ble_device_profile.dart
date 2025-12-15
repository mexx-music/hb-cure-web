// lib/models/ble_device_profile.dart

class BleDeviceProfile {
  final String id;
  final String name;
  final String? manufacturer;
  final Map<String, dynamic> metadata;

  BleDeviceProfile({
    required this.id,
    required this.name,
    this.manufacturer,
    Map<String, dynamic>? metadata,
  }) : metadata = metadata ?? {};

  factory BleDeviceProfile.fromMap(Map<dynamic, dynamic> map) {
    final id = map['id']?.toString() ?? '';
    final name = map['name']?.toString() ?? id;
    final manufacturer = map['manufacturer']?.toString();

    // metadata: copy remaining keys except id/name/manufacturer
    final metadata = <String, dynamic>{};
    for (final entry in map.entries) {
      final k = entry.key?.toString();
      if (k == null) continue;
      if (k == 'id' || k == 'name' || k == 'manufacturer') continue;
      metadata[k] = entry.value;
    }

    return BleDeviceProfile(
      id: id,
      name: name,
      manufacturer: manufacturer,
      metadata: metadata,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'manufacturer': manufacturer,
        ...metadata,
      };
}

