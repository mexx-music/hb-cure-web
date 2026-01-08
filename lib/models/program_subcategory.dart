import 'program_item.dart';

class ProgramSubcategory {
  final String id;
  final String title;
  // optional color hint (inherits from parent category if missing)
  final String? color;
  final List<ProgramItem> programs;

  ProgramSubcategory({
    required this.id,
    required this.title,
    this.color,
    List<ProgramItem>? programs,
  }) : programs = programs ?? [];

  factory ProgramSubcategory.fromJson(Map<String, dynamic> json) {
    final raw = (json['programs'] as List<dynamic>?) ?? const [];
    final programs = raw
        .whereType<Map>()
        .map((e) => ProgramItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    return ProgramSubcategory(
      id: json['id'] as String,
      title: json['title'] as String,
      color: json['color'] is String ? (json['color'] as String) : null,
      programs: programs,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      if (color != null) 'color': color,
      'programs': programs.map((p) => p.toJson()).toList(),
    };
  }
}
