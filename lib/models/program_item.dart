// ProgramItem model

import 'dart:convert';

class ProgramItem {
  final String id;
  final String name;
  final String? code;
  final int? variantIndex;
  final String? notes;

  ProgramItem({
    required this.id,
    required this.name,
    this.code,
    this.variantIndex,
    this.notes,
  });

  factory ProgramItem.fromJson(Map<String, dynamic> json) {
    return ProgramItem(
      id: json['id'] as String,
      name: json['name'] as String,
      code: json['code'] as String?,
      variantIndex: json['variantIndex'] is int ? json['variantIndex'] as int : (json['variantIndex'] == null ? null : int.tryParse(json['variantIndex'].toString())),
      notes: json['notes'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'code': code,
      'variantIndex': variantIndex,
      'notes': notes,
    };
  }

  @override
  String toString() => jsonEncode(toJson());
}

