import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/playlist_item_settings.dart';

class PlayerState {
  final bool isPlaying;
  final List<String> queueIds;
  final int currentIndex;
  final Duration total;
  final Duration remaining;

  const PlayerState({
    required this.isPlaying,
    required this.queueIds,
    required this.currentIndex,
    required this.total,
    required this.remaining,
  });

  static const empty = PlayerState(
    isPlaying: false,
    queueIds: <String>[],
    currentIndex: 0,
    total: Duration.zero,
    remaining: Duration.zero,
  );

  String? get currentProgramId {
    if (queueIds.isEmpty) return null;
    if (currentIndex < 0 || currentIndex >= queueIds.length) return null;
    return queueIds[currentIndex];
  }

  bool get hasNext => queueIds.isNotEmpty && currentIndex < queueIds.length - 1;
  bool get hasPrev => queueIds.isNotEmpty && currentIndex > 0;

  PlayerState copyWith({
    bool? isPlaying,
    List<String>? queueIds,
    int? currentIndex,
    Duration? total,
    Duration? remaining,
  }) {
    return PlayerState(
      isPlaying: isPlaying ?? this.isPlaying,
      queueIds: queueIds ?? this.queueIds,
      currentIndex: currentIndex ?? this.currentIndex,
      total: total ?? this.total,
      remaining: remaining ?? this.remaining,
    );
  }
}

class PlayerService extends ChangeNotifier {
  PlayerState _state = PlayerState.empty;
  PlayerState get state => _state;

  Timer? _ticker;

  // Phase 1 Default-Dauer: 15 Minuten (wie besprochen)
  static const Duration defaultDuration = Duration(minutes: 15);

  // BEGIN PATCH: store title keys for queue items (EN keys)
  Map<String, String> _titleKeyEnById = {};
  Map<String, String> get titleKeyEnById => _titleKeyEnById;
  // END PATCH

  // BEGIN PATCH: per-program settings (in-memory)
  final Map<String, PlaylistItemSettings> _settingsByProgramId = {};

  // SharedPreferences key prefix: prog_settings__<clientId>__<programId>
  static const _kSettingsPrefix = 'prog_settings__';

  static String _settingsKey(String clientId, String programId) =>
      '${_kSettingsPrefix}${clientId}__$programId';

  PlaylistItemSettings settingsFor(String programId) {
    return _settingsByProgramId[programId] ?? PlaylistItemSettings.defaults;
  }

  void setSettings(String programId, PlaylistItemSettings settings) {
    _settingsByProgramId[programId] = settings;
    // Notify listeners so UI (player, lists) can react immediately to changes
    notifyListeners();
    // Persist asynchronously (fire and forget)
    _persistSettings(programId, settings);
  }

  Future<void> _persistSettings(String programId, PlaylistItemSettings settings) async {
    try {
      // Avoid importing clients_store here: read raw pref directly
      final prefs = await SharedPreferences.getInstance();
      const kActive = 'clients_active_id_v1';
      final clientId = prefs.getString(kActive) ?? 'default';
      final key = _settingsKey(clientId, programId);
      await prefs.setString(key, jsonEncode(settings.toJson()));
    } catch (e) {
      debugPrint('[PlayerService] _persistSettings error: $e');
    }
  }

