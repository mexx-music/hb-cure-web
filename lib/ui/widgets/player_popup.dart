import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'package:hbcure/services/player_service.dart';
import 'package:hbcure/services/program_catalog.dart';
import 'package:hbcure/services/cube_device_service.dart';
import 'package:hbcure/services/program_language_controller.dart';
import 'package:hbcure/services/custom_frequencies_store.dart';

import 'package:hbcure/ui/widgets/original_player_line.dart';

class PlayerPopup extends StatefulWidget {
  final PlayerService player;

  /// sync resolver: id -> display name
  final String Function(String programId) resolveTitle;

  const PlayerPopup({
    super.key,
    required this.player,
    required this.resolveTitle,
  });

  @override
  State<PlayerPopup> createState() => _PlayerPopupState();
}

class _PlayerPopupState extends State<PlayerPopup> {
  // ---- Visual fill: fixed 50 seconds to full black (like original)
  static const Duration _tickDur = Duration(seconds: 1);
  static const int _fillSeconds = 50;

  Timer? _tick;
  int _fillIndex = 0; // 0..49

  // ---- decoded JSON root (ONLY for fallback title search)
  dynamic _decodedRoot;

  // ---- slug -> keys (uuid/internalId) from assets/programs.json
  final Map<String, ({String? uuid, int? internalId})> _slugKeys = {};
  bool _slugKeysLoaded = false;
  bool _slugKeysLoading = false;

  // ---- custom_<id> -> Hz cache
  final Map<String, double> _customHzById = {};
  bool _customLoading = false;
  bool _customLoaded = false;

  // ---- frequency cache (prevents jumping)
  String? _cachedProgramId;
  List<num> _cachedFreqs = const <num>[];

  // ---- detect queue changes
  int _lastQueueHash = 0;

  // ---- catalog load state
  bool _catalogLoaded = false;
  bool _catalogLoading = false;

  // ---- 50s window rotation (line refresh every cycle)
  int _cycleNo = 0;
  static const int _cycleWindowSize = 240;
  List<num> _cycleFreqs = const <num>[];

