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

  // ── Device-status polling during active playback ──────────────────────────
  /// Adaptive poll interval based on remaining playback time.
  Duration get _pollInterval {
    final remaining = playerService.state.remaining;
    if (remaining < const Duration(minutes: 5)) {
      return const Duration(seconds: 8);
    } else if (remaining < const Duration(minutes: 30)) {
      return const Duration(seconds: 30);
    } else {
      return const Duration(minutes: 3);
    }
  }
  Timer? _playbackPollTimer;
  bool _pollBusy = false;

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

    // Resolve base id for slot-key duplicates
    final baseId = programId.contains('__slot_')
        ? programId.split('__slot_').first
        : programId;

    // 1) Cached EN key? (try full key first, then base)
    var keyEn = _keyEnByProgramId[programId] ?? _keyEnByProgramId[baseId];

    if (keyEn == null) {
      // 2) Try decoded catalog by UUID / internalId using baseId
      try {
        final byUuid = ProgramCatalog.instance.byUuid(baseId);
        if (byUuid != null) {
          keyEn = ProgramCatalog.instance.name(byUuid, lang: 'EN');
        } else {
          final intId = int.tryParse(baseId);
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

      // 3) Fallback: if still null -> use baseId
      keyEn ??= baseId;

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
    // Try auto-reconnect first; only after it completes do the initial
    // MyPrograms -> player queue sync. This avoids overwriting a device
    // running-single-program context with the saved playlist during startup.
    _attemptAutoReconnect().whenComplete(() async {
      await _syncPlayerQueueWithMyPrograms();
    });
    // subscribe to changes in MyPrograms and sync the player queue
    _myProgramsSub = _myProgramsService.onChange.listen((_) async {
      await _syncPlayerQueueWithMyPrograms();
    });

    // Listen to AppMemory.programMode changes so the shell rebuilds (tabs/pages)
    AppMemory.instance.addListener(_onModeChanged);

    // Listen to playerService so we can start/stop the device-status poll
    playerService.addListener(_onPlayerStateChanged);

    // Auto-reconnect to last Cube if enabled
    // _attemptAutoReconnect();
  }

  @override
  void dispose() {
    AppMemory.instance.removeListener(_onModeChanged);
    playerService.removeListener(_onPlayerStateChanged);
    _myProgramsSub?.cancel();
    _myProgramsSub = null;
    _stopPlaybackPolling();
    super.dispose();
  }

  // Called when AppMemory.programMode changes
  void _onModeChanged() {
    if (!mounted) return;
    setState(() {
      // Rebuild to reflect mode-dependent pages / labels
    });
  }

  // Called on every playerService change — starts/stops the device poll timer
  void _onPlayerStateChanged() {
    final playing = playerService.state.isPlaying;
    if (playing && _playbackPollTimer == null) {
      _startPlaybackPolling();
    } else if (!playing && _playbackPollTimer != null) {
      _stopPlaybackPolling();
    }
  }

  void _startPlaybackPolling() {
    _playbackPollTimer?.cancel();
    final interval = _pollInterval;
    _lastScheduledInterval = interval;
    debugPrint('[PlaybackPoll] starting periodic poll (interval: $interval)');
    _playbackPollTimer = Timer.periodic(interval, (_) => _pollDeviceStatus());
  }

  void _stopPlaybackPolling() {
    _playbackPollTimer?.cancel();
    _playbackPollTimer = null;
    debugPrint('[PlaybackPoll] polling stopped');
  }

  Future<void> _pollDeviceStatus() async {
    if (_pollBusy) {
      debugPrint('[PlaybackPoll] poll skipped – previous still running');
      return;
    }
    if (!playerService.state.isPlaying) {
      _stopPlaybackPolling();
      return;
    }

    _pollBusy = true;
    try {
      final svc = CureDeviceUnlockService.instance;
      if (!svc.isNativeConnected) {
        debugPrint('[PlaybackPoll] poll skipped – device not connected');
        return;
      }

      debugPrint('[PlaybackPoll] polling progStatus ...');
      final status = await svc.fetchProgStatus(timeout: const Duration(seconds: 10));
      if (status == null) {
        debugPrint('[PlaybackPoll] progStatus returned null – skipping');
        return;
      }

      debugPrint('[PlaybackPoll] progStatus: running=${status.running} '
          'elapsed=${status.elapsedSec} total=${status.totalSec}');

      if (!status.running) {
        // Device has stopped – reflect this in the app immediately
        debugPrint('[PlaybackPoll] MISMATCH: device stopped but app still playing → stopping app timer');
        playerService.stop();
        _stopPlaybackPolling();
        return;
      }

      // Device is running – check for drift
      final localRemaining = playerService.state.remaining;
      final deviceRemaining = Duration(
          milliseconds: (status.totalSec - status.elapsedSec).clamp(0, status.totalSec));
      final drift = (localRemaining - deviceRemaining).abs();

      final inFinalMinute = localRemaining < const Duration(minutes: 1);
      debugPrint('[PlaybackPoll] localRemaining=$localRemaining '
          'deviceRemaining=$deviceRemaining drift=$drift finalMinute=$inFinalMinute');

      // During the final minute: always sync from device (even small drift)
      // Outside final minute: sync only if drift > 15 seconds
      if (inFinalMinute || drift > const Duration(seconds: 15)) {
        debugPrint('[PlaybackPoll] syncing with device (finalMinute=$inFinalMinute drift=$drift)');
        playerService.syncWithDeviceStatus(
          deviceTotalMs: status.totalSec,
          deviceElapsedMs: status.elapsedSec,
          deviceRunning: true,
        );
      } else {
        debugPrint('[PlaybackPoll] drift=$drift – within tolerance, no sync needed');
      }

      // Reschedule if the adaptive interval changed
      _rescheduleIfIntervalChanged();
    } catch (e) {
      debugPrint('[PlaybackPoll] poll error: $e');
    } finally {
      _pollBusy = false;
    }
  }

  Duration _lastScheduledInterval = Duration.zero;

  void _rescheduleIfIntervalChanged() {
    final newInterval = _pollInterval;
    if (newInterval != _lastScheduledInterval && playerService.state.isPlaying) {
      debugPrint('[PlaybackPoll] adaptive interval changed: $_lastScheduledInterval → $newInterval');
      _startPlaybackPolling();
    }
  }
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
        // If our current queue is empty (e.g. app restarted after single-start),
        // try to provide a meaningful queue id so the UI shows the actual running
        // program instead of falling back to index 0 of a saved list.
        if (playerService.state.queueIds.isEmpty) {
          // First: attempt to restore a previously persisted session (rich UI queue)
          try {
            final lastSess = await playerService.loadLastSession();
            if (lastSess != null) {
              final q = (lastSess['queueIds'] as List<dynamic>?)?.cast<String>() ?? <String>[];
              final idx = (lastSess['currentIndex'] is int) ? lastSess['currentIndex'] as int : 0;
              if (q.isNotEmpty) {
                debugPrint('[AutoReconnect] restored persisted session queue=${q} idx=$idx');
                // Extract persisted title map (if any) so UI can show friendly titles for copied/slot items
                Map<String, String>? titleMap;
                try {
                  final rawTitles = lastSess['titles'] as Map<String, dynamic>?;
                  if (rawTitles != null) {
                    titleMap = rawTitles.map((k, v) => MapEntry(k.toString(), v.toString()));
                  }
                } catch (_) {
                  titleMap = null;
                }
                 playerService.syncWithDeviceStatus(
                   deviceTotalMs: status.totalSec,
                   deviceElapsedMs: status.elapsedSec,
                   deviceRunning: true,
                   queueIds: q,
                   titleKeyEnById: titleMap,
                 );
                 debugPrint('[AutoReconnect] player timer synced with persisted session');
                 // Open popup and return early
                 if (mounted) {
                   WidgetsBinding.instance.addPostFrameCallback((_) {
                     if (mounted) _openPlayerPopupForReconnect();
                   });
                 }
                 return;
               }
             }
          } catch (e) {
            debugPrint('[AutoReconnect] failed to load persisted session: $e');
          }

          final progHex = status.programIdHex ?? '';
          if (progHex.isNotEmpty && progHex != '-' && progHex != 'FFFFFFFF') {
            debugPrint('[AutoReconnect] attempt resolve running program from programIdHex=$progHex');
            // Try to resolve the device program hex to a real app program id
            // (so the UI shows a friendly program identity instead of raw hex).
            final resolvedId = await _resolveProgramIdFromHex(progHex);
            if (resolvedId != null && resolvedId.isNotEmpty) {
              debugPrint('[AutoReconnect] resolved programIdHex to app id=$resolvedId');
              playerService.syncWithDeviceStatus(
                deviceTotalMs: status.totalSec,
                deviceElapsedMs: status.elapsedSec,
                deviceRunning: true,
                queueIds: [resolvedId],
              );
              debugPrint('[AutoReconnect] player timer synced with resolved program id');
            } else {
              // No reliable resolution possible: keep existing behavior but DO NOT
              // insert the raw hex as a visible queue id (avoid technical placeholder).
              playerService.syncWithDeviceStatus(
                deviceTotalMs: status.totalSec,
                deviceElapsedMs: status.elapsedSec,
                deviceRunning: true,
              );
              debugPrint('[AutoReconnect] could not resolve progHex – synced timer without synthetic queue id');
            }
          } else {
            playerService.syncWithDeviceStatus(
              deviceTotalMs: status.totalSec,
              deviceElapsedMs: status.elapsedSec,
              deviceRunning: true,
            );
          }
        } else {
          playerService.syncWithDeviceStatus(
            deviceTotalMs: status.totalSec,
            deviceElapsedMs: status.elapsedSec,
            deviceRunning: true,
          );
        }
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

  // Try to resolve a device programIdHex (hex string) to a real app program id.
  // Returns null if resolution cannot be done reliably.
  Future<String?> _resolveProgramIdFromHex(String hex) async {
    if (hex.isEmpty) return null;
    await _ensureNameCacheLoaded();

    try {
      // Try ProgramCatalog lookup by UUID/hex first
      final entry = ProgramCatalog.instance.byUuid(hex);
      if (entry != null) {
        try {
          final dyn = entry as dynamic;
          // Common property names: id, slug, internalId
          if (dyn.id is String && (dyn.id as String).isNotEmpty) return dyn.id as String;
          if (dyn.slug is String && (dyn.slug as String).isNotEmpty) return dyn.slug as String;
          if (dyn.internalId != null) return '${dyn.internalId}';
        } catch (_) {
          // ignore and continue
        }
      }

      // Fallback: try parse hex as base-16 integer and lookup by internal id
      final intVal = int.tryParse(hex, radix: 16);
      if (intVal != null) {
        final byInt = ProgramCatalog.instance.byInternalId(intVal);
        if (byInt != null) {
          try {
            final dyn = byInt as dynamic;
            if (dyn.id is String && (dyn.id as String).isNotEmpty) return dyn.id as String;
            if (dyn.slug is String && (dyn.slug as String).isNotEmpty) return dyn.slug as String;
            return '$intVal';
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('[AutoReconnect] resolveProgramIdFromHex error: $e');
    }
    return null;
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
                if (!isPlaying) {
                  return IconButton(
                    tooltip: 'Player',
                    icon: const Icon(Icons.queue_music),
                    onPressed: () => _openPlayerPopup(),
                  );
                }
                // Active playback: icon + remaining time
                final rem = playerService.state.remaining;
                final h = rem.inHours;
                final m = rem.inMinutes % 60;
                final s = rem.inSeconds % 60;
                final timeText = h > 0
                    ? '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
                    : '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
                return GestureDetector(
                  onTap: () => _openPlayerPopup(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.play_circle_filled, color: Colors.greenAccent, size: 24),
                        const SizedBox(width: 4),
                        Text(
                          timeText,
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ), // ListenableBuilder
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

  Future<void> _openPlayerPopup() async {
    await _ensureNameCacheLoaded();

    // Wenn Player noch keine Queue hat: starte automatisch "My Programs" (gefiltert)
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

    String resolveTitle(String id) {
      final langCode =
          (ProgramLangController.instance.lang == ProgramLang.de) ? 'de' : 'en';
      var keyEn = playerService.titleKeyEnById[id];
      if (keyEn == null && id.contains('__slot_')) {
        final baseId = id.split('__slot_').first;
        keyEn = playerService.titleKeyEnById[baseId] ?? baseId;
      }
      keyEn ??= id;
      return ProgramNameLocalizer.instance.displayName(
        keyEn: keyEn,
        langCode: langCode,
      );
    }

    if (!mounted) return;
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
      // Strip __slot_<suffix> to get the base programId for catalog lookup.
      // The full slot key is kept in the queue for independent settings.
      final baseId = id.contains('__slot_') ? id.split('__slot_').first : id;
      final p = map[baseId];
      // Always include every persisted ID – even if not found in programs.json
      // (e.g. numeric catalog IDs, custom_ IDs, slot-key duplicates).
      // Missing from catalog just means the raw baseId is used as title fallback.
      playable.add(id);
      titles[id] = p?.name ?? baseId; // EN-key keyed by full slot key
    }

    return {'ids': playable, 'titles': titles};
  }

  /// Opens PlayerPopup after auto-reconnect detected a running device.
  void _openPlayerPopupForReconnect() {
    _openPlayerPopup();
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

