import 'package:flutter/material.dart';
import 'package:hbcure/ui/widgets/gradient_background.dart';
import 'package:hbcure/ui/theme/app_colors.dart';
import 'package:hbcure/services/program_language_controller.dart';
import 'package:hbcure/core/program_mode.dart';
import 'package:hbcure/services/app_memory.dart';
import 'package:hbcure/services/custom_frequencies_service.dart';
import 'package:hbcure/services/custom_frequencies_store.dart' as store;
import 'package:hbcure/services/my_programs_service.dart';
import 'package:hbcure/services/custom_frequency_name_store.dart';
import 'package:hbcure/l10n/gen/app_localizations.dart';
import 'package:hbcure/app_services.dart';
import 'package:hbcure/models/playlist_item_settings.dart';

class CustomFrequenciesPage extends StatefulWidget {
  const CustomFrequenciesPage({super.key});

  @override
  State<CustomFrequenciesPage> createState() => _CustomFrequenciesPageState();
}

class _CustomFrequenciesPageState extends State<CustomFrequenciesPage> {
  // Use the central service storage
  List<CustomFrequencyEntry> get _entries =>
      CustomFrequenciesService.instance.items;
  final _myPrograms = MyProgramsService.instance;
  late final VoidCallback _langListener;

  @override
  void initState() {
    super.initState();
    _langListener = () {
      if (mounted) setState(() {});
    };
    ProgramLangController.instance.addListener(_langListener);
  }

