import 'dart:async';
import 'package:flutter/material.dart';

import 'package:hbcure/ui/pages/my_programs_page.dart';
import 'package:hbcure/ui/pages/available_programs_page.dart';
import 'package:hbcure/ui/pages/devices_page.dart';
import 'package:hbcure/ui/pages/settings_page.dart';

import 'package:hbcure/ui/theme/app_colors.dart';
import 'package:hbcure/ui/widgets/program_lang_toggle.dart';

import 'package:hbcure/services/program_language_controller.dart';
import 'package:hbcure/app_services.dart';
import 'package:hbcure/ui/widgets/player_popup.dart';

import 'package:hbcure/services/my_programs_service.dart';
import 'package:hbcure/data/program_repository.dart';
import 'package:hbcure/models/program_item.dart';
import 'package:hbcure/i18n/program_name_localizer.dart';
import 'package:hbcure/services/program_catalog.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  final MyProgramsService _myProgramsService = MyProgramsService();
  StreamSubscription<void>? _myProgramsSub;
  bool _syncInProgress = false;

  final Map<String, String> _keyEnByProgramId = {};
  final _repo = ProgramRepository();
  bool _nameCacheReady = false;

  Future<void> _ensureNameCacheLoaded() async {
    if (_nameCacheReady) return;

    // programs.json → id -> ProgramItem.name (EN key)
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

    // Try to load decoded catalog for fallbacks
    try {
      await ProgramCatalog.instance.ensureLoaded();
    } catch (_) {
      // non-fatal
    }

    // Fill lazily per id when resolver is called
    _nameCacheReady = true;
  }

  String _resolveTitleForPlayer(String programId) {
    final langCode = (ProgramLangController.instance.lang == ProgramLang.de)
        ? 'de'
        : 'en';

    var keyEn = _keyEnByProgramId[programId];

    if (keyEn == null) {
      // Try decoded catalog by UUID / internalId
      try {
        final byUuid = ProgramCatalog.instance.byUuid(programId);
        if (byUuid != null) {
          keyEn = ProgramCatalog.instance.name(byUuid, lang: 'EN');
        } else {
          final intId = int.tryParse(programId);
          if (intId != null) {
            final byInt = ProgramCatalog.instance.byInternalId(intId);
            if (byInt != null) {
              keyEn = ProgramCatalog.instance.name(byInt, lang: 'EN');
            }
          }
        }
      } catch (_) {
        // ignore
      }

      keyEn ??= programId;
      _keyEnByProgramId[programId] = keyEn!;
    }

    return ProgramNameLocalizer.instance.displayName(
      keyEn: keyEn!,
      langCode: langCode,
    );
  }

  @override
  void initState() {
    super.initState();

    // initial sync
    _syncPlayerQueueWithMyPrograms();

    // subscribe to changes in MyPrograms and sync the player queue
    _myProgramsSub = _myProgramsService.onChange.listen((_) async {
      await _syncPlayerQueueWithMyPrograms();
    });
  }

  @override
  void dispose() {
    _myProgramsSub?.cancel();
    _myProgramsSub = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const MyProgramsPage(),
      const AvailableProgramsPage(),
      const DevicesPage(),
      const SettingsPage(),
    ];

    final isDe = ProgramLangController.instance.lang == ProgramLang.de;

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: AppBar(
          title: Text(_appBarTitle(context)),
          actions: [
            IconButton(
              tooltip: 'Player',
              icon: const Icon(Icons.queue_music),
              onPressed: () async {
                await _ensureNameCacheLoaded();

                // If player has no queue yet, preload My Programs ids (+ titles map) into player
                if (playerService.state.queueIds.isEmpty) {
                  final res = await _loadPlayableIdsAndTitles();
                  final playableIds =
                      (res['ids'] as List<dynamic>?)?.cast<String>() ?? <String>[];
                  final titles = (res['titles'] as Map<dynamic, dynamic>?)
                      ?.map((k, v) => MapEntry(k.toString(), v.toString())) ??
                      <String, String>{};

                  if (playableIds.isNotEmpty) {
                    try {
                      playerService.playQueue(playableIds, 0, titleKeyEnById: titles);
                    } catch (_) {
                      playerService.playQueue(playableIds, 0);
                    }
                  }
                }

                // Resolver uses playerService.titleKeyEnById as EN-key source
                String resolveTitle(String id) {
                  final langCode = (ProgramLangController.instance.lang == ProgramLang.de)
                      ? 'de'
                      : 'en';
                  final keyEn = playerService.titleKeyEnById[id] ?? id;
                  return ProgramNameLocalizer.instance.displayName(
                    keyEn: keyEn,
                    langCode: langCode,
                  );
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
              },
            ),
            ProgramLangToggle(onChanged: () => setState(() {})),
          ],
        ),
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: pages,
      ),
      bottomNavigationBar: SafeArea(
        bottom: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Material(
              color: AppColors.navBarBackground,
              elevation: 8,
              child: SizedBox(
                height: 72,
                child: Row(
                  children: [
                    _NavTextTab(
                      label: isDe ? 'Meine\nProgramme' : 'My\nPrograms',
                      selected: _currentIndex == 0,
                      onTap: () => setState(() => _currentIndex = 0),
                    ),
                    _NavTextTab(
                      label: isDe ? 'Verfügbare\nProgramme' : 'Available\nPrograms',
                      selected: _currentIndex == 1,
                      onTap: () => setState(() => _currentIndex = 1),
                    ),
                    _NavTextTab(
                      label: isDe ? 'Geräte' : 'Devices',
                      selected: _currentIndex == 2,
                      onTap: () => setState(() => _currentIndex = 2),
                    ),
                    _NavTextTab(
                      label: isDe ? 'Einstellungen' : 'Settings',
                      selected: _currentIndex == 3,
                      onTap: () => setState(() => _currentIndex = 3),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _appBarTitle(BuildContext context) {
    final isDe = ProgramLangController.instance.lang == ProgramLang.de;

    switch (_currentIndex) {
      case 0:
        return isDe ? 'Meine Programme' : 'My Programs';
      case 1:
        return isDe ? 'Verfügbare Programme' : 'Available Programs';
      case 2:
        return isDe ? 'Geräte' : 'Devices';
      case 3:
        return isDe ? 'Einstellungen' : 'Settings';
      default:
        return '';
    }
  }

  Future<Map<String, dynamic>> _loadPlayableIdsAndTitles() async {
    final ids = await MyProgramsService().loadIds();

    final repo = ProgramRepository();
    final categories = await repo.loadCategories();

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

    final playable = <String>[];
    final titles = <String, String>{};

    for (final id in ids) {
      final p = map[id];
      if (p != null) {
        playable.add(id);
        titles[id] = p.name; // EN-key
      }
    }

    return {'ids': playable, 'titles': titles};
  }

  Future<void> _syncPlayerQueueWithMyPrograms() async {
    if (_syncInProgress) return;
    _syncInProgress = true;

    try {
      final st = playerService.state;

      // Never change queue while actively playing
      if (st.isPlaying) return;

      final res = await _loadPlayableIdsAndTitles();
      final playableIds =
          (res['ids'] as List<dynamic>?)?.cast<String>() ?? <String>[];
      final titles = (res['titles'] as Map<dynamic, dynamic>?)
          ?.map((k, v) => MapEntry(k.toString(), v.toString())) ??
          <String, String>{};

      if (playableIds.isEmpty) return;

      // If player is empty: set queue then pause
      if (st.queueIds.isEmpty) {
        try {
          playerService.playQueue(playableIds, 0, titleKeyEnById: titles);
        } catch (_) {
          playerService.playQueue(playableIds, 0);
        }
        try {
          playerService.pause();
        } catch (_) {}
        return;
      }

      // Keep current id if possible
      final currentId = st.currentProgramId;
      int newIndex = 0;
      if (currentId != null) {
        final idx = playableIds.indexOf(currentId);
        if (idx >= 0) newIndex = idx;
      }

      // Update queue and keep paused
      try {
        playerService.playQueue(playableIds, newIndex, titleKeyEnById: titles);
      } catch (_) {
        playerService.playQueue(playableIds, newIndex);
      }
      try {
        playerService.pause();
      } catch (_) {}
    } finally {
      _syncInProgress = false;
    }
  }
}

class _NavTextTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavTextTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 12,
      height: 1.15,
      color: selected ? AppColors.navBarActive : AppColors.navBarInactive,
    );

    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: style,
            maxLines: 2,
            overflow: TextOverflow.visible,
          ),
        ),
      ),
    );
  }
}
