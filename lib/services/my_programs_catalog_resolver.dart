import '../data/program_repository.dart';
import '../models/program_item.dart';

class MyProgramsCatalogResolver {
  MyProgramsCatalogResolver._();

  static Future<Map<String, ProgramItem>> buildIdToProgramItemMap() async {
    final repo = ProgramRepository();
    final categories = await repo.loadCategories();

    final Map<String, ProgramItem> map = {};
    for (final c in categories) {
      for (final p in c.programs) {
        map[p.id] = p;
      }
      for (final s in c.subcategories) {
        for (final p in s.programs) {
          map[p.id] = p;
        }
      }
    }
    return map;
  }

  static Future<List<ProgramItem>> resolveProgramItems(List<String> ids) async {
    final map = await buildIdToProgramItemMap();
    final out = <ProgramItem>[];
    for (final id in ids) {
      final p = map[id];
      if (p != null) out.add(p);
    }
    return out;
  }
}

