import '../models/program_item.dart';
import 'cure_device_unlock_service.dart';
import 'program_catalog.dart';
import '../core/cure_protocol/cure_program_factory.dart';
import 'my_programs_service.dart';
import 'player_service.dart';
import 'composite_program_builder.dart';
import 'qt_remote_composite_program_encoder.dart';
import 'package:hbcure/app_services.dart';
import 'package:flutter/foundation.dart';
import 'my_programs_catalog_resolver.dart';
import '../core/cure_protocol/cure_program_model.dart';
import 'composite_program_types.dart';
import '../models/playlist_item_settings.dart';
import 'custom_frequencies_store.dart';
import 'dart:convert';

class CubeDeviceService {
  static final instance = CubeDeviceService._();
  CubeDeviceService._();

  Future<void> sendProgram({
    required ProgramItem program,
    required Duration duration,
    required bool powerMode,
  }) async {
    // Special-case: custom single-frequency programs stored locally (id startsWith 'custom_')
    if (program.id.startsWith('custom_')) {
      final e = await CustomFrequenciesStore.instance.getById(program.id);
      if (e == null) {
        throw StateError('Custom program not found: id=${program.id}');
      }

      // Build a CureProgram using the factory's singleFrequency variant
      final cureProgram = CureProgramFactory.singleFrequency(
        customId: e.id,
        name: e.name,
        frequencyHz: e.frequencyHz,
        duration: Duration(minutes: e.durationMin),
        intensityPct: e.intensityPct,
        powerMode: powerMode,
        useElectric: e.useElectric,
        electricWaveform: e.electricWaveform,
        useMagnetic: e.useMagnetic,
        magneticWaveform: e.magneticWaveform,
      );

      final ok = await CureDeviceUnlockService.instance.uploadProgramAndStart(
        cureProgram,
      );

      if (!ok) {
        throw StateError('uploadProgramAndStart (custom) failed');
      }
      return;
    }

    await ProgramCatalog.instance.ensureLoaded();

    final entry =
        // 1) Bevorzugt: explizite UUID aus ProgramItem
        (program.uuid != null
            ? ProgramCatalog.instance.byUuid(program.uuid!)
            : null) ??
        // 2) Danach: explizite internalId aus ProgramItem
        (program.internalId != null
            ? ProgramCatalog.instance.byInternalId(program.internalId!)
            : null) ??
        // 3) Fallback: id als UUID interpretieren
        ProgramCatalog.instance.byUuid(program.id) ??
        // 4) Fallback: id als internalId interpretieren
        ProgramCatalog.instance.byInternalId(int.tryParse(program.id) ?? -1);

    if (entry == null) {
      throw StateError(
        'Program not found: '
        'slug=${program.id}, '
        'uuid=${program.uuid}, '
        'internalId=${program.internalId}',
      );
    }

    final cureProgram = CureProgramFactory.fromCatalogEntry(
      entry: entry,
      duration: duration,
      powerMode: powerMode,
    );

    final ok = await CureDeviceUnlockService.instance.uploadProgramAndStart(
      cureProgram,
    );

    if (!ok) {
      throw StateError('uploadProgramAndStart failed');
    }
  }

  /// Build the current MyPrograms playlist into ONE Qt-compatible program binary
  /// and upload it once (progClear/progAppend/progStart flow stays unchanged).
  Future<void> sendMyProgramsAsComposite() async {
    await ProgramCatalog.instance.ensureLoaded();

    // Proof debug output (short tags)
    debugPrint('COMPOSITE: enter');

    final myPrograms = MyProgramsService();
    final ids = await myPrograms.loadIds();
    debugPrint('COMPOSITE: ids=${ids.length} $ids');
    if (ids.isEmpty) return;

    final payloads = await CompositeProgramBuilder().buildFromMyPrograms(
      myPrograms: myPrograms,
      playerService: playerService,
      catalog: ProgramCatalog.instance,
    );
    // show how many payload items were built
    debugPrint('COMPOSITE: payloads=${payloads.length}');

    // Ensure we have List<CompositeItemPayload> for encoder. The builder
    // returns CompositeItemPayload items; cast defensively to the expected type.
    final compositePayloads = payloads.cast<CompositeItemPayload>().toList(growable: false);

    final bytes = encodeQtCompositeProgramBytes(compositePayloads);
    debugPrint('COMPOSITE: bytes=${bytes.length}');

    final ok = await CureDeviceUnlockService.instance.uploadProgramBytes(bytes);
    debugPrint('COMPOSITE: upload ok=$ok');
    if (!ok) {
      throw StateError('uploadProgramBytes failed');
    }

    final started = await CureDeviceUnlockService.instance.progStart();
    debugPrint('COMPOSITE: start ok=$started');
    if (!started) {
      throw StateError('progStart failed');
    }
  }

