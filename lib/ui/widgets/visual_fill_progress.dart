import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

typedef VisualFillBuilder = Widget Function(int cycleIndex, double progress);

/// Emits (cycleIndex, progress) where:
/// - cycleIndex increases every tick (1s default)
/// - progress is 0..1 across a fixed cycleDuration (default 50s)
///
/// Pure UI helper. No business logic.
class VisualFillProgress extends StatefulWidget {
  final Duration tick;
  final Duration cycleDuration;
  final VisualFillBuilder builder;
  final bool isActive; // new: run only when active

  const VisualFillProgress({
    super.key,
    required this.builder,
    this.tick = const Duration(seconds: 1),
    this.cycleDuration = const Duration(seconds: 50),
    this.isActive = true,
  });

  @override
  State<VisualFillProgress> createState() => _VisualFillProgressState();
}

class _VisualFillProgressState extends State<VisualFillProgress> {
  Timer? _timer;
  int _cycleIndex = 0;
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) _start();
  }

  @override
  void didUpdateWidget(covariant VisualFillProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tick != widget.tick || oldWidget.cycleDuration != widget.cycleDuration) {
      // if params changed, restart only if active
      if (widget.isActive) _restart();
    }
    if (oldWidget.isActive != widget.isActive) {
      if (widget.isActive) {
        // became active -> restart at 0
        _restart();
      } else {
        // became inactive -> stop and reset progress
        _timer?.cancel();
        setState(() {
          _cycleIndex = 0;
          _progress = 0.0;
        });
      }
    }
  }

  void _restart() {
    _timer?.cancel();
    _cycleIndex = 0;
    _progress = 0.0;
    _start();
  }

  void _start() {
    final totalTicks = (widget.cycleDuration.inMilliseconds / widget.tick.inMilliseconds).round().clamp(1, 1000000);

    _timer = Timer.periodic(widget.tick, (_) {
      if (!mounted) return;
      // if widget became inactive between ticks, cancel
      if (!widget.isActive) {
        _timer?.cancel();
        return;
      }
      setState(() {
        _cycleIndex++;
        final t = (_cycleIndex % totalTicks) / totalTicks;
        _progress = t.clamp(0.0, 1.0);
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_cycleIndex, _progress);
}