  @override
  void initState() {
    super.initState();

    // fire-and-forget background loads
    ProgramCatalog.instance.ensureLoaded();
    _loadDecodedFallback();
    _loadSlugKeysFromProgramsJson();
    _loadCustomFreqs();

    _tick = Timer.periodic(_tickDur, (_) {
      if (!mounted) return;
      if (!widget.player.state.isPlaying) return;

      setState(() {
        if (_fillIndex < (_fillSeconds - 1)) {
          _fillIndex += 1;
        } else {
          _fillIndex = 0;
          _cycleNo += 1;
          _rebuildCycleCurve();
        }
      });
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  // ----------------------------
  // Loaders
  // ----------------------------

  Future<void> _loadDecodedFallback() async {
    try {
      final raw = await rootBundle.loadString('assets/programs/Programs_decoded_full.json');
      final decoded = jsonDecode(raw);
      if (!mounted) return;
      setState(() {
        _decodedRoot = decoded;
        _invalidateSeriesCache();
      });
    } catch (_) {
      // optional
    }
  }

  Future<void> _loadCustomFreqs() async {
    if (_customLoading) return;
    _customLoading = true;
    try {
      final all = await CustomFrequenciesStore.instance.loadAll();
      _customHzById.clear();
      for (final e in all) {
        _customHzById[e.id] = e.frequencyHz;
      }
      if (!mounted) return;
      setState(() {
        _customLoaded = true;
        _customLoading = false;
        _invalidateSeriesCache();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _customLoaded = true;
        _customLoading = false;
      });
    }
  }

  Future<void> _loadSlugKeysFromProgramsJson() async {
    if (_slugKeysLoaded || _slugKeysLoading) return;
    _slugKeysLoading = true;

    try {
      final raw = await rootBundle.loadString('assets/programs.json');
      final root = jsonDecode(raw);

      _slugKeys.clear();
      _walkProgramsJson(root, (programMap) {
        if (programMap is! Map) return;

        final slug = _pickString(programMap, const ['id', 'Id', 'slug', 'programId']);
        if (slug == null || slug.isEmpty) return;

        final uuid = _pickString(programMap, const [
          'uuid',
          'programUuid',
          'ProgramUUID',
          'ProgramUuid',
          'programUUID',
        ]);

        final internalId = _pickInt(programMap, const [
          'internalId',
          'internalID',
          'InternalID',
          'internal_id',
        ]);

        if (uuid != null || internalId != null) {
          _slugKeys[slug] = (uuid: uuid, internalId: internalId);
        }
      });

      if (!mounted) return;
      setState(() {
        _slugKeysLoaded = true;
        _slugKeysLoading = false;
        _invalidateSeriesCache();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _slugKeysLoaded = true; // stop retry loops
        _slugKeysLoading = false;
      });
    }
  }

  void _walkProgramsJson(dynamic node, void Function(dynamic programMap) onProgram) {
    if (node is Map) {
      if (node.containsKey('id') || node.containsKey('programId') || node.containsKey('slug')) {
        onProgram(node);
      }
      for (final v in node.values) {
        _walkProgramsJson(v, onProgram);
      }
    } else if (node is List) {
      for (final e in node) {
        _walkProgramsJson(e, onProgram);
      }
    }
  }

  String? _pickString(Map m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v is String) {
        final s = v.trim();
        if (s.isNotEmpty) return s;
      }
    }
    return null;
  }

  int? _pickInt(Map m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) {
        final n = int.tryParse(v.trim());
        if (n != null) return n;
      }
    }
    return null;
  }

  // ----------------------------
  // Helpers
  // ----------------------------

  void _invalidateSeriesCache() {
    _cachedProgramId = null;
    _cachedFreqs = const <num>[];
    _cycleFreqs = const <num>[];
    _fillIndex = 0;
    _cycleNo = 0;
  }

  // Two-mode normalization:
  // - keysId must match EXACT ids in assets/programs.json (incl. legacy typos like "energey")
  // - uiId may be "beautified" for title/localizer
  String? _normalizeProgramId(String? raw, {bool fixEnergyTypo = true}) {
    if (raw == null) return null;
    final s = raw.trim();
    if (s.isEmpty) return null;

    // normalize colon forms like "uuid:..."
    final cleaned = s.contains(':') ? s.split(':').last.trim() : s;

    if (!fixEnergyTypo) return cleaned;
    return cleaned.replaceAll('energey', 'energy');
  }

  bool _looksLikeUuid(String s) {
    return RegExp(r'^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$').hasMatch(s);
  }

  int? _extractTrailingInt(String id) {
    final m = RegExp(r'(\d+)$').firstMatch(id);
    if (m == null) return null;
    return int.tryParse(m.group(1)!);
  }

  String _normTitle(String s) => s
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\u00AD]'), '')
      .replaceAll(RegExp(r'[^a-z0-9äöüß ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  List<num> _freqsFromDecodedByTitle(dynamic decodedRoot, String title) {
    if (decodedRoot is! List) return const <num>[];
    final nt = _normTitle(title);
    if (nt.isEmpty) return const <num>[];

    for (final rec in decodedRoot) {
      if (rec is! Map) continue;

      final dynTitle = rec['title'] ?? rec['Title'] ?? rec['programTitle'];
      String? de;
      String? en;

      if (dynTitle is Map) {
        final a = dynTitle['de'] ?? dynTitle['DE'];
        final b = dynTitle['en'] ?? dynTitle['EN'];
        if (a is String) de = a;
        if (b is String) en = b;
      } else if (dynTitle is String) {
        de = dynTitle;
        en = dynTitle;
      }

      final nde = _normTitle(de ?? '');
      final nen = _normTitle(en ?? '');

      if (nde.isEmpty && nen.isEmpty) continue;

      final match = nde == nt ||
          nen == nt ||
          (nde.isNotEmpty && (nde.contains(nt) || nt.contains(nde))) ||
          (nen.isNotEmpty && (nen.contains(nt) || nt.contains(nen)));

      if (!match) continue;

      final f = rec['Frequencies'] ?? rec['frequencies'] ?? rec['FREQUENCIES'];
      if (f is List) {
        final out = <num>[];
        for (final e in f) {
          if (e is num && e.isFinite) out.add(e);
          if (e is String) {
            final v = num.tryParse(e.trim());
            if (v != null && v.isFinite) out.add(v);
          }
        }
        return out;
      }
      return const <num>[];
    }

    return const <num>[];
  }

  // Extract frequencies from:
  // - typed catalog entry: rec.steps[*].frequencyHz
  // - map catalog entry: steps list or Frequencies list
  List<num> _extractFrequenciesFromRec(dynamic rec) {
    if (rec == null) return const <num>[];

    // typed entry
    try {
      final dynamic steps = (rec as dynamic).steps;
      if (steps is List) {
        final out = <num>[];
        for (final st in steps) {
          try {
            final v = (st as dynamic).frequencyHz;
            if (v is num && v.isFinite) out.add(v);
          } catch (_) {}
        }
        if (out.isNotEmpty) return out;
      }
    } catch (_) {
      // fall through
    }

    if (rec is Map) {
      // steps array inside map
      final stepsVal = rec['steps'] ?? rec['Steps'];
      if (stepsVal is List) {
        final out = <num>[];
        for (final st in stepsVal) {
          if (st is Map) {
            final v = st['frequencyHz'] ?? st['freqHz'] ?? st['frequency'] ?? st['freq'];
            if (v is num && v.isFinite) out.add(v);
            if (v is String) {
              final n = num.tryParse(v.trim());
              if (n != null && n.isFinite) out.add(n);
            }
          } else {
            try {
              final v = (st as dynamic).frequencyHz;
              if (v is num && v.isFinite) out.add(v);
            } catch (_) {}
          }
        }
        if (out.isNotEmpty) return out;
      }

      // frequencies array inside map
      dynamic freqs = rec['Frequencies'] ?? rec['frequencies'] ?? rec['FREQUENCIES'];
      if (freqs == null && rec['data'] is Map) {
        final m = rec['data'] as Map;
        freqs = m['Frequencies'] ?? m['frequencies'];
      }
      if (freqs is List) {
        final out = <num>[];
        for (final e in freqs) {
          if (e is num && e.isFinite) out.add(e);
          if (e is String) {
            final v = num.tryParse(e.trim());
            if (v != null && v.isFinite) out.add(v);
          }
        }
        if (out.isNotEmpty) return out;
      }
    }

    return const <num>[];
  }

  List<num> _freqsForProgramId(String programId) {
    // Custom: always return real stored Hz
    if (programId.startsWith('custom_')) {
      final hz = _customHzById[programId];
      if (hz != null && hz.isFinite) return <num>[hz];

      // if not loaded yet, trigger load once
      if (!_customLoaded && !_customLoading) {
        _loadCustomFreqs();
      }
      return const <num>[];
    }

    if (!_catalogLoaded) return const <num>[];

    // 1) direct uuid in id string
    if (_looksLikeUuid(programId)) {
      try {
        final rec = ProgramCatalog.instance.byUuid(programId);
        final f = _extractFrequenciesFromRec(rec);
        if (f.isNotEmpty) return f;
      } catch (_) {}
    }

    // 2) slug keys (assets/programs.json)
    final keys = _slugKeys[programId];
    if (keys != null) {
      final uuid = keys.uuid;
      final internalId = keys.internalId;

      if (uuid != null) {
        try {
          final rec = ProgramCatalog.instance.byUuid(uuid);
          final f = _extractFrequenciesFromRec(rec);
          if (f.isNotEmpty) return f;
        } catch (_) {}
      }

      if (internalId != null) {
        try {
          final rec = ProgramCatalog.instance.byInternalId(internalId);
          final f = _extractFrequenciesFromRec(rec);
          if (f.isNotEmpty) return f;
        } catch (_) {}
      }
    }

    // 3) trailing internalId like "..._21807"
    final trailing = _extractTrailingInt(programId);
    if (trailing != null && trailing >= 1000) {
      try {
        final rec = ProgramCatalog.instance.byInternalId(trailing);
        final f = _extractFrequenciesFromRec(rec);
        if (f.isNotEmpty) return f;
      } catch (_) {}
    }

    // 4) same fallbacks as sendProgram()
    try {
      final rec = ProgramCatalog.instance.byUuid(programId);
      final f = _extractFrequenciesFromRec(rec);
      if (f.isNotEmpty) return f;
    } catch (_) {}

    final asInt = int.tryParse(programId);
    if (asInt != null) {
      try {
        final rec = ProgramCatalog.instance.byInternalId(asInt);
        final f = _extractFrequenciesFromRec(rec);
        if (f.isNotEmpty) return f;
      } catch (_) {}
    }

    // 5) decoded title fallback (optional)
    final title = widget.resolveTitle(programId);
    final byTitle = (_decodedRoot != null) ? _freqsFromDecodedByTitle(_decodedRoot, title) : const <num>[];
    if (byTitle.isNotEmpty) return byTitle;

    return const <num>[];
  }

  void _ensureCachedSeries(String? currentId) {
    if (currentId == null || currentId.isEmpty) {
      _cachedProgramId = null;
      _cachedFreqs = const <num>[];
      _cycleFreqs = const <num>[];
      return;
    }
    if (_cachedProgramId == currentId) return;

    _cachedProgramId = currentId;

    var series = _freqsForProgramId(currentId);
    series = series.where((v) => v is num && (v as num).isFinite).toList(growable: false);

    // ensure something drawable
    if (series.length == 1) {
      series = List<num>.filled(_cycleWindowSize, series.first);
    } else if (series.length == 2) {
      series = List<num>.generate(_cycleWindowSize, (i) => series[i % 2]);
    }

    _cachedFreqs = series.isNotEmpty ? series : const <num>[100, 100, 100, 100, 100];

    _fillIndex = 0;
    _cycleNo = 0;
    _rebuildCycleCurve();
  }

  void _rebuildCycleCurve() {
    final base = _cachedFreqs;
    if (base.isEmpty) {
      _cycleFreqs = const <num>[];
      return;
    }

    final seed = (_cachedProgramId ?? '').hashCode.abs();
    final stride = (37 + (seed % 200)).clamp(37, 236);
    final start = (_cycleNo * stride) % base.length;

    final int take = base.length < _cycleWindowSize ? base.length : _cycleWindowSize;

    final out = <num>[];
    for (int i = 0; i < take; i++) {
      out.add(base[(start + i) % base.length]);
    }
    _cycleFreqs = out;
  }

  void _resetCachesOnQueueChange(PlayerState st) {
    final newHash = Object.hashAll(st.queueIds);
    if (newHash == _lastQueueHash) return;

    _lastQueueHash = newHash;
    _invalidateSeriesCache();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context).size;
    final maxHeight = mq.height * 0.85;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 520, maxHeight: maxHeight),
        child: Material(
          elevation: 12,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: AnimatedBuilder(
            animation: widget.player,
            builder: (context, _) {
              final st = widget.player.state;

              _resetCachesOnQueueChange(st);

              if (!_slugKeysLoaded && !_slugKeysLoading) {
                _loadSlugKeysFromProgramsJson();
              }

              // Ensure ProgramCatalog is loaded once from the popup (safety)
              if (!_catalogLoaded && !_catalogLoading) {
                _catalogLoading = true;
                ProgramCatalog.instance.ensureLoaded().then((_) {
                  if (!mounted) return;
                  setState(() {
                    _catalogLoaded = true;
                    _catalogLoading = false;
                    _cachedProgramId = null;
                    _cachedFreqs = const <num>[];
                  });
                }).catchError((_) {
                  if (!mounted) return;
                  setState(() => _catalogLoading = false);
                });
              }

              // Queue-aware raw id
              String? rawId;
              if (st.queueIds.isNotEmpty &&
                  st.currentIndex >= 0 &&
                  st.currentIndex < st.queueIds.length) {
                rawId = st.queueIds[st.currentIndex];
              } else {
                rawId = st.currentProgramId;
              }

              // keysId must match EXACT ids in assets/programs.json (incl legacy typos)
              final keysId = _normalizeProgramId(rawId, fixEnergyTypo: false);
              // uiId can be prettified for title/localizer
              final uiId = _normalizeProgramId(rawId, fixEnergyTypo: true);

              if (kDebugMode) {
                // keep this one-liner while stabilizing; remove later if you want
                debugPrint('POPUP rawId=$rawId keysId=$keysId uiId=$uiId');
              }

              // Frequencies: always resolve using keysId
              _ensureCachedSeries(keysId);

              // Title: prefer uiId, fallback to keysId
              final titleId = uiId ?? keysId;
              final isDe = ProgramLangController.instance.lang == ProgramLang.de;

              String _friendlyTitle(String? programId) {
                if (programId == null) return isDe ? 'Playlist leer' : 'Playlist empty';

                // First try the provided resolver (may be populated from main shell)
                try {
                  final resolved = widget.resolveTitle(programId);
                  if (resolved.isNotEmpty && resolved != programId) return resolved;
                } catch (_) {}

                // Try to resolve via ProgramCatalog using slug keys / uuid / internalId
                final baseId = programId.contains('__slot_') ? programId.split('__slot_').first : programId;

                // 1) try slugKeys map
                try {
                  final keys = _slugKeys[baseId];
                  if (keys != null) {
                    if (keys.uuid != null) {
                      final rec = ProgramCatalog.instance.byUuid(keys.uuid!);
                      if (rec != null) return ProgramCatalog.instance.name(rec, lang: isDe ? 'DE' : 'EN');
                    }
                    if (keys.internalId != null) {
                      final rec = ProgramCatalog.instance.byInternalId(keys.internalId!);
                      if (rec != null) return ProgramCatalog.instance.name(rec, lang: isDe ? 'DE' : 'EN');
                    }
                  }
                } catch (_) {}

                // 2) try trailing internal id
                try {
                  final trailing = _extractTrailingInt(baseId);
                  if (trailing != null) {
                    final rec = ProgramCatalog.instance.byInternalId(trailing);
                    if (rec != null) return ProgramCatalog.instance.name(rec, lang: isDe ? 'DE' : 'EN');
                  }
                } catch (_) {}

                // 3) try direct uuid
                try {
                  if (baseId.isNotEmpty && _looksLikeUuid(baseId)) {
                    final rec = ProgramCatalog.instance.byUuid(baseId);
                    if (rec != null) return ProgramCatalog.instance.name(rec, lang: isDe ? 'DE' : 'EN');
                  }
                } catch (_) {}

                // fallback: return the original id (last resort)
                return programId;
              }

              final title = _friendlyTitle(titleId);

              final bool isRunning = st.isPlaying;
              final double visualProgress =
              isRunning ? (_fillIndex / (_fillSeconds - 1)).clamp(0.0, 1.0) : 0.0;

              final bool uploading = widget.player.isUploading;

              // --- Segment + Gesamtzeit (UI-only) ---
              final queue = st.queueIds;
              final idx = st.currentIndex;

              // st.total and st.remaining are now the MERGED totals.
              // Compute segment-level remaining for the current program.
              Duration cumulativeBefore = Duration.zero;
              Duration currentSegDur = Duration.zero;
              for (int i = 0; i < queue.length; i++) {
                final m = widget.player.settingsFor(queue[i]).durationMinutes;
                final d = Duration(minutes: m);
                if (i < idx) {
                  cumulativeBefore += d;
                } else if (i == idx) {
                  currentSegDur = d;
                }
              }
              final elapsed = st.total - st.remaining;
              final segElapsed = elapsed - cumulativeBefore;
              final rawSegRem = currentSegDur - segElapsed;
              final segRemaining = rawSegRem < Duration.zero ? Duration.zero : (rawSegRem > currentSegDur ? currentSegDur : rawSegRem);

              // [PLAYLIST_TIME] diagnostic: popup time calculation
              debugPrint('[PLAYLIST_TIME] POPUP idx=$idx queueLen=${queue.length} st.total=${st.total} st.remaining=${st.remaining} segRemaining=$segRemaining currentSegDur=$currentSegDur');

              String fmt(Duration d) {
                final s = d.inSeconds.clamp(0, 24 * 3600);
                if (s >= 3600) {
                  final hh = (s ~/ 3600).toString();
                  final mm = ((s % 3600) ~/ 60).toString().padLeft(2, '0');
                  final ss = (s % 60).toString().padLeft(2, '0');
                  return '$hh:$mm:$ss';
                }
                final mm = (s ~/ 60).toString().padLeft(2, '0');
                final ss = (s % 60).toString().padLeft(2, '0');
                return '$mm:$ss';
              }

              return SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        switchInCurve: Curves.easeInOut,
                        switchOutCurve: Curves.easeInOut,
                        transitionBuilder: (child, animation) =>
                            FadeTransition(opacity: animation, child: child),
                        child: Center(
                          key: ValueKey(title),
                          child: Text(
                            title,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),

                      if (uploading) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: const [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Programme werden hochgeladen…',
                                style: TextStyle(fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const LinearProgressIndicator(),
                        const SizedBox(height: 12),
                      ] else ...[
                        const SizedBox(height: 12),
                      ],

                      OriginalPlayerLine(
                        progress: visualProgress,
                        values: _cycleFreqs.isNotEmpty ? _cycleFreqs : _cachedFreqs,
                        height: 120,
                      ),

                      const SizedBox(height: 12),

                      // Controls: Stop (Cube) only
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            icon: const Icon(Icons.stop),
                            label: const Text('Stopp'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () async {
                              // 1. Stop local player/timer immediately (no BLE required)
                              try {
                                widget.player.stop();
                              } catch (_) {}

                              if (mounted) {
                                setState(() {
                                  _fillIndex = 0;
                                  _cycleNo = 0;
                                });
                              }

                              // 2. Also send stop to Cube if connected (best-effort)
                              try {
                                await CubeDeviceService.instance.stopProgram();
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Gerät-Stop fehlgeschlagen: ${e.toString()}')),
                                  );
                                }
                                // local stop already done above – no early return needed
                              }
                            },
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // ---- Playlist progress list ----
                      if (queue.isNotEmpty) ...[
                        const Divider(height: 1),
                        const SizedBox(height: 8),
                        ...List.generate(queue.length, (i) {
                          final itemId = queue[i];
                          final itemDurMin = widget.player.settingsFor(itemId).durationMinutes;
                          final itemDur = Duration(minutes: itemDurMin);
                          // Resolve playlist row title the same way as the main title above:
                          final itemKeysId = _normalizeProgramId(itemId, fixEnergyTypo: false);
                          final itemUiId = _normalizeProgramId(itemId, fixEnergyTypo: true);
                          final itemTitleId = itemUiId ?? itemKeysId;
                          final itemTitle = _friendlyTitle(itemTitleId);

                          // Determine state: completed / current / upcoming
                          final bool isCompleted = i < idx;
                          final bool isCurrent = i == idx;

                          double barFill;
                          Duration displayRemaining;

                          if (isCompleted) {
                            barFill = 1.0;
                            displayRemaining = Duration.zero;
                          } else if (isCurrent) {
                            barFill = itemDur.inSeconds > 0
                                ? (1.0 - segRemaining.inSeconds / itemDur.inSeconds).clamp(0.0, 1.0)
                                : 0.0;
                            displayRemaining = segRemaining;
                          } else {
                            barFill = 0.0;
                            displayRemaining = itemDur;
                          }

                          final Color barColor = isCurrent
                              ? Theme.of(context).colorScheme.primary
                              : isCompleted
                                  ? Theme.of(context).colorScheme.primary.withOpacity(0.45)
                                  : Colors.grey.withOpacity(0.25);

                          final Color textColor = isCurrent
                              ? Theme.of(context).colorScheme.onSurface
                              : isCompleted
                                  ? Theme.of(context).colorScheme.onSurface.withOpacity(0.55)
                                  : Theme.of(context).colorScheme.onSurface.withOpacity(0.4);

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    // Index dot
                                    Container(
                                      width: 22,
                                      height: 22,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: isCurrent
                                            ? Theme.of(context).colorScheme.primary
                                            : isCompleted
                                                ? Theme.of(context).colorScheme.primary.withOpacity(0.35)
                                                : Colors.grey.withOpacity(0.22),
                                      ),
                                      child: Center(
                                        child: isCompleted
                                            ? Icon(Icons.check,
                                                size: 13,
                                                color: isCurrent
                                                    ? Theme.of(context).colorScheme.onPrimary
                                                    : Theme.of(context).colorScheme.onSurface.withOpacity(0.6))
                                            : Text(
                                                '${i + 1}',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: isCurrent
                                                      ? Theme.of(context).colorScheme.onPrimary
                                                      : Theme.of(context).colorScheme.onSurface.withOpacity(0.55),
                                                ),
                                              ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // Title
                                    Expanded(
                                      child: Text(
                                        itemTitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                              color: textColor,
                                              fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                                            ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // Time text
                                    Text(
                                      isCompleted
                                          ? fmt(itemDur)
                                          : isCurrent
                                              ? '${fmt(displayRemaining)} / ${fmt(itemDur)}'
                                              : fmt(itemDur),
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            color: textColor,
                                            fontFeatures: const [ui.FontFeature.tabularFigures()],
                                          ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                // Progress bar
                                Padding(
                                  padding: const EdgeInsets.only(left: 30),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: barFill,
                                      minHeight: 5,
                                      backgroundColor: Colors.grey.withOpacity(0.15),
                                      valueColor: AlwaysStoppedAnimation<Color>(barColor),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                        const SizedBox(height: 8),
                        const Divider(height: 1),
                      ],

                      const SizedBox(height: 8),

                      // Total timer (merged)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(isDe ? 'Gesamt' : 'Total',
                              style: Theme.of(context).textTheme.bodyMedium),
                          Text(
                            '${fmt(st.remaining)} / ${fmt(st.total)}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      Align(
                        alignment: Alignment.centerRight,
                        child: ElevatedButton(
                          onPressed: () {
                            if (Navigator.of(context).canPop()) {
                              Navigator.of(context).pop();
                            }
                          },
                          child: const Text('Close'),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