  /// Build and upload a composite program from provided playlist IDs.
  Future<void> sendMyProgramsCompositeFromIds({
    required List<String> ids,
    required PlaylistItemSettings Function(String programId) settingsForId,
    required bool powerMode,
  }) async {
    // Debug: incoming ids
    debugPrint('COMPOSITE: ids=${ids.length}');

    // 1) Resolve slugs -> ProgramItems (enriched like single-flow)
    final programs = await MyProgramsCatalogResolver.resolveProgramItems(ids);
    // Debug: how many resolved
    debugPrint('COMPOSITE: resolved programs=${programs.length}');

    if (programs.isEmpty) {
      throw StateError('Composite: playlist is empty (no programs resolved)');
    }

    // 2) Ensure catalog loaded
    await ProgramCatalog.instance.ensureLoaded();

    // 3) Build CompositeItemPayload list (one payload per playlist item)
    final compositePayloads = <CompositeItemPayload>[];

    for (final program in programs) {
      final entry =
          (program.uuid != null ? ProgramCatalog.instance.byUuid(program.uuid!) : null) ??
          (program.internalId != null ? ProgramCatalog.instance.byInternalId(program.internalId!) : null) ??
          ProgramCatalog.instance.byUuid(program.id) ??
          ProgramCatalog.instance.byInternalId(int.tryParse(program.id) ?? -1);

      if (entry == null) {
        throw StateError(
          'Composite: Program not found in catalog: '
          'slug=${program.id}, uuid=${program.uuid}, internalId=${program.internalId}',
        );
      }

      final s = settingsForId(program.id);
      final duration = Duration(minutes: s.durationMinutes);

      // Factory: build CureProgram (ensures same encoding as single-upload)
      final cureProgram = CureProgramFactory.fromCatalogEntry(
        entry: entry,
        duration: duration,
        powerMode: powerMode,
      );

      // DEBUG: log CureProgram step count + total dwell
      final totalDwellCp = cureProgram.steps.fold<int>(0, (a, st) => a + st.dwellSeconds);
      debugPrint('COMPOSITE_ITEM: id=${program.id} steps=${cureProgram.steps.length} totalDwellCpSec=$totalDwellCp durMin=${s.durationMinutes}');

      final payload = _toCompositeItemPayloadWithSettings(cureProgram, s);

      // DEBUG: log payload step count + total dwell
      final totalDwellPayload = payload.steps.fold<int>(0, (a, st) => a + st.dwellSec);
      debugPrint('COMPOSITE_PAYLOAD: id=${program.id} steps=${payload.steps.length} totalDwellPayloadSec=$totalDwellPayload');

      compositePayloads.add(payload);
    }

    // Debug: payloads count
    debugPrint('COMPOSITE: payloads=${compositePayloads.length}');

    // Original-app style upload: clear, then progAppend per item, then progStart
    debugPrint('COMPOSITE: progClear()');
    final cleared = await CureDeviceUnlockService.instance.progClear();
    debugPrint('COMPOSITE: progClear ok=$cleared');
    if (!cleared) throw StateError('Composite: progClear failed');

    for (final item in compositePayloads) {
      final bytes = encodeQtCompositeProgramBytes([item]);
      debugPrint('COMPOSITE: progAppend bytes=${bytes.length}');
      final ok = await CureDeviceUnlockService.instance.appendProgramBytes(bytes);
      debugPrint('COMPOSITE: progAppend ok=$ok');
      if (!ok) throw StateError('Composite: progAppend failed');
    }

    final started = await CureDeviceUnlockService.instance.progStart();
    debugPrint('COMPOSITE: progStart ok=$started');
    if (!started) throw StateError('Composite: progStart failed');
  }

