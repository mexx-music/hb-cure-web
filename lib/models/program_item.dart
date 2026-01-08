// ProgramItem model

import 'dart:convert';

class ProgramItem {
  final String id; // slug
  final String name;

  final String? uuid; // ProgramUUID
  final int? internalId; // internalID
  // New: optional program level (default = 1)
  final int level;

  ProgramItem({
    required this.id,
    required this.name,
    this.uuid,
    this.internalId,
    this.level = 1,
  });

  factory ProgramItem.fromJson(Map<String, dynamic> json) {
    String _s(dynamic v) => (v == null) ? '' : v.toString().trim();

    int? _i(dynamic v) {
      if (v is int) return v;
      final s = _s(v);
      return s.isEmpty ? null : int.tryParse(s);
    }

    final String uuid = _s(json['uuid']);
    final String name = _s(json['name']);
    final String idRaw = _s(json['id']);
    final int? internalId = _i(json['internalId']);

    // Choose a safe id: prefer explicit id, else uuid, else internalId
    final String id = idRaw.isNotEmpty
        ? idRaw
        : (uuid.isNotEmpty ? uuid : (internalId?.toString() ?? ''));

    // NEVER crash on missing fields
    return ProgramItem(
      id: id.isNotEmpty ? id : 'unknown_${DateTime.now().millisecondsSinceEpoch}',
      name: name.isNotEmpty ? name : '-',
      uuid: uuid,
      internalId: internalId,
      level: (json['level'] is num)
          ? (json['level'] as num).toInt()
          : (int.tryParse('${json['level']}') ?? 1),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (uuid != null) 'uuid': uuid,
        if (internalId != null) 'internalId': internalId,
        'level': level,
      };

  @override
  String toString() => jsonEncode(toJson());
}
