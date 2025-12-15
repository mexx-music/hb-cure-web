import 'program_item.dart';

class ProgramSubcategory {
  final String id;
  final String title;
  final List<ProgramItem> programs;

  ProgramSubcategory({
    required this.id,
    required this.title,
    List<ProgramItem>? programs,
  }) : programs = programs ?? [];

  factory ProgramSubcategory.fromJson(Map<String, dynamic> json) {
    final programsJson = json['programs'] as List<dynamic>?;
    return ProgramSubcategory(
      id: json['id'] as String,
      title: json['title'] as String,
      programs: programsJson != null
          ? programsJson.map((e) => ProgramItem.fromJson(e as Map<String, dynamic>)).toList()
          : [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'programs': programs.map((p) => p.toJson()).toList(),
    };
  }
}

