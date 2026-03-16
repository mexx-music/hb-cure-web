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
import 'package:hbcure/services/custom_frequency_name_store.dart';
import '../widgets/playlist_item_setup.dart';
import '../../services/cube_device_service.dart';
import 'package:hbcure/services/custom_frequencies_store.dart';
import 'package:hbcure/services/clients_store.dart';

class MyProgramsPage extends StatefulWidget {
  const MyProgramsPage({super.key});

  @override
  State<MyProgramsPage> createState() => _MyProgramsPageState();
}

class _MyProgramsPageState extends State<MyProgramsPage> {
  late final MyProgramsService _mySvc;
  VoidCallback? _myListener;
  final _repo = ProgramRepository();

  bool _isLoading = false;
  bool _pendingReload = false;

  bool _loading = true;
  List<ProgramItem> _programs = [];

  // name enrichment cache: programId -> display name (from asset catalog)
  final Map<String, String> _displayNameById = {};
  String? _activeClientName;

  Future<void> _refreshActiveClientName() async {
    try {
      final activeId = await ClientsStore.instance.loadActiveClientId();
      if (activeId == null) {
        if (!mounted) return;
        setState(() => _activeClientName = null);
        return;
      }
      final clients = await ClientsStore.instance.loadClients();
      final found = clients.firstWhere((c) => c.id == activeId, orElse: () => ClientProfile(id: activeId, name: ''));
      if (!mounted) return;
      setState(() => _activeClientName = (found.name.isNotEmpty ? found.name : null));
    } catch (_) {
      if (!mounted) return;
      setState(() => _activeClientName = null);
    }
  }

  @override
  void initState() {
    super.initState();
    _mySvc = MyProgramsService.instance;
    _myListener = () => _loadPrograms();
    _mySvc.addListener(_myListener!);
    _loadPrograms();
    _refreshActiveClientName();
  }

