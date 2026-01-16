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

class CubeDeviceService {
  static final instance = CubeDeviceService._();
  CubeDeviceService._();

  Future<void> sendProgram({
    required ProgramItem program,
    required Duration duration,
    required bool powerMode,
  }) async {
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
    // might return CureProgram objects or CompositeItemPayloads depending
    // on implementation; handle both.
    final compositePayloads = payloads.map((p) {
      if (p is CompositeItemPayload) return p;
      if (p is CureProgram) return _toCompositeItemPayload(p);
      throw StateError('Unsupported payload item type: ${p.runtimeType}');
    }).toList(growable: false);

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
    required Duration Function(String programId) durationForId,
    required bool powerMode,
  }) async {
    // 1) Resolve slugs -> ProgramItems (enriched like single-flow)
    final programs = await MyProgramsCatalogResolver.resolveProgramItems(ids);

    if (programs.isEmpty) {
      throw StateError('Composite: playlist is empty (no programs resolved)');
    }

    // 2) Ensure catalog loaded
    await ProgramCatalog.instance.ensureLoaded();

    // 3) Build CureProgram payloads (one CureProgram per playlist item)
    final payloads = <CureProgram>[];

    for (final program in programs) {
      final entry =
          (program.uuid != null ? ProgramCatalog.instance.byUuid(program.uuid!) : null) ??
              (program.internalId != null ? ProgramCatalog.instance.byInternalId(program.internalId!) : null) ??
              ProgramCatalog.instance.byUuid(program.id) ??
              ProgramCatalog.instance.byInternalId(int.tryParse(program.id) ?? -1);

      if (entry == null) {
        throw StateError(
          'Composite: Program not found in catalog: slug=${program.id}, uuid=${program.uuid}, internalId=${program.internalId}',
        );
      }

      final duration = durationForId(program.id);
      final cureProgram = CureProgramFactory.fromCatalogEntry(
        entry: entry,
        duration: duration,
        powerMode: powerMode,
      );

      payloads.add(cureProgram);
    }

    // 4) Encode composite bytes using your existing Qt encoder
    // Convert CureProgram list to CompositeItemPayload list expected by encoder
    final compositePayloads = payloads.map((p) => _toCompositeItemPayload(p)).toList(growable: false);
    final bytes = encodeQtCompositeProgramBytes(compositePayloads);
    debugPrint('COMPOSITE(fromIds): items=${compositePayloads.length} bytes=${bytes.length}');

    final ok = await CureDeviceUnlockService.instance.uploadProgramBytes(bytes);
    if (!ok) {
      throw StateError('Composite: uploadProgramBytes failed');
    }

    final started = await CureDeviceUnlockService.instance.progStart();
    if (!started) {
      throw StateError('Composite: progStart failed');
    }
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
  Future<bool> stopProgram() async {
    // Delegate to the native unlock service progClear command.
    // Return the raw bool result from the native transport.
    return await CureDeviceUnlockService.instance.progClear();
  }
}
