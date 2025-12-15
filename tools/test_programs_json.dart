import 'dart:convert';
import 'dart:io';

/// Smoke test for assets/programs.json
/// Run: dart run tools/test_programs_json.dart

void main(List<String> args) {
  final file = File('assets/programs.json');
  if (!file.existsSync()) {
    stderr.writeln('ERROR: assets/programs.json not found');
    exit(1);
  }

  String raw = file.readAsStringSync();
  // Remove any leading // comments (our generator may have added a comment line)
  final cleaned = raw.replaceAll(RegExp(r'^\s*//.*	*$', multiLine: true), '');

  late Map<String, dynamic> root;
  try {
    root = jsonDecode(cleaned) as Map<String, dynamic>;
  } catch (e) {
    stderr.writeln('ERROR: Failed to parse JSON: $e');
    exit(2);
  }

  final catsJson = root['categories'] as List<dynamic>?;
  if (catsJson == null) {
    stderr.writeln('ERROR: No "categories" array in JSON');
    exit(3);
  }

  final int catCount = catsJson.length;
  int subCount = 0;
  int progCount = 0;

  final List<String> warnings = [];

  for (var cIndex = 0; cIndex < catsJson.length; cIndex++) {
    final c = catsJson[cIndex] as Map<String, dynamic>;
    final cid = (c['id'] ?? '').toString().trim();
    if (cid.isEmpty) warnings.add('Category at index $cIndex has empty id (title: "${c['title']}")');

    final subs = (c['subcategories'] as List<dynamic>?) ?? [];
    subCount += subs.length;
    for (var sIndex = 0; sIndex < subs.length; sIndex++) {
      final s = subs[sIndex] as Map<String, dynamic>;
      final sid = (s['id'] ?? '').toString().trim();
      if (sid.isEmpty) warnings.add('Subcategory at category[$cIndex] subindex $sIndex has empty id (title: "${s['title']}")');
      final progs = (s['programs'] as List<dynamic>?) ?? [];
      progCount += progs.length;
      for (var pIndex = 0; pIndex < progs.length; pIndex++) {
        final p = progs[pIndex] as Map<String, dynamic>;
        final pid = (p['id'] ?? '').toString().trim();
        if (pid.isEmpty) warnings.add('Program at category[$cIndex] subcategory[$sIndex] programIndex $pIndex has empty id (name: "${p['name']}")');
      }
    }

    final topProgs = (c['programs'] as List<dynamic>?) ?? [];
    progCount += topProgs.length;
    for (var tpIndex = 0; tpIndex < topProgs.length; tpIndex++) {
      final p = topProgs[tpIndex] as Map<String, dynamic>;
      final pid = (p['id'] ?? '').toString().trim();
      if (pid.isEmpty) warnings.add('Program at category[$cIndex] top-level programIndex $tpIndex has empty id (name: "${p['name']}")');
    }
  }

  stdout.writeln('Categories: $catCount');
  stdout.writeln('Subcategories: $subCount');
  stdout.writeln('Programs: $progCount');

  if (warnings.isNotEmpty) {
    stdout.writeln('\nWarnings:');
    for (final w in warnings) {
      stdout.writeln('- $w');
    }
  } else {
    stdout.writeln('\nNo empty IDs found.');
  }

  // Optional sample: first 3 categories with up to 2 subcategories and 2 programs each
  stdout.writeln('\nSample output (up to first 3 categories):');
  for (var ci = 0; ci < catsJson.length && ci < 3; ci++) {
    final c = catsJson[ci] as Map<String, dynamic>;
    stdout.writeln('\nCategory ${ci + 1}: "${c['title']}" (id: "${c['id']}")');

    final subs = (c['subcategories'] as List<dynamic>?) ?? [];
    for (var si = 0; si < subs.length && si < 2; si++) {
      final s = subs[si] as Map<String, dynamic>;
      stdout.writeln('  Subcategory ${si + 1}: "${s['title']}" (id: "${s['id']}")');
      final progs = (s['programs'] as List<dynamic>?) ?? [];
      for (var pi = 0; pi < progs.length && pi < 2; pi++) {
        final p = progs[pi] as Map<String, dynamic>;
        stdout.writeln('    Program: "${p['name']}" (id: "${p['id']}")');
      }
    }

    final topProgs = (c['programs'] as List<dynamic>?) ?? [];
    for (var tpi = 0; tpi < topProgs.length && tpi < 2; tpi++) {
      final p = topProgs[tpi] as Map<String, dynamic>;
      stdout.writeln('  Top-level Program: "${p['name']}" (id: "${p['id']}")');
    }
  }

  // exit normally
}
