import 'dart:convert';
import 'dart:io';

String norm(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

class _Stats {
  int matched = 0;
  int already = 0;
  int missing = 0;
}

void enrichProgramsList(
  List<dynamic>? programs,
  Map<String, Map<String, dynamic>> byEnName,
  _Stats stats,
) {
  if (programs == null) return;

  for (final item in programs) {
    if (item is! Map) continue;
    final map = item.cast<String, dynamic>();

    if (map['uuid'] != null || map['internalId'] != null) {
      stats.already++;
      continue;
    }

    final name = map['name'];
    if (name is! String) {
      stats.missing++;
      continue;
    }

    final hit = byEnName[norm(name)];
    if (hit != null) {
      map['uuid'] = hit['uuid'];
      map['internalId'] = hit['internalId'];
      stats.matched++;
    } else {
      stats.missing++;
    }
  }
}

Future<void> main() async {
  final programsPath = 'assets/programs.json';
  final decodedPath = 'assets/programs/Programs_decoded_full.json';

  final programsRaw = await File(programsPath).readAsString();
  final decodedRaw = await File(decodedPath).readAsString();

  final decodedList = (jsonDecode(decodedRaw) as List).cast<dynamic>();
  final tree = jsonDecode(programsRaw);

  // Index: Program.EN -> uuid/internalId
  final Map<String, Map<String, dynamic>> byEnName = {};
  for (final e in decodedList) {
    if (e is! Map) continue;
    final uuid = e['ProgramUUID'];
    final internalId = e['internalID'];
    final prog = e['Program'];
    final en = (prog is Map) ? prog['EN'] : null;
    if (uuid is String && en is String) {
      byEnName[norm(en)] = {'uuid': uuid, 'internalId': internalId};
    }
  }

  final stats = _Stats();

  if (tree is Map) {
    final categories = tree['categories'];
    if (categories is List) {
      for (final c in categories) {
        if (c is! Map) continue;

        // category programs
        enrichProgramsList(c['programs'] as List<dynamic>?, byEnName, stats);

        // subcategories programs
        final subs = c['subcategories'];
        if (subs is List) {
          for (final s in subs) {
            if (s is! Map) continue;
            enrichProgramsList(s['programs'] as List<dynamic>?, byEnName, stats);

            // optional: deeper nesting (falls du mal sub-subcategories hast)
            final subs2 = s['subcategories'];
            if (subs2 is List) {
              for (final ss in subs2) {
                if (ss is! Map) continue;
                enrichProgramsList(ss['programs'] as List<dynamic>?, byEnName, stats);
              }
            }
          }
        }
      }
    }
  }

  final pretty = const JsonEncoder.withIndent('  ').convert(tree);
  await File(programsPath).writeAsString('$pretty\n');

  stdout.writeln(
    'Done. matched=${stats.matched}, alreadyHad=${stats.already}, missing=${stats.missing}',
  );
}