  // ---------------------- Helpers ----------------------
  // Convert CureProgram -> CompositeItemPayload (used by encoder)
  CompositeItemPayload _toCompositeItemPayload(CureProgram p) {
    final steps = <CompositeStep>[];
    for (final s in p.steps) {
      final dwell = s.dwellSeconds.clamp(0, 0xFFFF);
      steps.add(CompositeStep(freqHz: s.frequencyHz, dwellSec: dwell));
    }

    // Use CureProgram getters (defined in cure_program_model.dart)
    final int eInt = (p.eIntensity0to10).clamp(0, 10);
    final int hInt = (p.hIntensity0to10).clamp(0, 10);

    final int eWave = _waveToCode(p.eWaveForm);
    final int hWave = _waveToCode(p.hWaveForm);

    return CompositeItemPayload(
      uuid16: p.uuid16,
      name: p.name,
      eInt0to10: eInt,
      hInt0to10: hInt,
      eWave0to15: eWave,
      hWave0to15: hWave,
      steps: steps,
    );
  }

  // Convert CureProgram + per-item UI settings -> CompositeItemPayload
  CompositeItemPayload _toCompositeItemPayloadWithSettings(CureProgram p, PlaylistItemSettings s) {
    final steps = <CompositeStep>[];
    for (final st in p.steps) {
      final dwell = st.dwellSeconds.clamp(0, 0xFFFF);
      steps.add(CompositeStep(freqHz: st.frequencyHz, dwellSec: dwell));
    }

    // UI intensity 0..100 -> protocol 0..10
    final intBase = (s.intensity / 10.0).round().clamp(0, 10);
    final eInt = s.electric ? intBase : 0;
    final hInt = s.magnetic ? intBase : 0;

    final eWave = s.electric ? _waveToCodeFromName(s.electricWaveform.name) : 0;
    final hWave = s.magnetic ? _waveToCodeFromName(s.magneticWaveform.name) : 0;

    return CompositeItemPayload(
      uuid16: p.programUuid16,
      name: p.name,
      eInt0to10: eInt,
      hInt0to10: hInt,
      eWave0to15: eWave,
      hWave0to15: hWave,
      steps: steps,
    );
  }

  // Map waveform enum/name -> protocol code (0..15)
  int _waveToCodeFromName(String name) {
    final n = name.trim().toLowerCase();
    switch (n) {
      case 'sine':
        return 0;
      case 'square':
        return 1;
      case 'triangle':
        return 2;
      case 'saw':
      case 'sawtooth':
        return 3;
      case 'pulse':
        return 4;
      default:
        return 0;
    }
  }

  int _waveToCode(dynamic w) {
    // Accept different enum types/names or numeric values; map to 0..15
    try {
      if (w == null) return 0;
      // numeric already
      if (w is int) return (w & 0x0F);
      if (w is CureWaveForm) return (w.index & 0x0F);
      final name = w.toString().toLowerCase();
      if (name.contains('sine')) return 0;
      if (name.contains('triangle')) return 1;
      if (name.contains('rect') || name.contains('rectangular') || name.contains('square')) return 2;
      if (name.contains('saw')) return 3;
      final parsed = int.tryParse(name);
      if (parsed != null) return (parsed & 0x0F);
    } catch (_) {}
    return 0;
  }

  // Minimal stopProgram: delegates to native shared progClear
  /// Stop the running program on the Cube device.
  /// Uses the underlying native command to clear/stop the running program.
  /// Throws StateError on failure.
  Future<void> stopProgram() async {
    final ok = await CureDeviceUnlockService.instance.progClear();
    if (!ok) {
      throw StateError('progClear (stop) failed');
    }
  }

