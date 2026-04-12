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
import 'package:hbcure/services/app_memory.dart';
import 'package:hbcure/core/program_mode.dart';
import 'package:hbcure/ui/pages/custom_frequencies_page.dart';
import 'package:hbcure/l10n/gen/app_localizations.dart';
import 'package:hbcure/services/cure_device_unlock_service.dart';
import 'package:hbcure/services/ble_cure_device_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

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
    final langCode =
    (ProgramLangController.instance.lang == ProgramLang.de) ? 'de' : 'en';

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

      _keyEnByProgramId[programId] = keyEn;
    }

    return ProgramNameLocalizer.instance.displayName(
      keyEn: keyEn,
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

    // Listen to AppMemory.programMode changes so the shell rebuilds (tabs/pages)
    AppMemory.instance.addListener(_onModeChanged);

    // Auto-reconnect to last Cube if enabled
    _attemptAutoReconnect();
  }

  @override
  void dispose() {
    AppMemory.instance.removeListener(_onModeChanged);
    _myProgramsSub?.cancel();
    _myProgramsSub = null;
    super.dispose();
  }

  // Called when AppMemory.programMode changes
  void _onModeChanged() {
    if (!mounted) return;
    setState(() {
      // Rebuild to reflect mode-dependent pages / labels
    });
  }

  /// Auto-reconnect to last Cube device if setting is enabled.
  /// Runs asynchronously in the background — does not block UI.
  ///
  /// Uses the normal BleCureDeviceService.connect() → ensureUnlockedForCurrentDevice()
  /// pipeline so that _selectedDevice / _connectedDeviceId are properly set and
  /// the manual Unlock button keeps working afterwards.
  Future<void> _attemptAutoReconnect() async {
    final mem = AppMemory.instance;
    if (!mem.reconnectEnabled) {
      debugPrint('[AutoReconnect] disabled in settings');
      return;
    }
    final lastId = mem.lastConnectedDeviceId;
    if (lastId == null || lastId.isEmpty) {
      debugPrint('[AutoReconnect] no last device id stored');
      return;
    }

    debugPrint('[AutoReconnect] scheduled for $lastId – waiting for BLE adapter ...');

    try {
      // ── Wait for FlutterBluePlus to be ready ──────────────────────────
      final adapterState = await FlutterBluePlus.adapterState
          .firstWhere((s) => s == BluetoothAdapterState.on)
          .timeout(const Duration(seconds: 6), onTimeout: () => BluetoothAdapterState.unknown);

      if (adapterState != BluetoothAdapterState.on) {
        debugPrint('[AutoReconnect] BLE adapter not ON ($adapterState) – aborting');
        return;
      }

      // Extra delay: let flutterRestart + disconnectAllDevices finish
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted) return;

      debugPrint('[AutoReconnect] BLE adapter ready – attempting reconnect to $lastId ...');

      // ── Step 1: Connect through BleCureDeviceService ──────────────────
      // This sets _selectedDevice, _connectedDeviceId, and in native mode
      // delegates to the native transport. The normal UI flow remains intact.
      final bleDevice = BluetoothDevice.fromId(lastId);
      final bleSvc = BleCureDeviceService.instance;
      await bleSvc.connect(bleDevice);

      if (!mounted) return;
      debugPrint('[AutoReconnect] BleCureDeviceService.connect() OK');

      // ── Step 2: Unlock through the normal path ────────────────────────
      final unlocked = await bleSvc.ensureUnlockedForCurrentDevice();
      if (!unlocked) {
        debugPrint('[AutoReconnect] unlock failed');
        return;
      }

      debugPrint('[AutoReconnect] unlock OK');

      // ── Step 3: Fetch progStatus ──────────────────────────────────────
      final svc = CureDeviceUnlockService.instance;
      final status = await svc.fetchProgStatus();
      if (status == null) {
        debugPrint('[AutoReconnect] progStatus returned null');
        return;
      }

      debugPrint('[AutoReconnect] progStatus: running=${status.running} '
          'elapsed=${status.elapsedSec} total=${status.totalSec}');

      // ── Step 4: Sync player timer if device is still running ──────────
      if (status.running) {
        playerService.syncWithDeviceStatus(
          deviceTotalMs: status.totalSec,
          deviceElapsedMs: status.elapsedSec,
          deviceRunning: true,
        );
        debugPrint('[AutoReconnect] player timer synced – device still running');

        // ── Step 5: Show PlayerPopup so user sees remaining time ────────
        if (mounted) {
          // Small delay to let the widget tree settle after init
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _openPlayerPopupForReconnect();
          });
        }
      } else {
        debugPrint('[AutoReconnect] device not running – no timer sync needed');
      }
    } catch (e, st) {
      debugPrint('[AutoReconnect] failed: $e');
      if (kDebugMode) debugPrint('[AutoReconnect] stack: $st');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    // Determine whether Expert mode is active (affects tabs/pages)
    final isExpert = AppMemory.instance.programMode == ProgramMode.expert;

    // IMPORTANT: do NOT make these pages const – they must rebuild on language/mode changes
    final pages = <Widget>[
      MyProgramsPage(),
      AvailableProgramsPage(),
      if (isExpert) const CustomFrequenciesPage(),
      DevicesPage(),
      SettingsPage(),
    ];

    // Safety: clamp current index when mode changed and pages count reduced
    if (_currentIndex >= pages.length) {
      _currentIndex = pages.length - 1;
    }

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: AppBar(
          title: Text(_appBarTitle(context)),
          actions: [
            ListenableBuilder(
              listenable: playerService,
              builder: (context, _) {
                final isPlaying = playerService.state.isPlaying;
                return IconButton(
                  tooltip: 'Player',
                  icon: Icon(
                    isPlaying ? Icons.play_circle_filled : Icons.queue_music,
                    color: isPlaying ? Colors.greenAccent : null,
                  ),
                  onPressed: () async {
                // ensure name cache for sync resolver used by PlayerPopup
                await _ensureNameCacheLoaded();

                // Wenn Player noch keine Queue hat: starte automatisch "My Programs" (gefiltert)
                if (playerService.state.queueIds.isEmpty) {
                  final res = await _loadPlayableIdsAndTitles();
                  final playableIds =
                      (res['ids'] as List<dynamic>?)?.cast<String>() ??
                          <String>[];
                  final titles = (res['titles'] as Map<dynamic, dynamic>?)
                      ?.map((k, v) => MapEntry(k.toString(), v.toString())) ??
                      <String, String>{};
                  if (playableIds.isNotEmpty) {
                    try {
                      playerService.playQueue(
                        playableIds,
                        0,
                        titleKeyEnById: titles,
                      );
                    } catch (_) {
                      // fallback if playQueue signature doesn't accept titles
                      playerService.playQueue(playableIds, 0);
                    }
                  }
                }

                // Konsistenter Resolver: nutze playerService.titleKeyEnById als Quelle für keyEn
                String resolveTitle(String id) {
                  final langCode =
                  (ProgramLangController.instance.lang == ProgramLang.de)
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
            ); // IconButton
              },
            ), // ListenableBuilder
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
                      label: l10n.navMyPrograms,
                      selected: _currentIndex == 0,
                      onTap: () => setState(() => _currentIndex = 0),
                    ),
                    _NavTextTab(
                      label: l10n.navAvailable,
                      selected: _currentIndex == 1,
                      onTap: () => setState(() => _currentIndex = 1),
                    ),
                    if (isExpert)
                      _NavTextTab(
                        label: l10n.navCustomFrequencies,
                        selected: _currentIndex == 2,
                        onTap: () => setState(() => _currentIndex = 2),
                      ),
                    _NavTextTab(
                      label: l10n.navDevices,
                      selected: _currentIndex == (isExpert ? 3 : 2),
                      onTap: () =>
                          setState(() => _currentIndex = (isExpert ? 3 : 2)),
                    ),
                    _NavTextTab(
                      label: l10n.navSettings,
                      selected: _currentIndex == (isExpert ? 4 : 3),
                      onTap: () =>
                          setState(() => _currentIndex = (isExpert ? 4 : 3)),
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
    final isExpert = AppMemory.instance.programMode == ProgramMode.expert;
    final l10n = AppLocalizations.of(context)!;

    switch (_currentIndex) {
      case 0:
        return l10n.myProgramsTitle;
      case 1:
        return l10n.availableProgramsTitle;
      case 2:
        return isExpert
            ? l10n.customFrequenciesTitle
            : l10n.devicesTitle;
      case 3:
        return isExpert ? l10n.devicesTitle : l10n.navSettings;
      case 4:
        return l10n.navSettings;
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

  /// Opens PlayerPopup after auto-reconnect detected a running device.
  void _openPlayerPopupForReconnect() {
    _ensureNameCacheLoaded().then((_) {
      if (!mounted) return;

      String resolveTitle(String id) {
        final langCode =
            (ProgramLangController.instance.lang == ProgramLang.de)
                ? 'de'
                : 'en';
        final keyEn = playerService.titleKeyEnById[id] ?? id;
        return ProgramNameLocalizer.instance.displayName(
          keyEn: keyEn,
          langCode: langCode,
        );
      }

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
    });
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

      // keep current id if possible
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