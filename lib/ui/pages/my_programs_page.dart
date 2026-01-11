import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hbcure/app_services.dart';
import 'package:hbcure/services/cure_device_unlock_service.dart';
import 'package:hbcure/i18n/program_name_localizer.dart';
import 'package:hbcure/services/program_language_controller.dart';
import 'package:hbcure/ui/widgets/player_popup.dart';

import '../../data/program_repository.dart';
import '../../models/program_item.dart';
import '../../services/my_programs_service.dart';
import '../widgets/gradient_background.dart';
import '../theme/app_colors.dart';
import 'program_detail_page.dart';
import '../../services/program_catalog.dart';

class MyProgramsPage extends StatefulWidget {
  const MyProgramsPage({super.key});

  @override
  State<MyProgramsPage> createState() => _MyProgramsPageState();
}

class _MyProgramsPageState extends State<MyProgramsPage> {
  final _service = MyProgramsService();
  final _repo = ProgramRepository();

  StreamSubscription<void>? _myProgramsSub;

  // Loading guard / queue flags
  bool _isLoading = false;
  bool _pendingReload = false;

  // Existing loading indicator and data
  bool _loading = true;
  List<ProgramItem> _programs = [];

  // name enrichment cache: programId -> display name (from asset catalog)
  final Map<String, String> _displayNameById = {};

  @override
  void initState() {
    super.initState();
    _loadPrograms();
    _myProgramsSub = _service.onChange.listen((_) {
      // schedule a reload; _loadPrograms itself will coalesce concurrent calls
      _loadPrograms();
    });
  }

  @override
  void dispose() {
    _myProgramsSub?.cancel();
    super.dispose();
  }

  Future<void> _loadPrograms() async {
    if (!mounted) return;
    if (_isLoading) {
      _pendingReload = true;
      return;
    }
    _isLoading = true;
    setState(() => _loading = true);
    try {
      final ids = await _service.loadIds();

      // load all categories and build id->ProgramItem map
      final categories = await _repo.loadCategories();
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

      final programs = <ProgramItem>[];
      for (final id in ids) {
        final p = map[id];
        if (p != null) programs.add(p);
      }

      // ---- name enrichment from Programs_decoded_full.json (optional) ----
      try {
        await ProgramCatalog.instance.ensureLoaded();
        _displayNameById.clear();
        for (final program in programs) {
          final current = program.name.trim();
          final isPlaceholder =
              current.isEmpty || current == '-' || current.toLowerCase() == 'placeholder';
          if (!isPlaceholder) {
            _displayNameById[program.id] = program.name;
            continue;
          }
          final byUuid = ProgramCatalog.instance.byUuid(program.id);
          if (byUuid != null) {
            _displayNameById[program.id] = ProgramCatalog.instance.name(byUuid, lang: 'EN');
            continue;
          }
          final intId = int.tryParse(program.id);
          if (intId != null) {
            final byInt = ProgramCatalog.instance.byInternalId(intId);
            if (byInt != null) {
              _displayNameById[program.id] = ProgramCatalog.instance.name(byInt, lang: 'EN');
              continue;
            }
          }
          _displayNameById[program.id] = program.name;
        }
      } catch (_) {
        // Non-fatal: if program catalog missing or parse fails, ignore enrichment
      }
      // -------------------------------------------------------------------

      if (!mounted) return;
      setState(() {
        _programs = programs;
      });
    } finally {
      if (!mounted) return;
      _isLoading = false;
      setState(() => _loading = false);
      if (_pendingReload) {
        _pendingReload = false;
        // schedule a single reload after current microtask
        Future.microtask(() => _loadPrograms());
      }
    }
  }

  Future<void> _remove(String id) async {
    await _service.remove(id);
    _loadPrograms();
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    // ReorderableListView gives newIndex as if the old item was already removed
    if (newIndex > oldIndex) newIndex -= 1;

    final ids = await _service.loadIds();
    if (ids.isEmpty) return;
    if (oldIndex < 0 || oldIndex >= ids.length) return;
    if (newIndex < 0 || newIndex >= ids.length) return;

    final moved = ids.removeAt(oldIndex);
    ids.insert(newIndex, moved);

    // Persist order (Source of Truth for playlist order)
    await _service.saveIds(ids);

    // Reload list to reflect order + keep enrichment consistent
    await _loadPrograms();
  }