  // ---------------------- NEW: Merged-Single Upload ----------------------
  /// Build a single merged CureProgram from playlist ids and upload it as ONE program.
  Future<void> sendMyProgramsAsMergedSingleFromIds({
    required List<String> ids,
    required PlaylistItemSettings Function(String programId) settingsForId,
    required bool powerMode,
  }) async {
    debugPrint('MERGED: enter ids=${ids.length}');
    if (ids.isEmpty) return;

    // Resolve ProgramItems from slugs/ids (used as a lookup map for non-custom ids)
    final resolvedPrograms = await MyProgramsCatalogResolver.resolveProgramItems(ids);
    final byId = <String, ProgramItem>{};
    for (final p in resolvedPrograms) {
      byId[p.id] = p;
    }
    debugPrint('MERGED: resolved programs=${resolvedPrograms.length}');

    await ProgramCatalog.instance.ensureLoaded();

    final mergedSteps = <CureFrequencyStep>[];
    CureIntensity? chosenIntensity;
    CureWaveForms? chosenWaveForms;

    for (final id in ids) {
      // Use the provided PlaylistItemSettings for this id (UI settings)
      final playlistSettings = settingsForId(id);
      final playlistDuration = Duration(minutes: playlistSettings.durationMinutes);
      final dwell = playlistDuration.inSeconds.clamp(1, 0xFFFF);

      // [PLAYLIST_TIME] diagnostic: per-item upload values
      debugPrint('[PLAYLIST_TIME] UPLOAD id=$id uiDurMin=${playlistSettings.durationMinutes} uiDurSec=${playlistDuration.inSeconds} clampedDwell=$dwell');

      if (id.startsWith('custom_')) {
        // Custom entry stored locally
        final ce = await CustomFrequenciesStore.instance.getById(id);
        if (ce == null) {
          throw StateError('Merged: custom entry not found: $id');
        }

        // Single step for custom entry
        mergedSteps.add(CureFrequencyStep(
          frequencyHz: ce.frequencyHz,
          dwellSeconds: dwell,
        ));

        // Choose global intensity/waveforms from first encountered item (custom uses UI settings)
        if (chosenIntensity == null) {
          final intBase = (playlistSettings.intensity / 10.0).round().clamp(0, 10);
          // PlaylistItemSettings does not expose eNibble/hNibble; derive from intensity + channel flags
          final eNib = playlistSettings.electric ? intBase : 0;
          final hNib = playlistSettings.magnetic ? intBase : 0;
          chosenIntensity = CureIntensity(eNibble: eNib, hNibble: hNib);
        }
        if (chosenWaveForms == null) {
          chosenWaveForms = CureWaveForms(
            e: _waveFromName(playlistSettings.electricWaveform.name),
            h: _waveFromName(playlistSettings.magneticWaveform.name),
          );
        }

        debugPrint('MERGED_ITEM: id=$id (custom) steps=1 totalDwellSec=$dwell durMin=${playlistSettings.durationMinutes}');
        continue;
      }

      // Non-custom: resolve ProgramItem (must have been in resolved map)
      final program = byId[id];
      if (program == null) {
        throw StateError('Merged: program not resolved: $id');
      }

      final entry =
          (program.uuid != null ? ProgramCatalog.instance.byUuid(program.uuid!) : null) ??
          (program.internalId != null ? ProgramCatalog.instance.byInternalId(program.internalId!) : null) ??
          ProgramCatalog.instance.byUuid(program.id) ??
          ProgramCatalog.instance.byInternalId(int.tryParse(program.id) ?? -1);

      if (entry == null) {
        throw StateError(
          'Merged: Program not found in catalog: slug=${program.id}, uuid=${program.uuid}, internalId=${program.internalId}',
        );
      }

      final s = settingsForId(program.id);
      final duration = Duration(minutes: s.durationMinutes);

      // Factory: build CureProgram (ensures same encoding as single-upload)
      final cureProgram = CureProgramFactory.fromCatalogEntry(
        entry: entry,
        duration: duration,
        powerMode: powerMode,
      );

      final itemDwell = cureProgram.steps.fold<int>(0, (a, st) => a + st.dwellSeconds);
      // [PLAYLIST_TIME] diagnostic: compare configured vs actual dwell
      debugPrint('[PLAYLIST_TIME] UPLOAD_FACTORY id=${program.id} configuredDurSec=${duration.inSeconds} actualDwellSec=$itemDwell steps=${cureProgram.steps.length} delta=${itemDwell - duration.inSeconds}s');
      debugPrint('MERGED_ITEM: id=${program.id} steps=${cureProgram.steps.length} totalDwellSec=$itemDwell durMin=${s.durationMinutes}');

      mergedSteps.addAll(cureProgram.steps);

      // take global intensity/waveforms from first program if not yet set
      chosenIntensity ??= cureProgram.intensity;
      chosenWaveForms ??= cureProgram.waveForms;
    }

    if (mergedSteps.isEmpty) {
      throw StateError('Merged: no steps built');
    }

    final totalDwell = mergedSteps.fold<int>(0, (a, st) => a + st.dwellSeconds);
    debugPrint('MERGED: totalSteps=${mergedSteps.length} totalDwellSec=$totalDwell');

    // [PLAYLIST_TIME] diagnostic: final merged totals
    {
      int expectedSec = 0;
      for (final id in ids) {
        expectedSec += settingsForId(id).durationMinutes * 60;
      }
      debugPrint('[PLAYLIST_TIME] UPLOAD_FINAL expectedTotalSec=$expectedSec actualMergedDwellSec=$totalDwell deltaSec=${totalDwell - expectedSec}');
    }

    // stable 16-byte id for merged program
    final mergedUuid = _uuid16FromString('merged:${ids.join(',')}');

    final mergedProgram = CureProgram(
      programUuid16: mergedUuid,
      name: 'My Programs (Merged)',
      intensity: chosenIntensity ?? CureIntensity(eNibble: 5, hNibble: 5),
      waveForms: chosenWaveForms ?? CureWaveForms(e: CureWaveForm.sine, h: CureWaveForm.sine),
      steps: mergedSteps,
    );

    debugPrint('MERGED: uploading merged program (steps=${mergedProgram.steps.length})');

    final ok = await CureDeviceUnlockService.instance.uploadProgramAndStart(mergedProgram);
    debugPrint('MERGED: upload ok=$ok');
    if (!ok) {
      throw StateError('Merged: uploadProgramAndStart failed');
    }
  }

