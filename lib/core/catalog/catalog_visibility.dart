import 'package:flutter/foundation.dart';

import 'package:hbcure/core/program_mode.dart';
import 'catalog_color.dart';

int maxLevelForMode(ProgramMode mode) {
  switch (mode) {
    case ProgramMode.beginner:
      return 1;
    case ProgramMode.advanced:
      return 2;
    case ProgramMode.expert:
      return 3;
  }
}

bool allowYellowForMode(ProgramMode mode) {
  return mode != ProgramMode.beginner;
}

int parseProgramLevel(dynamic v) {
  if (v == null) return 1;
  if (v is int) return v;
  final s = v.toString().trim();
  return int.tryParse(s) ?? 1;
}

bool isNodeVisible({
  required ProgramMode mode,
  required CatalogColor color,
  required int level,
}) {
  // TEMP DEBUG (remove after verification)
  debugPrint('[VIS] mode=${mode.name} color=$color level=$level');

  if (color == CatalogColor.yellow && !allowYellowForMode(mode)) return false;
  return level <= maxLevelForMode(mode);
}
