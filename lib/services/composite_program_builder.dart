import 'dart:typed_data';

import 'package:hbcure/data/program_repository.dart';
import 'package:hbcure/services/my_programs_service.dart';
import 'package:hbcure/services/player_service.dart';
import 'package:hbcure/services/program_catalog.dart';
import 'package:hbcure/models/program_item.dart';

import 'composite_program_types.dart';

class CompositeProgramBuilder {
  /// Build composite items from the user's MyPrograms list and per-item settings.
  ///
  /// Throws [StateError] if required source-of-truth data is missing (e.g. no
  /// frequencies for a program). It preserves the order returned by
  /// [MyProgramsService.loadIds()].
  Future<List<CompositeItemPayload>> buildFromMyPrograms({
    required MyProgramsService myPrograms,
    required PlayerService playerService,
    required ProgramCatalog catalog,
  }) async {
    final ids = await myPrograms.loadIds();
    final List<CompositeItemPayload> result = [];

    for (final id in ids) {
      // per-item settings
      final settings = playerService.settingsFor(id);

      // try to resolve catalog entry for this program id
      Map<String, dynamic>? entry;

      // 0) Prefer resolving by slug via ProgramRepository -> ProgramItem
      try {
        final repo = ProgramRepository();
        final cats = await repo.loadCategories();
        ProgramItem? found;
        for (final c in cats) {
          for (final p in c.programs) {
            if (p.id == id) {
              found = p;
              break;
            }
          }
          if (found != null) break;
          for (final s in c.subcategories) {
            for (final p in s.programs) {
              if (p.id == id) {
                found = p;
                break;
              }
            }
            if (found != null) break;
          }
          if (found != null) break;
        }
        if (found != null) {
          if (found.uuid != null && found.uuid!.isNotEmpty)
            entry = catalog.byUuid(found.uuid!);
          if (entry == null && found.internalId != null)
            entry = catalog.byInternalId(found.internalId!);
        }
      } catch (_) {
        // ignore repo errors and fallback to catalog lookups below
      }

      // Resolution order (explicit, minimal):
      // 1) try by slug/id as stored in programs.json
      // Note: ProgramCatalog does not expose a byId(slug) method. We already
      // attempted to resolve via ProgramRepository above. If still unresolved,
      // try byUuid(id) and byInternalId(id) as fallback.
      if (entry == null) entry = catalog.byUuid(id);
      if (entry == null) {
        final int? intId = int.tryParse(id);
        if (intId != null) entry = catalog.byInternalId(intId);
      }

      if (entry == null) {
        throw StateError('Catalog entry not found for program id=$id');
      }

      // obtain ProgramUUID string
      final String? uuidStr =
          (entry['ProgramUUID'] ?? entry['uuid'] ?? entry['ProgramUuid'])
              as String?;
      if (uuidStr == null || uuidStr.trim().isEmpty) {
        throw StateError('ProgramUUID missing for program id=$id');
      }

      final Uint8List uuid16 = _uuidToBytes(uuidStr);

      // name: prefer decoded Program EN name if available, else fallback to entry fields
      String name = '';
      final dynamic prog = entry['Program'];
      if (prog is Map) {
        name = (prog['EN'] ?? prog['EN']?.toString() ?? '').toString();
        if (name.trim().isEmpty)
          name = (prog['DE'] ?? prog['DE']?.toString() ?? '').toString();
      }
      if (name.trim().isEmpty) {
        name = (entry['name'] ?? entry['Name'] ?? id).toString();
      }

      // frequencies: read List<num> from entry['Frequencies'] (exact original order)
      final freqsRaw =
          entry['Frequencies'] ??
          entry['frequencies'] ??
          entry['FREQ'] ??
          entry['Freq'];
      final List<double> freqs = <double>[];
      if (freqsRaw is List) {
        for (final f in freqsRaw) {
          if (f is num) {
            freqs.add(f.toDouble());
          } else if (f is String) {
            final parsed = double.tryParse(f);
            if (parsed != null) freqs.add(parsed);
          }
        }
      }

      if (freqs.isEmpty) {
        throw StateError(
          'No frequencies found for program id=$id (catalog entry lacks Frequencies)',
        );
      }

      // compute duration and split into steps
      final int durationSec = (settings.durationMinutes * 60);
      final int n = freqs.length;
      final int base = (n > 0) ? (durationSec ~/ n) : 0;
      final int delta = durationSec - (base * n);

      final List<CompositeStep> steps = <CompositeStep>[];
      for (int i = 0; i < n; i++) {
        final int dwell = (i == 0) ? (base + delta) : base;
        // Defensive clamp to uint16 range required by firmware
        final int dwell16 = dwell.clamp(0, 65535);
        steps.add(CompositeStep(freqHz: freqs[i], dwellSec: dwell16));
      }

      // intensity nibble mapping: settings.intensity (1..100) -> 0..10 nibble
      int nibble = ((settings.intensity / 10.0).round()).clamp(0, 10);

      final int eInt = settings.electric ? nibble : 0;
      final int hInt = settings.magnetic ? nibble : 0;

      final int eWave = settings.electric
          ? (settings.electricWaveform.index & 0x0F)
          : 0;
      final int hWave = settings.magnetic
          ? (settings.magneticWaveform.index & 0x0F)
          : 0;

      final payload = CompositeItemPayload(
        uuid16: uuid16,
        name: name,
        eInt0to10: eInt,
        hInt0to10: hInt,
        eWave0to15: eWave,
        hWave0to15: hWave,
        steps: steps,
      );

      result.add(payload);
    }

    return result;
  }
}

Uint8List _uuidToBytes(String uuid) {
  final hex = uuid.replaceAll('-', '').replaceAll(RegExp(r"[^0-9A-Fa-f]"), '');
  if (hex.length != 32) {
    throw ArgumentError(
      'UUID must contain 16 bytes (32 hex chars) after removing dashes: "$uuid"',
    );
  }
  final bytes = Uint8List(16);
  for (int i = 0; i < 16; i++) {
    bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return bytes;
}
