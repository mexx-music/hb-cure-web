import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import '../../models/program_item.dart';
import '../../services/cube_device_service.dart';
import '../../services/my_programs_service.dart';
import '../../services/cure_device_unlock_service.dart';
import '../widgets/gradient_background.dart';
import '../widgets/duration_wheel_picker.dart';
import '../widgets/intensity_picker.dart';
import '../theme/app_colors.dart';
import 'dart:math' as math;
import 'dart:async';

class ProgramDetailPage extends StatefulWidget {
  final ProgramItem program;
  final String deviceId;

  const ProgramDetailPage({super.key, required this.program, required this.deviceId});

  @override
  State<ProgramDetailPage> createState() => _ProgramDetailPageState();
}

class _ProgramDetailPageState extends State<ProgramDetailPage> {
  int? _selectedMinutes = 15;
  int _intensity = 100;
  bool _powerMode = false;
  bool _inMyPrograms = false;
  final _myService = MyProgramsService();
  final List<int> _durations = [10, 15, 20, 30, 45, 60, 90, 120, 180];
  // waveform selections for electric and magnetic fields
  String _electricWaveform = 'sine';
  String _magneticWaveform = 'sine';

  // --- Timer / runtime tracking for started program ---
  Timer? _statusTimer;
  DateTime? _startedAt;
  Duration _elapsedLocal = Duration.zero;
  String? _lastProgStatus;
  // ----------------------------------------------------

  @override
  void initState() {
    super.initState();
    _checkInMyPrograms();
  }

  Future<void> _checkInMyPrograms() async {
    final contains = await _myService.contains(widget.program.id);
    if (!mounted) return;
    setState(() => _inMyPrograms = contains);
  }

