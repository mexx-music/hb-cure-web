import 'package:flutter/material.dart';
import '../../models/playlist_item_settings.dart';
import 'package:hbcure/l10n/gen/app_localizations.dart';

class PlaylistItemSetupSheet extends StatefulWidget {
  final String programId;
  final PlaylistItemSettings initial;
  const PlaylistItemSetupSheet({super.key, required this.programId, required this.initial});

  @override
  State<PlaylistItemSetupSheet> createState() => _PlaylistItemSetupSheetState();
}

class _PlaylistItemSetupSheetState extends State<PlaylistItemSetupSheet> {
  late int _duration;
  late double _intensity;
  late bool _electric;
  late bool _magnetic;
  late Waveform _electricWaveform;
  late Waveform _magneticWaveform;

  @override
  void initState() {
    super.initState();
    _duration = widget.initial.durationMinutes;
    _intensity = widget.initial.intensity.toDouble();
    _electric = widget.initial.electric;
    _magnetic = widget.initial.magnetic;
    // default waveforms from initial settings (fallback to Waveform.sine)
    _electricWaveform = widget.initial.electricWaveform;
    _magneticWaveform = widget.initial.magneticWaveform;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    String waveformLabel(Waveform w) {
      switch (w) {
        case Waveform.sine: return l10n.waveformSine;
        case Waveform.triangle: return l10n.waveformTriangle;
        case Waveform.rectangle: return l10n.waveformRectangle;
        case Waveform.sawtooth: return l10n.waveformSawtooth;
      }
    }

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Text(l10n.setupTitle, style: Theme.of(context).textTheme.titleMedium)),
            const SizedBox(height: 12),
                  Text(l10n.setupDurationMinutes),
                  DropdownButton<int>(
                    value: _duration,
                    items: [5, 10, 15, 20, 30, 45, 60, 120, 180]
                        .map((e) {
                          String label;
                          if (e >= 60 && e % 60 == 0) {
                            label = '${e ~/ 60} h';
                          } else {
                            label = '$e min';
                          }
                          return DropdownMenuItem(value: e, child: Text(label));
                        })
                        .toList(),
                    onChanged: (v) => setState(() => _duration = v ?? _duration),
                  ),

                  const SizedBox(height: 8),
                  Text(l10n.intensity),
                  Slider(
                    min: 1,
                    max: 100,
                    divisions: 99,
                    value: _intensity,
                    label: _intensity.round().toString(),
                    onChanged: (v) => setState(() => _intensity = v),
                  ),

                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(l10n.setupElectric),
                      Switch(value: _electric, onChanged: (v) => setState(() => _electric = v)),
                    ],
                  ),

                  // Electric waveform selector (only when electric enabled)
                  if (_electric) ...[
                    const SizedBox(height: 8),
                    DropdownButtonFormField<Waveform>(
                      value: _electricWaveform,
                      decoration: InputDecoration(labelText: l10n.setupElectricWaveform),
                      items: Waveform.values.map((w) {
                        return DropdownMenuItem(
                          value: w,
                          child: Text(waveformLabel(w)),
                        );
                      }).toList(),
                      onChanged: (v) => setState(() => _electricWaveform = v ?? _electricWaveform),
                    ),
                  ],

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(l10n.setupMagnetic),
                      Switch(value: _magnetic, onChanged: (v) => setState(() => _magnetic = v)),
                    ],
                  ),

                  // Magnetic waveform selector (only when magnetic enabled)
                  if (_magnetic) ...[
                    const SizedBox(height: 8),
                    DropdownButtonFormField<Waveform>(
                      value: _magneticWaveform,
                      decoration: InputDecoration(labelText: l10n.setupMagneticWaveform),
                      items: Waveform.values.map((w) {
                        return DropdownMenuItem(
                          value: w,
                          child: Text(waveformLabel(w)),
                        );
                      }).toList(),
                      onChanged: (v) => setState(() => _magneticWaveform = v ?? _magneticWaveform),
                    ),
                  ],

                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(onPressed: () => Navigator.of(context).pop(null), child: Text(l10n.setupCancel)),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {
                          final settings = PlaylistItemSettings(
                            durationMinutes: _duration,
                            intensity: _intensity.round(),
                            electric: _electric,
                            electricWaveform: _electricWaveform,
                            magnetic: _magnetic,
                            magneticWaveform: _magneticWaveform,
                          );
                          Navigator.of(context).pop(settings);
                        },
                        child: Text(l10n.setupSave),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}

Future<PlaylistItemSettings?> showPlaylistItemSetup(BuildContext context, String programId, PlaylistItemSettings initial) {
  return showDialog<PlaylistItemSettings>(
    context: context,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: PlaylistItemSetupSheet(programId: programId, initial: initial),
      ),
    ),
  );
}
