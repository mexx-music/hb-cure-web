// ProgramItem model

import 'dart:convert';

class ProgramItem {
  final String id; // slug
  final String name;

  final String? uuid; // ProgramUUID
  final int? internalId; // internalID

  ProgramItem({
    required this.id,
    required this.name,
    this.uuid,
    this.internalId,
  });

  factory ProgramItem.fromJson(Map<String, dynamic> json) {
    return ProgramItem(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? '',
      uuid: json['uuid'] as String?,
      internalId: json['internalId'] is int
          ? json['internalId'] as int
          : int.tryParse('${json['internalId']}'),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (uuid != null) 'uuid': uuid,
        if (internalId != null) 'internalId': internalId,
      };

  @override
  String toString() => jsonEncode(toJson());
}