  @override
  void dispose() {
    if (_myListener != null) {
      _mySvc.removeListener(_myListener!);
      _myListener = null;
    }
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
      // Ensure custom frequencies store is loaded so we can resolve custom_ IDs
      // Use loadAll() which is available on the store; this mirrors an ensureLoaded() call.
      try {
        await CustomFrequenciesStore.instance.loadAll();
      } catch (_) {
        // best-effort: continue even if store not present or fails
      }

      final ids = await _mySvc.loadIds();

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
      final nextDisplay = <String, String>{};
      final isDe = ProgramLangController.instance.lang == ProgramLang.de;

      for (final id in ids) {
        // custom user-created entries (persisted as custom_<ts>)
        if (id.startsWith('custom_')) {
          // try to load persisted custom entry and use its name for display
          final e = await CustomFrequenciesStore.instance.getById(id);
          final displayName = (e?.name ?? '').trim();

          programs.add(ProgramItem(
            id: id,
            name: displayName.isNotEmpty ? displayName : (isDe ? 'Eigene Frequenz' : 'Custom Frequency'),
            uuid: null,
            internalId: null,
            level: 1,
          ));

          nextDisplay[id] = displayName.isNotEmpty ? displayName : (isDe ? 'Eigene Frequenz' : 'Custom Frequency');
          continue;
        }

        final p = map[id];
        if (p != null) {
          programs.add(p);
          // leave display name to enrichment below (or set immediately if name present)
          continue;
        }

        // unknown id: keep it visible as placeholder so user can spot missing entries
        programs.add(ProgramItem(
          id: id,
          name: isDe ? 'Unbekanntes Programm' : 'Unknown Program',
          uuid: null,
          internalId: null,
          level: 1,
        ));
        nextDisplay[id] = isDe ? 'Unbekanntes Programm' : 'Unknown Program';
      }

      // ---- name enrichment from Programs_decoded_full.json (optional) ----
      try {
        await ProgramCatalog.instance.ensureLoaded();
        _displayNameById.clear();

        for (final program in programs) {
          // if we already set a display name (for custom_/unknown) keep it
          if (nextDisplay.containsKey(program.id)) {
            _displayNameById[program.id] = nextDisplay[program.id]!;
            continue;
          }

          final current = program.name.trim();
          final isPlaceholder = current.isEmpty || current == '-' || current.toLowerCase() == 'placeholder';

          if (!isPlaceholder) {
            _displayNameById[program.id] = program.name;
            continue;
          }

          // prefer explicit uuid/internalId fields on ProgramItem
          if (program.uuid != null && program.uuid!.isNotEmpty) {
            final byUuid = ProgramCatalog.instance.byUuid(program.uuid!);
            if (byUuid != null) {
              _displayNameById[program.id] = ProgramCatalog.instance.name(byUuid, lang: 'EN');
              continue;
            }
          }

          if (program.internalId != null) {
            final byInt = ProgramCatalog.instance.byInternalId(program.internalId!);
            if (byInt != null) {
              _displayNameById[program.id] = ProgramCatalog.instance.name(byInt, lang: 'EN');
              continue;
            }
          }

          // fallback to stored name
          _displayNameById[program.id] = program.name;
        }
      } catch (_) {
        // best-effort: if catalog missing, keep any earlier nextDisplay entries
        if (_displayNameById.isEmpty) {
          _displayNameById.addAll(nextDisplay);
        }
      }

      if (!mounted) return;
      // merge enriched display names with nextDisplay placeholders (custom/unknown)
      final mergedDisplay = Map<String, String>.from(_displayNameById);
      mergedDisplay.addAll(nextDisplay);
      setState(() {
        _programs = programs;
        _displayNameById
          ..clear()
          ..addAll(mergedDisplay);
      });
    } finally {
      if (!mounted) return;
      _isLoading = false;
      setState(() => _loading = false);

      if (_pendingReload) {
        _pendingReload = false;
        Future.microtask(() => _loadPrograms());
      }
    }
  }

  Future<void> _remove(String id) async {
    await _mySvc.remove(id);
    _loadPrograms();
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;

    if (oldIndex < 0 || oldIndex >= _programs.length) return;
    if (newIndex < 0 || newIndex >= _programs.length) return;

    setState(() {
      final moved = _programs.removeAt(oldIndex);
      _programs.insert(newIndex, moved);
    });

    final ids = _programs.map((p) => p.id).toList(growable: false);
    await _mySvc.saveIds(ids);
  }

  void _openPlayerPopup(BuildContext context) {
    final langCode = (ProgramLangController.instance.lang == ProgramLang.de) ? 'de' : 'en';

    String resolveTitle(String programId) {
      final keyEn = playerService.titleKeyEnById[programId] ?? _displayNameById[programId] ?? programId;
      return ProgramNameLocalizer.instance.displayName(keyEn: keyEn, langCode: langCode);
    }

    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      showDragHandle: false,
      builder: (ctx) => SafeArea(
        child: Center(
          child: PlayerPopup(
            player: playerService,
            resolveTitle: resolveTitle,
          ),
        ),
      ),
    );
  }

  Future<void> _pickClient(BuildContext context) async {
    final clients = await ClientsStore.instance.loadClients();
    final activeId = await ClientsStore.instance.loadActiveClientId();

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDe = ProgramLangController.instance.lang == ProgramLang.de;
        return SafeArea(
          child: Material(
            color: AppColors.cardBackground,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    isDe ? 'Klient wählen' : 'Choose client',
                    style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
                  ),
                ),
                ...clients.map((c) {
                  final selected = c.id == activeId;
                  return ListTile(
                    leading: Icon(
                      selected ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: selected ? AppColors.accentGreen : AppColors.textSecondary,
                    ),
                    title: Text(c.name, style: const TextStyle(color: AppColors.textPrimary)),
                    onTap: () async {
                      await ClientsStore.instance.setActiveClientId(c.id);
                      if (!mounted) return;
                      Navigator.pop(ctx);
                      setState(() {}); // refresh header label
                      await _loadPrograms(); // load My Programs for the newly selected client
                    },
                  );
                }),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  String _settingsSubtitle(String programId) {
    try {
      final s = playerService.settingsFor(programId);
      final parts = <String>['${s.durationMinutes}m', '${s.intensity}%'];
      if (s.electric) parts.add('E:${s.electricWaveform.name}');
      if (s.magnetic) parts.add('M:${s.magneticWaveform.name}');
      return parts.join(' • ');
    } catch (_) {
      return '';
    }
  }

  Future<void> _playFromIndex(int index, BuildContext context) async {
    final ids = _programs.map((p) => p.id).toList(growable: false);
    if (ids.isEmpty) return;

    // keyEn map for consistent titles
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

    // Start playback via PlayerService (single call) so the service owns queue/start behavior
    playerService.playQueue(
      ids,
      index,
      titleKeyEnById: keyEnMap,
    );

    // Popup öffnen wie bisher
    if (!context.mounted) return;
    _openPlayerPopup(context);

    // Upload banner in popup (PlayerPopup reads playerService.isUploading)
    playerService.setUploading(true);
    try {
      await CubeDeviceService.instance.sendMyProgramsAsMergedSingleFromIds(
        ids: ids,
        powerMode: true,
        settingsForId: (id) => playerService.settingsFor(id),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Playlist-Upload fehlgeschlagen: $e')),
      );
    } finally {
      if (mounted) playerService.setUploading(false);
    }
  }

  Future<void> _playSingleProgram(ProgramItem program, BuildContext context) async {
    final s = playerService.settingsFor(program.id);
    final duration = Duration(minutes: s.durationMinutes);

    // UI: only this program in the queue
    final ids = <String>[program.id];

    // Use enriched display name, but prefer stored custom name for custom_ entries
    String uiName = (_displayNameById[program.id] ?? program.name);
    if (program.id.startsWith('custom_')) {
      final e = await CustomFrequenciesStore.instance.getById(program.id);
      if (e != null && e.name.trim().isNotEmpty) {
        uiName = e.name.trim();
      }
    }

    final keyEnMap = <String, String>{
      program.id: uiName,
    };

    playerService.setQueueUiOnly(
      ids,
      startIndex: 0,
      titleKeyEnById: keyEnMap,
    );

    if (playerService.state.total > Duration.zero) {
      playerService.markStarted();
    }

    if (!context.mounted) return;
    _openPlayerPopup(context);

    // Upload banner in popup
    playerService.setUploading(true);
    try {
      await CubeDeviceService.instance.sendProgram(
        program: program,
        duration: duration,
        powerMode: true,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Single-Start fehlgeschlagen: $e')),
      );
    } finally {
      if (mounted) playerService.setUploading(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final langCode = (ProgramLangController.instance.lang == ProgramLang.de) ? 'de' : 'en';
    final isDe = langCode == 'de';

    return GradientBackground(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
        child: ListView(
          padding: const EdgeInsets.only(bottom: 12.0),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    isDe ? 'Meine Programme' : 'My Programs',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FutureBuilder<List<ClientProfile>>(
                  future: ClientsStore.instance.loadClients(),
                  builder: (context, snap) {
                    final clients = snap.data ?? const [];
                    if (clients.isEmpty) return const SizedBox.shrink();

                    return TextButton.icon(
                      onPressed: () => _pickClient(context),
                      icon: const Icon(Icons.person, color: AppColors.textPrimary, size: 18),
                      label: FutureBuilder<String?>(
                        future: ClientsStore.instance.loadActiveClientId(),
                        builder: (context, aSnap) {
                          final activeId = aSnap.data;
                          final active = clients.where((c) => c.id == activeId).cast<ClientProfile?>().firstWhere(
                                (x) => x != null,
                                orElse: () => null,
                              );
                          final name = active?.name ?? (isDe ? 'Kein Klient' : 'No client');
                          return Text(name, style: const TextStyle(color: AppColors.textPrimary));
                        },
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 6),

            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _programs.isEmpty ? null : () async => _playFromIndex(0, context),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Play Playlist'),
            ),
            const SizedBox(height: 8),

            if (_loading) ...[
              const SizedBox(height: 36),
              const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            ] else if (_programs.isEmpty) ...[
              const SizedBox(height: 36),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.favorite_border, size: 64, color: AppColors.navBarInactive),
                    SizedBox(height: 10),
                    Text('Keine gespeicherten Programme', style: TextStyle(color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ] else ...[
              const SizedBox(height: 4),

              ReorderableListView.builder(
                buildDefaultDragHandles: false, // IMPORTANT: avoid gesture conflicts with buttons
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
                                deviceId: CureDeviceUnlockService.instance.nativeConnectedDeviceId ?? '',
                              ),
                            ),
                          );
                          await _loadPrograms();
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                          child: Row(
                            children: [
                              // Optional: item-start (works now; can be removed later)
                              IconButton(
                                icon: const Icon(Icons.play_arrow),
                                color: AppColors.primary,
                                onPressed: () => _playSingleProgram(program, context),
                              ),
                              const SizedBox(width: 4),

                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(displayTitle, style: const TextStyle(color: AppColors.textPrimary)),
                                    const SizedBox(height: 2),
                                    Text(
                                      _settingsSubtitle(program.id),
                                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                    ),
                                  ],
                                ),
                              ),

                              IconButton(
                                icon: const Icon(Icons.edit, color: AppColors.textSecondary),
                                onPressed: () async {
                                  final initial = playerService.settingsFor(program.id);
                                  final settings = await showPlaylistItemSetup(context, program.id, initial);
                                  if (settings != null) {
                                    playerService.setSettings(program.id, settings);
                                    if (!mounted) return;
                                    setState(() {}); // refresh subtitle immediately
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Einstellungen gespeichert')),
                                    );
                                  }
                                },
                              ),

                              IconButton(
                                icon: const Icon(Icons.delete, color: AppColors.textSecondary),
                                onPressed: () async => _remove(program.id),
                              ),

                              ReorderableDragStartListener(
                                index: index,
                                child: const Icon(Icons.drag_handle, color: AppColors.textSecondary),
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
