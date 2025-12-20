import '../models/program_item.dart';
import 'cure_device_unlock_service.dart';
import 'program_catalog.dart';
import '../core/cure_protocol/cure_program_factory.dart';

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

    final ok = await CureDeviceUnlockService.instance
        .uploadProgramAndStart(cureProgram);

    if (!ok) {
      throw StateError('uploadProgramAndStart failed');
    }
  }

  // Minimal stopProgram: delegates to native shared progClear
  Future<bool> stopProgram() async {
    // Delegate to the native unlock service progClear command.
    // Return the raw bool result from the native transport.
    return await CureDeviceUnlockService.instance.progClear();
  }
}