  @override
  void dispose() {
    ProgramLangController.instance.removeListener(_langListener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isExpert = AppMemory.instance.programMode == ProgramMode.expert;

    if (!isExpert) {
      return GradientBackground(
        child: Center(
          child: Text(
            l10n.cfExpertOnly,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.accentGreen,
        child: const Icon(Icons.add, color: Colors.black),
        onPressed: _openCreateDialog,
      ),
      body: GradientBackground(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    l10n.customFrequenciesTitle,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.cfNote,
                    icon: const Icon(
                      Icons.info_outline,
                      color: AppColors.textPrimary,
                    ),
                    onPressed: _showInfoDialog,
                  ),
                ],
              ),
              const SizedBox(height: 10),

              if (_entries.isEmpty) ...[
                _emptyCard(),
                const SizedBox(height: 14),
              ],

              Expanded(
                child: ListView.separated(
                  itemCount: _entries.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (ctx, i) {
                    final e = _entries[i];
                    return _entryTile(e, i);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyCard() {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.tune, color: AppColors.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.cfNoEntries,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.cfNoEntriesHint,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _entryTile(CustomFrequencyEntry e, int index) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: ListTile(
        title: Row(
          children: [
            Expanded(
              child: Text(
                e.name,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        subtitle: Text(
          '${l10n.cfFrequency}: ${e.frequencyHz.toStringAsFixed(_needsDecimals(e.frequencyHz) ? 2 : 0)} Hz • '
          '${l10n.duration}: ${e.durationMin}m • '
          '${l10n.intensity}: ${e.intensityPct}%',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        // Remove the old chevron and popup menu. Instead show add/check icon and support long-press for edit/delete.
        trailing: _TempAddButton(
          onAdd: () async {
            final l10n = AppLocalizations.of(context)!;
            try {
              await MyProgramsService().add(e.id);
              playerService.setSettings(
                e.id,
                PlaylistItemSettings(
                  durationMinutes: e.durationMin,
                  intensity: e.intensityPct,
                  electric: e.useElectric,
                  electricWaveform: _wf(e.electricWaveform),
                  magnetic: e.useMagnetic,
                  magneticWaveform: _wf(e.magneticWaveform),
                ),
              );
              // Persist human-readable name so My Programs can show it
              try {
                await CustomFrequencyNameStore.instance.setName(e.id, e.name);
              } catch (_) {}
              // small UI refresh
              if (!mounted) return;
              setState(() {});
              final progTitle = e.name;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(milliseconds: 1500),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  content: Row(
                    children: [
                      const Icon(Icons.check, color: Colors.white),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          ProgramLangController.instance.lang == ProgramLang.de
                              ? '$progTitle wurde zu „Meine Programme" hinzugefügt'
                              : '$progTitle added to "My Programs"',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            } catch (err) {
              if (!mounted) return;
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(l10n.singleStartFailed)));
            }
          },
        ),
        onTap: null,
        onLongPress: () => _showEditDeleteDialog(e),
      ),
    );
  }

  Future<void> _handleAddToMyPrograms(CustomFrequencyEntry e) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      await MyProgramsService().add(e.id);
      // Persist human-readable name so My Programs can show it
      try {
        await CustomFrequencyNameStore.instance.setName(e.id, e.name);
      } catch (_) {}
      // small UI refresh
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 1500),
          backgroundColor: Theme.of(context).colorScheme.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          content: Row(
            children: [
              const Icon(Icons.check, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  ProgramLangController.instance.lang == ProgramLang.de
                      ? '${e.name} wurde zu „Meine Programme" hinzugefügt'
                      : '${e.name} added to "My Programs"',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.singleStartFailed)));
    }
  }

  Future<void> _showEditDeleteDialog(CustomFrequencyEntry e) async {
    final l10n = AppLocalizations.of(context)!;
    if (!mounted) return;

    final choice = await showModalBottomSheet<String?>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: Material(
          color: AppColors.cardBackground,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.edit, color: AppColors.textPrimary),
                title: Text(
                  l10n.cfEdit,
                  style: const TextStyle(color: AppColors.textPrimary),
                ),
                onTap: () => Navigator.pop(ctx, 'edit'),
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: AppColors.accentRed),
                title: Text(
                  l10n.cfDelete,
                  style: const TextStyle(color: AppColors.accentRed),
                ),
                onTap: () => Navigator.pop(ctx, 'delete'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );

    if (choice == null) return;
    if (choice == 'edit') {
      final updated = await showDialog<CustomFrequencyEntry>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _CustomFrequencyDialog(initial: e),
      );
      if (updated == null) return;
      CustomFrequenciesService.instance.upsert(updated);
      try {
        await CustomFrequencyNameStore.instance.setName(
          updated.id,
          updated.name,
        );
      } catch (_) {}
      if (!mounted) return;
      setState(() {});
    } else if (choice == 'delete') {
      CustomFrequenciesService.instance.removeById(e.id);
      try {
        await store.CustomFrequenciesStore.instance.remove(e.id);
      } catch (_) {}
      try {
        await CustomFrequencyNameStore.instance.remove(e.id);
      } catch (_) {}
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.cfDeleted)));
    }
  }

  bool _needsDecimals(double v) => (v - v.roundToDouble()).abs() > 0.000001;

  void _showInfoDialog() {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: Text(
          l10n.cfNote,
          style: const TextStyle(color: AppColors.textPrimary),
        ),
        content: Text(
          l10n.cfInfoText,
          style: const TextStyle(color: AppColors.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'OK',
              style: TextStyle(color: AppColors.accentGreen),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openCreateDialog() async {
    final created = await showDialog<CustomFrequencyEntry>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _CustomFrequencyDialog(),
    );

    if (created == null) return;
    CustomFrequenciesService.instance.upsert(created);
    // Persist human-readable name so My Programs can show it
    try {
      await CustomFrequencyNameStore.instance.setName(created.id, created.name);
    } catch (_) {}
    // Persist full entry to store for app restarts
    try {
      await store.CustomFrequenciesStore.instance.upsert(
        store.CustomFrequencyEntry(
          id: created.id,
          name: created.name,
          frequencyHz: created.frequencyHz,
          durationMin: created.durationMin,
          intensityPct: created.intensityPct,
          useElectric: created.useElectric,
          electricWaveform: created.electricWaveform,
          useMagnetic: created.useMagnetic,
          magneticWaveform: created.magneticWaveform,
        ),
      );
    } catch (_) {}
    setState(() {});
  }

  void _openEntryActions(CustomFrequencyEntry e, int index) async {
    final l10n = AppLocalizations.of(context)!;
    final inMy = await _myPrograms.contains(e.id);
    if (!mounted) return;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return SafeArea(
          child: Material(
            color: AppColors.cardBackground,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                ListTile(
                  leading: Icon(
                    inMy ? Icons.favorite : Icons.favorite_border,
                    color: inMy ? AppColors.accentGreen : AppColors.textPrimary,
                  ),
                  title: Text(
                    inMy ? l10n.cfRemoveFromMyPrograms : l10n.addToMyPrograms,
                    style: const TextStyle(color: AppColors.textPrimary),
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    if (inMy) {
                      await MyProgramsService().remove(e.id);
                    } else {
                      await MyProgramsService().add(e.id);
                    }
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          inMy
                              ? l10n.cfRemovedFromMyPrograms
                              : l10n.addedToMyPrograms,
                        ),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.play_arrow,
                    color: AppColors.textPrimary,
                  ),
                  title: Text(
                    l10n.cfStart,
                    style: const TextStyle(color: AppColors.textPrimary),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(milliseconds: 1500),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        content: Text(
                          l10n.cfStartFlowNext,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.edit, color: AppColors.textPrimary),
                  title: Text(
                    l10n.cfEdit,
                    style: const TextStyle(color: AppColors.textPrimary),
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final updated = await showDialog<CustomFrequencyEntry>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => _CustomFrequencyDialog(initial: e),
                    );
                    if (updated == null) return;
                    CustomFrequenciesService.instance.upsert(updated);
                    try {
                      await CustomFrequencyNameStore.instance.setName(
                        updated.id,
                        updated.name,
                      );
                    } catch (_) {}
                    setState(() {});
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete, color: AppColors.accentRed),
                  title: Text(
                    l10n.cfDelete,
                    style: const TextStyle(color: AppColors.accentRed),
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    CustomFrequenciesService.instance.removeById(e.id);
                    try {
                      await store.CustomFrequenciesStore.instance.remove(e.id);
                    } catch (_) {}
                    try {
                      await CustomFrequencyNameStore.instance.remove(e.id);
                    } catch (_) {}
                    setState(() {});
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(l10n.cfDeleted)));
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }
}

Waveform _wf(String s) => s == 'saw-tooth'
    ? Waveform.sawtooth
    : Waveform.values.firstWhere((w) => w.name == s, orElse: () => Waveform.sine);

class _CustomFrequencyDialog extends StatefulWidget {
  final CustomFrequencyEntry? initial;

  const _CustomFrequencyDialog({this.initial});

  @override
  State<_CustomFrequencyDialog> createState() => _CustomFrequencyDialogState();
}

class _CustomFrequencyDialogState extends State<_CustomFrequencyDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _freqCtrl;

  int _durationMin = 15;
  int _intensity = 100;

  bool _useElectric = true;
  String _electricWaveform = 'sine';

  bool _useMagnetic = true;
  String _magneticWaveform = 'sine';

  String? _error;
  bool _defaultNameSet = false;

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    _nameCtrl = TextEditingController(text: init?.name ?? '');
    _freqCtrl = TextEditingController(
      text: init != null ? init.frequencyHz.toString() : '963',
    );
    _defaultNameSet = init != null;

    if (init != null) {
      _durationMin = init.durationMin;
      _intensity = init.intensityPct;
      _useElectric = init.useElectric;
      _electricWaveform = init.electricWaveform;
      _useMagnetic = init.useMagnetic;
      _magneticWaveform = init.magneticWaveform;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _freqCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    // Set localized default name once (only for new entries)
    if (!_defaultNameSet) {
      _nameCtrl.text = l10n.cfDefaultName;
      _defaultNameSet = true;
    }

    return AlertDialog(
      backgroundColor: AppColors.cardBackground,
      title: Text(
        l10n.customFrequency,
        style: const TextStyle(color: AppColors.textPrimary),
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label('Name'), // identical in DE/EN
            const SizedBox(height: 6),
            _textField(_nameCtrl, hint: 'Name', keyboard: TextInputType.text),
            const SizedBox(height: 12),

            _label(l10n.cfFrequency),
            const SizedBox(height: 6),
            _textField(
              _freqCtrl,
              hint: l10n.cfFreqHint,
              keyboard: const TextInputType.numberWithOptions(decimal: true),
            ),

            const SizedBox(height: 14),
            _rowLabel(l10n.duration, '${_durationMin}m'),
            Slider(
              value: _durationMin.toDouble(),
              min: 1,
              max: 180,
              divisions: 179,
              onChanged: (v) => setState(() => _durationMin = v.round()),
            ),

            const SizedBox(height: 8),
            _rowLabel(l10n.intensity, '$_intensity%'),
            Slider(
              value: _intensity.toDouble(),
              min: 0,
              max: 100,
              divisions: 100,
              onChanged: (v) => setState(() => _intensity = v.round()),
            ),

            const SizedBox(height: 14),
            _label(l10n.cfElectricFields),
            const SizedBox(height: 6),
            _waveRow(
              enabled: _useElectric,
              onToggle: (v) => setState(() => _useElectric = v),
              value: _electricWaveform,
              onChanged: (v) => setState(() => _electricWaveform = v),
            ),

            const SizedBox(height: 14),
            _label(l10n.cfMagneticFields),
            const SizedBox(height: 6),
            _waveRow(
              enabled: _useMagnetic,
              onToggle: (v) => setState(() => _useMagnetic = v),
              value: _magneticWaveform,
              onChanged: (v) => setState(() => _magneticWaveform = v),
            ),

            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: AppColors.accentRed)),
            ],
          ],
        ),
      ),
      actions: [
        IconButton(
          tooltip: l10n.cfCancel,
          icon: const Icon(Icons.close, color: AppColors.textSecondary),
          onPressed: () => Navigator.pop(context),
        ),
        IconButton(
          tooltip: l10n.cfSave,
          icon: const Icon(Icons.check, color: AppColors.accentGreen),
          onPressed: _onSave,
        ),
      ],
    );
  }

  Widget _label(String s) =>
      Text(s, style: const TextStyle(color: AppColors.textSecondary));

  Widget _rowLabel(String left, String right) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _label(left),
        Text(right, style: const TextStyle(color: AppColors.textSecondary)),
      ],
    );
  }

  Widget _textField(
    TextEditingController ctrl, {
    required String hint,
    required TextInputType keyboard,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboard,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white.withOpacity(0.06),
        border: const OutlineInputBorder(),
      ),
      style: const TextStyle(color: AppColors.textPrimary),
    );
  }

  Widget _waveRow({
    required bool enabled,
    required ValueChanged<bool> onToggle,
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    final options = const ['sine', 'triangle', 'rectangle', 'saw-tooth'];
    final l10n = AppLocalizations.of(context)!;

    String _labelForOption(String o) {
      switch (o) {
        case 'sine':
          return l10n.waveformSine;
        case 'triangle':
          return l10n.waveformTriangle;
        case 'rectangle':
          return l10n.waveformRectangle;
        case 'saw-tooth':
          return l10n.waveformSawtooth;
        default:
          return o;
      }
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.borderSubtle),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          Checkbox(value: enabled, onChanged: (v) => onToggle(v ?? false)),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                isExpanded: true,
                items: options
                    .map(
                      (o) => DropdownMenuItem(
                        value: o,
                        child: Text(_labelForOption(o)),
                      ),
                    )
                    .toList(),
                onChanged: enabled ? (v) => onChanged(v ?? value) : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onSave() {
    final l10n = AppLocalizations.of(context)!;
    final name = _nameCtrl.text.trim();
    final freqRaw = _freqCtrl.text.trim().replaceAll(',', '.');

    final freq = double.tryParse(freqRaw);
    if (name.isEmpty) {
      setState(() => _error = l10n.cfErrorName);
      return;
    }
    if (freq == null || freq <= 0) {
      setState(() => _error = l10n.cfErrorFrequency);
      return;
    }

    final existingId = widget.initial?.id;
    final id = existingId ?? 'custom_${DateTime.now().millisecondsSinceEpoch}';

    final entry = CustomFrequencyEntry(
      id: id,
      name: name,
      frequencyHz: freq,
      durationMin: _durationMin,
      intensityPct: _intensity,
      useElectric: _useElectric,
      electricWaveform: _electricWaveform,
      useMagnetic: _useMagnetic,
      magneticWaveform: _magneticWaveform,
    );

    Navigator.pop(context, entry);
  }
}

class _TempAddButton extends StatefulWidget {
  final Future<void> Function() onAdd;
  const _TempAddButton({required this.onAdd});

  @override
  State<_TempAddButton> createState() => _TempAddButtonState();
}

class _TempAddButtonState extends State<_TempAddButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    if (_done) return;
    try {
      await widget.onAdd();
    } catch (_) {}

    if (!mounted) return;
    setState(() => _done = true);
    try {
      await _ctrl.forward();
      await _ctrl.reverse();
      await Future.delayed(const Duration(milliseconds: 900));
    } catch (_) {}
    if (!mounted) return;
    setState(() => _done = false);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      child: ScaleTransition(
        scale: Tween(
          begin: 1.0,
          end: 1.08,
        ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut)),
        child: CircleAvatar(
          radius: 16,
          backgroundColor: _done ? AppColors.accentGreen : AppColors.primary,
          child: Icon(
            _done ? Icons.check : Icons.add,
            color: Colors.white,
            size: 18,
          ),
        ),
      ),
    );
  }
}