  Future<void> _toggleMyPrograms() async {
    if (_inMyPrograms) {
      debugPrint('Remove from My Programs: ${widget.program.id} (${widget.program.name})');
      await _myService.remove(widget.program.id);
      if (!mounted) return;
      setState(() => _inMyPrograms = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Entfernt aus My Programs')));
    } else {
      debugPrint('Add to My Programs: ${widget.program.id} (${widget.program.name})');
      await _myService.add(widget.program.id);
      if (!mounted) return;
      setState(() => _inMyPrograms = true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Hinzugefügt zu My Programs')));
    }
  }

  void _startProgram() async {
    final minutes = _selectedMinutes ?? 15;
    final duration = Duration(minutes: minutes);
    final svc = CureDeviceUnlockService.instance;

    // Use deviceId passed to the page, otherwise fall back to shared native connection
    final pageDeviceId = widget.deviceId.trim();
    final deviceId = pageDeviceId.isNotEmpty ? pageDeviceId : svc.nativeConnectedDeviceId;
    if (deviceId == null || deviceId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No device connected. Please connect first.')),
      );
      return;
    }

    try {
      // Ensure native/shared connection is active for the target device
      if (!svc.isNativeConnected || svc.nativeConnectedDeviceId != deviceId) {
        await svc.nativeConnect(deviceId);
      }

      await CubeDeviceService.instance.sendProgram(
        program: widget.program,
        duration: duration,
        powerMode: _powerMode,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Program started')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Start failed: $e')));
    }
  }

  // Final start flow: connect (if needed) -> send program using shared/native transport
  Future<void> _startProgramFinal() async {
    final svc = CureDeviceUnlockService.instance;

    // DeviceId source: prefer page-provided deviceId, otherwise shared nativeConnectedDeviceId
    final String? deviceId =
    (widget is dynamic && (widget as dynamic).deviceId is String)
        ? (widget as dynamic).deviceId as String
        : svc.nativeConnectedDeviceId;

    if (deviceId == null || deviceId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kein Cube verbunden. Bitte zuerst verbinden.')),
      );
      return;
    }

    // Ensure native/shared connection (shared transport) is active for that device
    if (!svc.isNativeConnected || svc.nativeConnectedDeviceId != deviceId) {
      try {
        await svc.nativeConnect(deviceId);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connect failed: $e')),
        );
        return;
      }
    }

    final minutes = _selectedMinutes ?? 15;
    final duration = Duration(minutes: minutes);

    try {
      await CubeDeviceService.instance.sendProgram(
        program: widget.program,
        duration: duration,
        powerMode: _powerMode,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Programm gestartet')),
      );

      // Start local timer tracking
      _statusTimer?.cancel();
      _startedAt = DateTime.now();
      _elapsedLocal = Duration.zero;
      setState(() {});
      _statusTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return;
        final now = DateTime.now();
        setState(() {
          _elapsedLocal = now.difference(_startedAt ?? now);
        });
      });
    } catch (e, st) {
      debugPrint('StartProgram failed: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Start fehlgeschlagen: $e')),
      );
    }
  }

  void _stopProgram() async {
    try {
      // Use native unlock service progClear as STOP
      final ok = await CureDeviceUnlockService.instance.progClear();

      // stop local timer and reset
      _statusTimer?.cancel();
      _statusTimer = null;
      _startedAt = null;
      _elapsedLocal = Duration.zero;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? 'STOP OK (progClear)' : 'STOP fehlgeschlagen (kein OK)')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Stop failed: $e')));
    }
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  void _showDurationPicker() {
    showCupertinoModalPopup(
      context: context,
      builder: (context) => DurationWheelPicker(
        durationsMinutes: _durations,
        initialMinutes: _selectedMinutes ?? 15,
        onSelected: (minutes) {
          setState(() => _selectedMinutes = minutes);
        },
      ),
    );
  }

  void _showIntensityPicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => IntensityPicker(
        initialValue: _intensity,
        onSelected: (intensity) {
          setState(() => _intensity = intensity);
        },
      ),
    );
  }

  // helper to show waveform selection bottom sheet
  void _showWaveformPicker(String title, String current, ValueChanged<String> onSelected) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.cardBackground,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
      builder: (ctx) {
        final options = ['sine', 'triangle', 'rectangle', 'saw-tooth'];
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(padding: const EdgeInsets.all(12), child: Text(title, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold))),
              ...options.map((o) => ListTile(
                title: Text(o, style: const TextStyle(color: AppColors.textPrimary)),
                onTap: () {
                  onSelected(o);
                  Navigator.of(ctx).pop();
                },
                selected: o == current,
                selectedTileColor: AppColors.primary.withOpacity(0.12),
              )),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Defensive: ensure debug paints are disabled for this page render in debug mode
    if (kDebugMode) {
      debugPaintBaselinesEnabled = false;
      debugPaintSizeEnabled = false;
      debugPaintPointersEnabled = false;
    }
    final mq = MediaQuery.of(context);
    final cappedScale = math.min(mq.textScaleFactor, 1.2);
    return GradientBackground(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
        child: MediaQuery(
          data: mq.copyWith(textScaleFactor: cappedScale),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary), onPressed: () => Navigator.pop(context)),
                    const Spacer(),
                    IconButton(
                      icon: Icon(_inMyPrograms ? Icons.favorite : Icons.favorite_border, color: _inMyPrograms ? AppColors.accentGreen : AppColors.textPrimary),
                      onPressed: _toggleMyPrograms,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Icon(Icons.change_history, size: 80, color: AppColors.warmAccent),
                const SizedBox(height: 16),
                // limit scaling/size to avoid overflow on large system text settings
                Text(
                  widget.program.name,
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(color: AppColors.textPrimary, fontSize: 28),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textScaleFactor: 1.0,
                ),
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: _showIntensityPicker,
                  child: Container(
                    height: 52,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(color: AppColors.cardBackground, borderRadius: BorderRadius.circular(24)),
                    alignment: Alignment.center,
                    child: Container(
                      width: double.infinity,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: AppColors.cardBackground, borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text('Intensity: $_intensity%', style: const TextStyle(color: AppColors.textPrimary, decoration: TextDecoration.none, fontSize: 18), textAlign: TextAlign.center, textScaleFactor: 1.0),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Waveform selectors: responsive layout
                LayoutBuilder(builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 560;
                  final left = Container(
                    height: 48,
                    decoration: BoxDecoration(color: AppColors.cardBackground, borderRadius: BorderRadius.circular(24)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 12, right: 8),
                            child: Text('Use electric fields', style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, decoration: TextDecoration.none), textScaleFactor: 1.0, overflow: TextOverflow.ellipsis, maxLines: 1),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => _showWaveformPicker('Electric waveform', _electricWaveform, (v) => setState(() => _electricWaveform = v)),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [Text(_electricWaveform, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, decoration: TextDecoration.none)), const SizedBox(width: 6), const Icon(Icons.arrow_drop_down, color: AppColors.textPrimary, size: 20)]),
                          ),
                        ),
                      ],
                    ),
                  );

                  final right = Container(
                    height: 48,
                    decoration: BoxDecoration(color: AppColors.cardBackground, borderRadius: BorderRadius.circular(24)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 12, right: 8),
                            child: Text('Use magnetic fields', style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, decoration: TextDecoration.none), textScaleFactor: 1.0, overflow: TextOverflow.ellipsis, maxLines: 1),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => _showWaveformPicker('Magnetic waveform', _magneticWaveform, (v) => setState(() => _magneticWaveform = v)),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [Text(_magneticWaveform, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, decoration: TextDecoration.none)), const SizedBox(width: 6), const Icon(Icons.arrow_drop_down, color: AppColors.textPrimary, size: 20)]),
                          ),
                        ),
                      ],
                    ),
                  );

                  if (isWide) {
                    return Row(children: [Expanded(child: left), const SizedBox(width: 12), Expanded(child: right)]);
                  }
                  return Column(children: [left, const SizedBox(height: 12), right]);
                }),
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: _showDurationPicker,
                  child: Container(
                    height: 52,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(color: AppColors.cardBackground, borderRadius: BorderRadius.circular(24)),
                    alignment: Alignment.center,
                    child: Container(
                      width: double.infinity,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: AppColors.cardBackground, borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text('Duration: ${_selectedMinutes} min', style: const TextStyle(color: AppColors.textPrimary, decoration: TextDecoration.none, fontSize: 18), textAlign: TextAlign.center, textScaleFactor: 1.0),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _startProgramFinal,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accentGreen,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        ),
                        child: const Text(
                          'Start program',
                          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18),
                          textScaleFactor: 1.0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _stopProgram,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        ),
                        child: const Text(
                          'STOP',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                          textScaleFactor: 1.0,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => debugPrint('Help pressed'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                  child: const Text('Help', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 18), textScaleFactor: 1.0),
                ),

                const SizedBox(height: 16),
                // --- Compact centered Timer display ---
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.cardBackground,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    constraints: const BoxConstraints(minWidth: 120, maxWidth: 360),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Text(
                              'Program Timer',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _startedAt == null
                                  ? 'Timer: nicht gestartet'
                                  : '${_elapsedLocal.inMinutes.toString().padLeft(2, '0')}:${(_elapsedLocal.inSeconds % 60).toString().padLeft(2, '0')} / ${_selectedMinutes ?? 0} min',
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 14,
                              ),
                            ),
                            if (_lastProgStatus != null) ...[
                              const SizedBox(height: 6),
                              ConstrainedBox(
                                constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                                child: Text(
                                  'Last progStatus: $_lastProgStatus',
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  ),
                ),

                const SizedBox(height: 12),
                // ...existing closing widgets...
              ],
            ),
          ),
        ),
      ),
    );
  }
}
