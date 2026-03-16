import 'dart:async';
import 'package:flutter/foundation.dart';
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

  PlaylistItemSettings settingsFor(String programId) {
    return _settingsByProgramId[programId] ?? PlaylistItemSettings.defaults;
  }

  void setSettings(String programId, PlaylistItemSettings settings) {
    _settingsByProgramId[programId] = settings;
    // Notify listeners so UI (player, lists) can react immediately to changes
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
        _state = _state.copyWith(remaining: Duration.zero);
        notifyListeners();
        next(); // auto-advance
      } else {
        _state = _state.copyWith(remaining: rem);
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

    // If explicit duration passed -> use it; otherwise use settings for the first program
    Duration dur;
    if (duration != null) {
      dur = duration;
    } else {
      final pid = queueIds[idx];
      final s = settingsFor(pid);
      dur = Duration(minutes: s.durationMinutes);
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
      total: dur,
      remaining: dur,
    );

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

    // UI-only: stop any running ticker and set state without starting playback
    _stopTicker();
    _state = PlayerState(
      isPlaying: false,
      queueIds: List.unmodifiable(queueIds),
      currentIndex: idx,
      total: total,
      remaining: total,
    );
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
    // Determine program id at the target index (validate bounds)
    String? pid;
    if (_state.queueIds.isNotEmpty &&
        newIndex >= 0 &&
        newIndex < _state.queueIds.length) {
      pid = _state.queueIds[newIndex];
    }

    // duration from per-item settings (fallback to defaultDuration)
    final Duration dur = pid != null
        ? Duration(minutes: settingsFor(pid).durationMinutes)
        : defaultDuration;

    _stopTicker();
    _state = _state.copyWith(
      currentIndex: newIndex,
      total: dur,
      remaining: dur,
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
