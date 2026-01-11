import 'dart:async';
import 'package:flutter/foundation.dart';

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

  void playQueue(List<String> queueIds, int startIndex,
      {Duration? duration, Map<String, String>? titleKeyEnById}) {
    if (queueIds.isEmpty) return;
    final idx = startIndex.clamp(0, queueIds.length - 1);
    final dur = duration ?? defaultDuration;

    // store provided title map (EN keys) for later resolving in UI
    _titleKeyEnById = titleKeyEnById ?? _titleKeyEnById;

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
    playQueue([programId], 0, duration: duration);
  }

  void play() {
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
    if (_state.queueIds.isEmpty) return;
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
    final dur = _state.total == Duration.zero ? defaultDuration : _state.total;

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
