import 'program_subcategory.dart';
import 'program_item.dart';

class ProgramCategory {
  final String id;
  final String title;
  final List<ProgramSubcategory> subcategories;
  final List<ProgramItem> programs;

  ProgramCategory({
    required this.id,
    required this.title,
    List<ProgramSubcategory>? subcategories,
    List<ProgramItem>? programs,
  })  : subcategories = subcategories ?? [],
        programs = programs ?? [];

  factory ProgramCategory.fromJson(Map<String, dynamic> json) {
    final subsJson = json['subcategories'] as List<dynamic>?;
    final progsJson = json['programs'] as List<dynamic>?;
    return ProgramCategory(
      id: json['id'] as String,
      title: json['title'] as String,
      subcategories: subsJson != null
          ? subsJson.map((e) => ProgramSubcategory.fromJson(e as Map<String, dynamic>)).toList()
          : [],
      programs: progsJson != null
          ? progsJson.map((e) => ProgramItem.fromJson(e as Map<String, dynamic>)).toList()
          : [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'subcategories': subcategories.map((s) => s.toJson()).toList(),
      'programs': programs.map((p) => p.toJson()).toList(),
    };
  }
}