  /// Load all persisted settings for the given clientId into memory.
  /// Call this on app start and on client switch.
  Future<void> loadSettingsForClient(String clientId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final prefix = '${_kSettingsPrefix}${clientId}__';
      final keys = prefs.getKeys().where((k) => k.startsWith(prefix));
      _settingsByProgramId.clear();
      for (final key in keys) {
        final programId = key.substring(prefix.length);
        final raw = prefs.getString(key);
        if (raw != null) {
          try {
            final map = jsonDecode(raw) as Map<String, dynamic>;
            _settingsByProgramId[programId] = PlaylistItemSettings.fromJson(map);
          } catch (_) {
            // skip corrupt entry
          }
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[PlayerService] loadSettingsForClient error: $e');
    }
  }

  /// Clear in-memory settings (used when switching clients before loading new ones).
  void clearSettings() {
    _settingsByProgramId.clear();
    notifyListeners();
  }
  // END PATCH

  // BEGIN PATCH: uploading flag exposed for UI coordination
  bool _isUploading = false;
  bool get isUploading => _isUploading;

  void setUploading(bool v) {
    if (_isUploading == v) return;
    _isUploading = v;
    notifyListeners();
  }
  // END PATCH

  // BEGIN ADD: session persistence keys/helpers
  static const _kSessionKey = 'player_last_session_v1';

  Future<void> _persistSession(List<String> queueIds, int currentIndex) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Also persist any UI title map so reconnect can restore friendly names
      final payload = jsonEncode({
        'queueIds': queueIds,
        'currentIndex': currentIndex,
        'titles': _titleKeyEnById,
      });
      await prefs.setString(_kSessionKey, payload);
    } catch (e) {
      debugPrint('[PlayerService] _persistSession error: $e');
    }
  }

  /// Return persisted session or null if none
  Future<Map<String, dynamic>?> loadLastSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kSessionKey);
      if (raw == null || raw.isEmpty) return null;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map;
    } catch (e) {
      debugPrint('[PlayerService] loadLastSession error: $e');
      return null;
    }
  }
  // END ADD

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  void _startTicker() {
    _stopTicker();
    if (!_state.isPlaying) return;

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_state.isPlaying) return;

      final rem = _state.remaining - const Duration(seconds: 1);
      if (rem <= Duration.zero) {
        // Merged program finished — stop the app timer.
        // The device stops autonomously; we just reflect it in the UI.
        debugPrint('[PLAYLIST_TIME] TIMER_EXPIRED: merged total reached zero, stopping');
        _stopTicker();
        _state = _state.copyWith(isPlaying: false, remaining: Duration.zero);
        notifyListeners();
      } else {
        // Update remaining time; also advance currentIndex for UI display
        // so the popup shows the correct program name for each segment.
        final elapsed = _state.total - rem;
        int newIdx = 0;
        Duration cumulative = Duration.zero;
        for (int i = 0; i < _state.queueIds.length; i++) {
          final segDur = Duration(minutes: settingsFor(_state.queueIds[i]).durationMinutes);
          if (elapsed < cumulative + segDur) {
            newIdx = i;
            break;
          }
          cumulative += segDur;
          newIdx = i; // last segment
        }

        _state = _state.copyWith(
          remaining: rem,
          currentIndex: newIdx,
        );
        notifyListeners();
      }
    });
  }

  void playQueue(
      List<String> queueIds,
      int startIndex, {
        Duration? duration,
        Map<String, String>? titleKeyEnById,
      }) {
    // If empty -> reset cleanly (do not silently return)
    if (queueIds.isEmpty) {
      _stopTicker();
      _state = PlayerState.empty;
      notifyListeners();
      return;
    }

    final idx = startIndex.clamp(0, queueIds.length - 1);

    // Sum durations across ALL programs — the device plays them as one merged block.
    Duration totalDur;
    if (duration != null) {
      totalDur = duration;
    } else {
      int sumMin = 0;
      for (final id in queueIds) {
        sumMin += settingsFor(id).durationMinutes;
      }
      totalDur = Duration(minutes: sumMin);
    }

    // Remaining = total minus already-elapsed segments before startIndex
    Duration elapsedBefore = Duration.zero;
    for (int i = 0; i < idx; i++) {
      elapsedBefore += Duration(minutes: settingsFor(queueIds[i]).durationMinutes);
    }
    final remaining = totalDur - elapsedBefore;

    // [PLAYLIST_TIME] diagnostic: log what playQueue sets as total/remaining
    debugPrint('[PLAYLIST_TIME] playQueue: queueSize=${queueIds.length} startIndex=$idx totalDur=$totalDur remaining=$remaining');
    for (int i = 0; i < queueIds.length; i++) {
      final s = settingsFor(queueIds[i]);
      debugPrint('[PLAYLIST_TIME] playQueue item[$i] id=${queueIds[i]} settingsDurMin=${s.durationMinutes} settingsDur=${Duration(minutes: s.durationMinutes)}');
    }

    // store provided title map (EN keys) for later resolving in UI
    if (titleKeyEnById != null) {
      _titleKeyEnById = {
        ..._titleKeyEnById,
        ...titleKeyEnById,
      };
    }

    _state = PlayerState(
      isPlaying: true,
      queueIds: List.unmodifiable(queueIds),
      currentIndex: idx,
      total: totalDur,
      remaining: remaining,
    );

    // Persist last session (fire-and-forget)
    unawaited(_persistSession(_state.queueIds, _state.currentIndex));

    _startTicker();
    notifyListeners();
  }

  void playSingle(String programId, {Duration? duration}) {
    // prefer explicit duration; otherwise use settings
    final dur =
        duration ?? Duration(minutes: settingsFor(programId).durationMinutes);
    playQueue([programId], 0, duration: dur);
  }

  // BEGIN ADD: UI-only queue setter (no ticker, summed duration)
  void setQueueUiOnly(
      List<String> queueIds, {
        int startIndex = 0,
        Map<String, String>? titleKeyEnById,
      }) {
    // If empty -> reset cleanly (do not silently return)
    if (queueIds.isEmpty) {
      _stopTicker();
      _state = PlayerState.empty;
      notifyListeners();
      return;
    }

    final idx = startIndex.clamp(0, queueIds.length - 1).toInt();

    // store provided title map (EN keys) for UI resolving
    if (titleKeyEnById != null) {
      _titleKeyEnById = {
        ..._titleKeyEnById,
        ...titleKeyEnById,
      };
    }

    // sum durations from per-item settings
    final totalMinutes = queueIds
        .map((id) => settingsFor(id).durationMinutes)
        .fold<int>(0, (a, b) => a + b);

    final total = Duration(minutes: totalMinutes);

    // [PLAYLIST_TIME] diagnostic: setQueueUiOnly summed total
    debugPrint('[PLAYLIST_TIME] setQueueUiOnly: queueSize=${queueIds.length} summedMin=$totalMinutes total=$total');
    for (int i = 0; i < queueIds.length; i++) {
      final s = settingsFor(queueIds[i]);
      debugPrint('[PLAYLIST_TIME] setQueueUiOnly item[$i] id=${queueIds[i]} durMin=${s.durationMinutes}');
    }

    // UI-only: stop any running ticker and set state without starting playback
    _stopTicker();
    _state = PlayerState(
      isPlaying: false,
      queueIds: List.unmodifiable(queueIds),
      currentIndex: idx,
      total: total,
      remaining: total,
    );
    // Persist UI queue as last session (so reconnect can restore richer UI)
    unawaited(_persistSession(_state.queueIds, _state.currentIndex));
    notifyListeners();
  }
  // END ADD

  void play() {
    if (_state.queueIds.isEmpty) return;
    if (_state.isPlaying) return;
    _state = _state.copyWith(isPlaying: true);
    _startTicker();
    notifyListeners();
  }

  // Minimal additive API: mark the current queue as started (UI flow after external device start)
  void markStarted() {
    if (_state.queueIds.isEmpty) return;
    if (_state.isPlaying) return;
    _state = _state.copyWith(isPlaying: true);
    _startTicker();
    notifyListeners();
  }

  /// Sync app timer with real device status after reconnect.
  /// [deviceTotalMs] and [deviceElapsedMs] come from progStatus response
  /// (the device reports these values in milliseconds despite the field names).
  ///
  /// If [queueIds] is provided, the player will use them as the queue
  /// (used during reconnect when the original queue is not available).
  void syncWithDeviceStatus({
    required int deviceTotalMs,
    required int deviceElapsedMs,
    required bool deviceRunning,
    List<String>? queueIds,
    Map<String, String>? titleKeyEnById,
  }) {
    // If a queue is provided (reconnect scenario), install it
    if (queueIds != null && queueIds.isNotEmpty) {
      // install any provided UI title map first so subsequent UI uses the friendly titles
      if (titleKeyEnById != null && titleKeyEnById.isNotEmpty) {
        _titleKeyEnById = {
          ..._titleKeyEnById,
          ...titleKeyEnById,
        };
      }
      _state = _state.copyWith(queueIds: queueIds);
    }

    // If still no queue, create a synthetic single-item queue so the timer works
    if (_state.queueIds.isEmpty) {
      _state = _state.copyWith(queueIds: ['_reconnected_program']);
    }

    final deviceTotal = Duration(milliseconds: deviceTotalMs);
    final deviceRemaining = Duration(milliseconds: (deviceTotalMs - deviceElapsedMs).clamp(0, deviceTotalMs));

    debugPrint('[PLAYLIST_TIME] syncWithDeviceStatus: deviceTotal=$deviceTotal deviceRemaining=$deviceRemaining deviceRunning=$deviceRunning');

    // Compute which segment index the device is currently in
    final elapsed = Duration(milliseconds: deviceElapsedMs);
    int newIdx = 0;

    Duration cumulative = Duration.zero;
    for (int i = 0; i < _state.queueIds.length; i++) {
      final segDur = Duration(minutes: settingsFor(_state.queueIds[i]).durationMinutes);
      if (elapsed < cumulative + segDur) {
        newIdx = i;
        break;
      }
      cumulative += segDur;
      newIdx = i;
    }

    _stopTicker();
    _state = _state.copyWith(
      total: deviceTotal,
      remaining: deviceRemaining,
      currentIndex: newIdx,
      isPlaying: deviceRunning,
    );
    if (deviceRunning) _startTicker();
    notifyListeners();
  }

  void pause() {
    if (!_state.isPlaying) return;
    _state = _state.copyWith(isPlaying: false);
    _stopTicker();
    notifyListeners();
  }

  void stop() {
    _stopTicker();
    if (_state.queueIds.isEmpty) {
      _state = PlayerState.empty;
      notifyListeners();
      return;
    }
    _state = _state.copyWith(isPlaying: false, remaining: _state.total);
    // Clear persisted session when stopping playback entirely
    unawaited(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_kSessionKey);
      } catch (_) {}
    }());
    notifyListeners();
  }

  void next() {
    if (!_state.hasNext) {
      _stopTicker();
      _state = _state.copyWith(isPlaying: false, remaining: Duration.zero);
      notifyListeners();
      return;
    }
    _jumpTo(_state.currentIndex + 1, autoplay: _state.isPlaying);
  }

  void previous() {
    if (!_state.hasPrev) return;
    _jumpTo(_state.currentIndex - 1, autoplay: _state.isPlaying);
  }

  void _jumpTo(int newIndex, {required bool autoplay}) {
    if (_state.queueIds.isEmpty ||
        newIndex < 0 ||
        newIndex >= _state.queueIds.length) return;

    // Compute remaining = total minus elapsed segments before newIndex
    Duration elapsedBefore = Duration.zero;
    for (int i = 0; i < newIndex; i++) {
      elapsedBefore += Duration(minutes: settingsFor(_state.queueIds[i]).durationMinutes);
    }
    final raw = _state.total - elapsedBefore;
    final remaining = raw < Duration.zero ? Duration.zero : (raw > _state.total ? _state.total : raw);

    // [PLAYLIST_TIME] diagnostic: program transition
    debugPrint('[PLAYLIST_TIME] _jumpTo: newIndex=$newIndex elapsedBefore=$elapsedBefore remaining=$remaining autoplay=$autoplay');

    _stopTicker();
    _state = _state.copyWith(
      currentIndex: newIndex,
      remaining: remaining,
      isPlaying: autoplay,
    );
    if (autoplay) _startTicker();
    notifyListeners();
  }

  @override
  void dispose() {
    _stopTicker();
    super.dispose();
  }
}
