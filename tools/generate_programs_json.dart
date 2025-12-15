// Tool to parse raw program text and generate assets/programs.json
// Run: dart run tools/generate_programs_json.dart

import 'dart:convert';
import 'dart:io';

// Liste der bekannten Hauptkategorien genau wie im Rohtext
const List<String> knownCategories = [
  'Animals',
  'Antiparasitic',
  'General Energy, Vitalisation',
  'Pain',
  'Set of Programs',
  'Seven Chakras',
  'Acupuncture',
];

// Forbidden normalized tokens for subcategories / programs
const List<String> _forbiddenNorms = [
  'programme',
  'programme_',
  'programs',
  'program',
  '',
  // additional forbidden tokens requested
  'allergie',
  'unterordner',
  'unterordner_',
  'unterordner:',
  'unterordner:_',
];

String normalize(String text) {
  var s = text.trim().toLowerCase();
  // Umlaute
  s = s.replaceAll('ä', 'ae').replaceAll('ö', 'oe').replaceAll('ü', 'ue').replaceAll('ß', 'ss');
  // Replace spaces, slashes, hyphens with underscore
  s = s.replaceAll(RegExp(r"[\s/\-]+"), '_');
  // Remove any character not a-z, 0-9 or _
  s = s.replaceAll(RegExp(r'[^a-z0-9_]'), '');
  // Collapse multiple underscores
  s = s.replaceAll(RegExp(r'_+'), '_');
  // Trim leading/trailing _
  s = s.replaceAll(RegExp(r'^_+|_+$'), '');
  return s;
}

class ProgramItemJson {
  final String id;
  final String name;
  ProgramItemJson({required this.id, required this.name});
  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}

class ProgramSubcategoryJson {
  final String id;
  final String title;
  final List<ProgramItemJson> programs;
  ProgramSubcategoryJson({required this.id, required this.title, List<ProgramItemJson>? programs}) : programs = programs ?? [];
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'programs': programs.map((p) => p.toJson()).toList(),
      };
}

class ProgramCategoryJson {
  final String id;
  final String title;
  final List<ProgramSubcategoryJson> subcategories;
  final List<ProgramItemJson> programs;
  ProgramCategoryJson({required this.id, required this.title, List<ProgramSubcategoryJson>? subcategories, List<ProgramItemJson>? programs})
      : subcategories = subcategories ?? [],
        programs = programs ?? [];
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'subcategories': subcategories.map((s) => s.toJson()).toList(),
        'programs': programs.map((p) => p.toJson()).toList(),
      };
}

