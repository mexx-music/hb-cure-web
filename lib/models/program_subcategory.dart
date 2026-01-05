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
    final programsJson = json['programs'] as List<dynamic>?;
    return ProgramSubcategory(
      id: json['id'] as String,
      title: json['title'] as String,
      color: json['color'] is String ? (json['color'] as String) : null,
      programs: programsJson != null
          ? programsJson.map((e) => ProgramItem.fromJson(e as Map<String, dynamic>)).toList()
          : [],
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