  // ---------------------- Helper implementations ----------------------
  CureWaveForm _waveFromName(String name) {
    final n = name.trim().toLowerCase();

    if (n.contains('sine')) return CureWaveForm.sine;
    if (n.contains('triangle')) return CureWaveForm.triangle;
    if (n.contains('square') || n.contains('rect')) return CureWaveForm.square;

    // Fallback-Mappings für nicht vorhandene Enum-Werte
    if (n.contains('saw')) return CureWaveForm.triangle;
    if (n.contains('pulse')) return CureWaveForm.square;

    return CureWaveForm.sine;
  }

  // Helper: produce deterministic 16-byte id from a string (same algorithm as factory)
  Uint8List _uuid16FromString(String s) {
    // BigInt-based FNV-1a 64-bit implementation (web-safe)
    BigInt fnv1a64(List<int> bytes, BigInt seed) {
      final BigInt fnvPrime = BigInt.parse('100000001b3', radix: 16);
      final BigInt mask64 = BigInt.parse('FFFFFFFFFFFFFFFF', radix: 16);
      BigInt hash = seed & mask64;
      for (final b in bytes) {
        hash = (hash ^ BigInt.from(b));
        hash = (hash * fnvPrime) & mask64;
      }
      return hash;
    }

    final bytes = utf8.encode(s);
    final h1 = fnv1a64(bytes, BigInt.parse('cbf29ce484222325', radix: 16));
    final h2 = fnv1a64(bytes, BigInt.parse('84222325cbf29ce4', radix: 16));

    final out = ByteData(16);
    // write little-endian 8 bytes from BigInt values
    for (int i = 0; i < 8; i++) {
      out.setUint8(i, ((h1 >> (8 * i)) & BigInt.from(0xFF)).toInt());
    }
    for (int i = 0; i < 8; i++) {
      out.setUint8(8 + i, ((h2 >> (8 * i)) & BigInt.from(0xFF)).toInt());
    }
    return out.buffer.asUint8List();
  }

}