void main(List<String> args) async {
  // Read raw data from tools/programs_raw.txt (external file)
  final inputFile = File('tools/programs_raw.txt');
  if (!inputFile.existsSync()) {
    stderr.writeln('ERROR: tools/programs_raw.txt not found');
    exit(1);
  }
  final rawData = inputFile.readAsStringSync();

  // Preprocess rawData: replace tabs and multiple spaces with newlines to separate tokens/sections
  var pre = rawData.replaceAll(RegExp(r'[\t]| {2,}'), '\n');
  // Normalize various dashes to hyphen
  pre = pre.replaceAll('—', '-').replaceAll('–', '-');
  // Now split into non-empty trimmed lines
  final lines = pre.split(RegExp(r"\r?\n")).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

  final List<ProgramCategoryJson> categories = [];
  ProgramCategoryJson? currentCategory;
  ProgramSubcategoryJson? currentSubcategory;
  bool expectingSubcategoryList = false;
  bool readingPrograms = false;

  // For numbering program ids
  final Map<String, int> baseCounts = {};

  ProgramCategoryJson startNewCategory(String title) {
    final id = normalize(title);
    // reuse existing category with same id if present
    final existing = categories.firstWhere((c) => c.id == id, orElse: () => ProgramCategoryJson(id: id, title: title));
    if (!categories.any((c) => c.id == existing.id)) {
      categories.add(existing);
    }
    return existing;
  }

  ProgramSubcategoryJson? startNewSubcategory(ProgramCategoryJson category, String title) {
    final id = normalize(title);
    // if normalized id is forbidden, do not add this subcategory
    if (_forbiddenNorms.contains(id)) {
      return null;
    }
    // reuse existing subcategory with same id if present in this category
    final existing = category.subcategories.firstWhere((s) => s.id == id, orElse: () => ProgramSubcategoryJson(id: id, title: title));
    if (!category.subcategories.any((s) => s.id == existing.id)) {
      category.subcategories.add(existing);
    }
    return existing;
  }

  List<String> splitPotentialListLine(String line) {
    // Split by tabs or 2+ spaces
    final parts = line.split(RegExp(r'\t|\s{2,}'));
    return parts
        .map((p) => p.trim())
        .where((p) {
          if (p.isEmpty) return false;
          final low = p.toLowerCase();
          // ignore tokens that are just punctuation or the word 'programme'
          if (RegExp(r'^[:\-]+$').hasMatch(p)) return false;
          if (low == 'programme' || low == 'programme:' || low == ':') return false;
          return true;
        })
        .toList();
  }

  // Helper to add program
  void addProgram(ProgramCategoryJson category, ProgramSubcategoryJson? sub, String programName) {
    final trimmed = programName.trim();
    final low = trimmed.toLowerCase();
    // discard trivial/forbidden program tokens
    final forbiddenProgramSet = {'programme', 'programme:', 'programme_', 'programs', 'program', ':', '::'};
    if (trimmed.isEmpty) return;
    if (forbiddenProgramSet.contains(low)) return;
    final catId = category.id;
    final subIdPart = sub != null ? '_${sub.id}' : '';
    final progNorm = normalize(programName);
    if (_forbiddenNorms.contains(progNorm)) return; // extra safety: don't add programs whose normalized token is forbidden
    final base = '${catId}${subIdPart}_$progNorm';
    final count = (baseCounts[base] ?? 0) + 1;
    baseCounts[base] = count;
    final id = '${base}_$count';
    final item = ProgramItemJson(id: id, name: programName);
    if (sub != null) {
      sub.programs.add(item);
    } else {
      category.programs.add(item);
    }
  }

  // iterate lines
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final low = line.toLowerCase();

    // Detect explicit "Ein unterordner mit acupuncture" -> category Acupuncture
    if (line.toLowerCase().contains('ein unterordner') && line.toLowerCase().contains('acupuncture')) {
      currentCategory = startNewCategory('Acupuncture');
      currentSubcategory = null;
      expectingSubcategoryList = false;
      readingPrograms = true; // next tokens are programs
      final rest = line.replaceAll(RegExp('ein unterordner mit acupuncture\\s*[-:]*\\s*programme:?', caseSensitive: false), '').trim();
      if (rest.isNotEmpty) {
        final parts = splitPotentialListLine(rest);
        for (var p in parts) addProgram(currentCategory, null, p);
      }
      continue;
    }

    // If line matches a known category (exact or startsWith), start a new category
    bool started = false;
    for (var catName in knownCategories) {
      if (line.toLowerCase() == catName.toLowerCase() || line.toLowerCase().startsWith(catName.toLowerCase())) {
        currentCategory = startNewCategory(catName);
        currentSubcategory = null;
        expectingSubcategoryList = line.toLowerCase().contains('unterordner');
        readingPrograms = line.toLowerCase().contains('programme');
        started = true;
        break;
      }
    }
    if (started) continue;

    // If line contains ': unterordner' and mentions a known category, start it
    if (low.contains(':') && low.contains('unterordner')) {
      for (var catName in knownCategories) {
        if (low.contains(catName.toLowerCase())) {
          currentCategory = startNewCategory(catName);
          currentSubcategory = null;
          expectingSubcategoryList = true;
          readingPrograms = false;
          started = true;
          break;
        }
      }
      if (started) continue;
    }

    // Detect subcategory header like 'Allergie:Programme' or 'Arthrology: Programme'
    if (low.contains('programme')) {
      // extract potential title before 'programme'
      final idx = low.indexOf('programme');
      final before = line.substring(0, idx).replaceAll(RegExp(r'[:\-]+'), '').trim();
      if (before.isNotEmpty && currentCategory != null) {
        // ensure normalized id is not empty and not a forbidden token
        final normBefore = normalize(before);
        if (normBefore.isNotEmpty && !_forbiddenNorms.contains(normBefore)) {
          // treat as subcategory header
          final sub = startNewSubcategory(currentCategory, before);
          if (sub != null) {
            currentSubcategory = sub;
            readingPrograms = true;
            expectingSubcategoryList = false;
          }
        }
        continue;
      }
    }

    // If we are expecting subcategory list, parse this line as list of subcategory titles
    if (expectingSubcategoryList && currentCategory != null) {
      final subs = splitPotentialListLine(line);
      if (subs.isNotEmpty) {
        for (var s in subs) {
          final normS = normalize(s);
          if (normS.isEmpty) continue;
          if (_forbiddenNorms.contains(normS)) continue; // skip 'Programme' artefacts and other forbidden tokens
          final sub = startNewSubcategory(currentCategory, s);
          // if sub is null it was forbidden and skipped
        }
        expectingSubcategoryList = false;
        continue;
      }
    }

    // If we are reading programs, parse program names from this line
    if (readingPrograms && currentCategory != null) {
      // If line likely contains multiple program names (split by tabs or multiple spaces)
      final parts = splitPotentialListLine(line);
      if (parts.length > 1) {
        for (var p in parts) addProgram(currentCategory, currentSubcategory, p);
        continue;
      }
      // Otherwise treat the whole line as one program name
      addProgram(currentCategory, currentSubcategory, line);
      continue;
    }

    // Heuristic: some lines may be lists of programs without entering reading mode
    final parts = splitPotentialListLine(line);
    if (parts.length > 1 && currentCategory != null) {
      for (var p in parts) addProgram(currentCategory, currentSubcategory, p);
      continue;
    }

    // If none matched, ignore line
  }

  final root = {
    'rootTitle': 'Available Programs',
    'categories': categories.map((c) => c.toJson()).toList(),
  };

  // Statistics: count categories, subcategories, programs
  int catCount = categories.length;
  int subCount = 0;
  int progCount = 0;
  for (final c in categories) {
    subCount += c.subcategories.length;
    progCount += c.programs.length;
    for (final s in c.subcategories) {
      progCount += s.programs.length;
    }
  }

  // write stats to tools/programs_stats.txt for reliable retrieval
  final statsFile = File('tools/programs_stats.txt');
  statsFile.writeAsStringSync('Categories: $catCount\nSubcategories: $subCount\nPrograms: $progCount\n');

  stdout.writeln('Categories: $catCount');
  stdout.writeln('Subcategories: $subCount');
  stdout.writeln('Programs: $progCount');

  final out = const JsonEncoder.withIndent('  ').convert(root);

  // Ensure assets directory exists
  final assetsDir = Directory('assets');
  if (!assetsDir.existsSync()) assetsDir.createSync(recursive: true);

  final outFile = File('assets/programs.json');
  outFile.writeAsStringSync(out);

  print('Wrote ${outFile.path}');
  print('Generated assets/programs.json from tools/programs_raw.txt');
  print('--- JSON OUTPUT START ---');
  print(out);
  print('--- JSON OUTPUT END ---');
}
