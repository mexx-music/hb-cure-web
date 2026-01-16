import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hbcure/ui/pages/my_programs_page.dart';
import 'package:hbcure/ui/pages/available_programs_page.dart';
import 'package:hbcure/ui/pages/devices_page.dart';
import 'package:hbcure/ui/pages/settings_page.dart';
import 'package:hbcure/ui/theme/app_colors.dart';
import 'package:hbcure/ui/widgets/program_lang_toggle.dart';
import 'package:hbcure/l10n/gen/app_localizations.dart';
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

  // MyPrograms subscription + sync guard
  final MyProgramsService _myProgramsService = MyProgramsService();
  StreamSubscription<void>? _myProgramsSub;
  bool _syncInProgress = false;

  // Name cache for Player resolver
  final Map<String, String> _keyEnByProgramId = {};
  final _repo = ProgramRepository();
  bool _nameCacheReady = false;

  static const List<String> _titles = [
    'My Programs',
    'Available Programs',
    'Devices',
    'Settings',
  ];

  Future<void> _ensureNameCacheLoaded() async {
    if (_nameCacheReady) return;

    // 1) programs.json → id -> ProgramItem.name (EN key)
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

    // 2) try to load decoded catalog for fallbacks
    try {
      await ProgramCatalog.instance.ensureLoaded();
    } catch (_) {
      // non-fatal
    }

    // We will fill _keyEnByProgramId lazily per id when resolver is called
    _nameCacheReady = true;
  }

  String _resolveTitleForPlayer(String programId) {
    final langCode = (ProgramLangController.instance.lang == ProgramLang.de) ? 'de' : 'en';

    // 1) Cached EN key?
    var keyEn = _keyEnByProgramId[programId];

    if (keyEn == null) {
      // 2) Try decoded catalog by UUID / internalId
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

      // 3) Fallback: if still null -> use id itself
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
      MyProgramsPage(),
      AvailableProgramsPage(),
      DevicesPage(),
      SettingsPage(),
    ];

    final t = AppLocalizations.of(context);
    // Bind bottom-nav labels to ProgramLangController (minimal, two-line German labels)
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
                // ensure name cache for sync resolver used by PlayerPopup
                await _ensureNameCacheLoaded();
                // Wenn Player noch keine Queue hat: starte automatisch "My Programs" (gefiltert)
                if (playerService.state.queueIds.isEmpty) {
                  final res = await _loadPlayableIdsAndTitles();
                  final playableIds = (res['ids'] as List<dynamic>?)?.cast<String>() ?? <String>[];
                  final titles = (res['titles'] as Map<dynamic, dynamic>?)
                          ?.map((k, v) => MapEntry(k.toString(), v.toString())) ??
                      <String, String>{};
                  if (playableIds.isNotEmpty) {
                    try {
                      playerService.playQueue(playableIds, 0, titleKeyEnById: titles);
                    } catch (_) {
                      // fallback if playQueue signature doesn't accept titles
                      playerService.playQueue(playableIds, 0);
                    }
                  }
                }

                // String resolveTitle(String id) => _resolveTitleForPlayer(id);
                // Konsistenter Resolver: nutze playerService.titleKeyEnById als Quelle für keyEn
                String resolveTitle(String id) {
                  final langCode = (ProgramLangController.instance.lang == ProgramLang.de) ? 'de' : 'en';
                  final keyEn = playerService.titleKeyEnById[id] ?? id;
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
                height: 72, // Pill-Höhe (wie vorher optisch), keine Schriftgröße geändert
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

  // Helper to provide localized AppBar titles based on the current index
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

  // Helper to load playable program IDs from MyPrograms (resolves only those present in catalog)
  Future<List<String>> _loadPlayableMyProgramIds() async {
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
    for (final id in ids) {
      if (map.containsKey(id)) playable.add(id);
    }
    return playable;
  }

  // Helper to load playable program IDs and title map from MyPrograms (resolves only those present in catalog)
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
        // prefer p.name as EN-key; caller/localizer may translate
        titles[id] = p.name;
      }
    }

    return {'ids': playable, 'titles': titles};
  }

  // Sync MyPrograms -> Player queue (minimal, guarded)
  Future<void> _syncPlayerQueueWithMyPrograms() async {
    if (_syncInProgress) return;
    _syncInProgress = true;
    try {
      final st = playerService.state;

      // Never change queue while actively playing
      // use the PlayerState API: isPlaying and currentProgramId
      final isPlaying = st.isPlaying;
      if (isPlaying) return;

      // Replace old ID-only sync with IDs+Titles sync
      final res = await _loadPlayableIdsAndTitles();
      final playableIds = (res['ids'] as List<dynamic>?)?.cast<String>() ?? <String>[];
      final titles = (res['titles'] as Map<dynamic, dynamic>?)
              ?.map((k, v) => MapEntry(k.toString(), v.toString())) ??
          <String, String>{};

      if (playableIds.isEmpty) return;

      // If player is empty: just set queue at 0 and pause
      if (st.queueIds.isEmpty) {
        try {
          playerService.playQueue(playableIds, 0, titleKeyEnById: titles);
        } catch (_) {
          // fallback if playQueue signature doesn't accept titles
          playerService.playQueue(playableIds, 0);
        }
        // keep paused until user explicitly plays
        try {
          playerService.pause();
        } catch (_) {}
        return;
      }

      // If player already has a queue: update queue but try to keep current program
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
    // Wichtig: Center + textAlign.center => 100% mittig, auch bei 2 Zeilen
    final style = TextStyle(
      fontSize: 12, // NICHT geändert
      height: 1.15, // nur Zeilenblock "ruhiger"
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