  void _openPlayerPopup(BuildContext context) {
    final langCode = (ProgramLangController.instance.lang == ProgramLang.de) ? 'de' : 'en';

    String resolveTitle(String programId) {
      // Prefer explicit title from playerService cache, then local enrichment, then id
      final keyEn = playerService.titleKeyEnById[programId] ?? _displayNameById[programId] ?? programId;
      return ProgramNameLocalizer.instance.displayName(
        keyEn: keyEn,
        langCode: langCode,
      );
    }

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => PlayerPopup(
        player: playerService,
        resolveTitle: resolveTitle,
      ),
    );
  }

  void _playFromIndex(int index, BuildContext context) {
    final ids = _programs.map((p) => p.id).toList(growable: false);
    if (ids.isEmpty) return;

    // Build stable keyEn map: prefer p.name (usually EN from programs.json). If name is placeholder,
    // and we have enrichment (_displayNameById) use that as fallback.
    final keyEnMap = <String, String>{};
    for (final p in _programs) {
      keyEnMap[p.id] = p.name;
    }
    for (final p in _programs) {
      final current = p.name.trim();
      final isPlaceholder =
          current.isEmpty || current == '-' || current.toLowerCase() == 'placeholder';
      if (isPlaceholder && _displayNameById[p.id] != null) {
        keyEnMap[p.id] = _displayNameById[p.id]!;
      }
    }

    // Play with titleKeyEnById so Player has consistent titles for IDs
    try {
      playerService.playQueue(ids, index, titleKeyEnById: keyEnMap);
    } catch (_) {
      // Fallback to old call if signature not available at runtime
      playerService.playQueue(ids, index);
    }

    _openPlayerPopup(context);
  }

  @override
  Widget build(BuildContext context) {
    final langCode = (ProgramLangController.instance.lang == ProgramLang.de) ? 'de' : 'en';

    return GradientBackground(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
        child: ListView(
          padding: const EdgeInsets.only(bottom: 12.0),
          children: [
            Text(
              'My Programs',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(color: AppColors.textPrimary, fontSize: 18),
            ),
            const SizedBox(height: 6),

            if (_loading) ...[
              const SizedBox(height: 36),
              const Center(child: CircularProgressIndicator(color: AppColors.primary)),
            ] else if (_programs.isEmpty) ...[
              const SizedBox(height: 36),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.favorite_border, size: 64, color: AppColors.navBarInactive),
                    SizedBox(height: 10),
                    Text(
                      'Keine gespeicherten Programme',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ] else ...[
              const SizedBox(height: 4),

              // Important: keep existing outer ListView,
              // render reorderable list inside (shrinkWrap + no inner scrolling).
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _programs.length,
                onReorder: (oldIndex, newIndex) => _reorder(oldIndex, newIndex),
                itemBuilder: (context, index) {
                  final program = _programs[index];

                  final displayTitle = ProgramNameLocalizer.instance.displayName(
                    keyEn: _displayNameById[program.id] ?? program.name,
                    langCode: langCode,
                  );

                  return Padding(
                    key: ValueKey(program.id),
                    padding: const EdgeInsets.only(bottom: 6.0),
                    child: Material(
                      color: AppColors.cardBackground,
                      borderRadius: BorderRadius.circular(22),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(22),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ProgramDetailPage(
                                program: program,
                                deviceId: CureDeviceUnlockService
                                    .instance.nativeConnectedDeviceId ??
                                    '',
                              ),
                            ),
                          );
                          await _loadPrograms();
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.play_arrow),
                                color: AppColors.primary,
                                onPressed: () => _playFromIndex(index, context),
                              ),
                              const SizedBox(width: 4),

                              Expanded(
                                child: Text(
                                  displayTitle,
                                  style: const TextStyle(color: AppColors.textPrimary),
                                ),
                              ),

                              // Setup placeholder (Phase 1.5)
                              IconButton(
                                icon: const Icon(Icons.edit, color: AppColors.textSecondary),
                                onPressed: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Setup kommt in Phase 1.5'),
                                    ),
                                  );
                                },
                              ),

                              IconButton(
                                icon: const Icon(Icons.delete, color: AppColors.textSecondary),
                                onPressed: () async => _remove(program.id),
                              ),

                              // Drag handle: long-press/drag only for reorder (as requested)
                              ReorderableDragStartListener(
                                index: index,
                                child: const Icon(Icons.drag_handle,
                                    color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
