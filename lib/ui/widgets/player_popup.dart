import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'package:hbcure/services/player_service.dart';
import 'package:hbcure/services/program_catalog.dart';
import 'package:hbcure/services/cube_device_service.dart';
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
  // ---- Visual Fill (like original app): fixed 50 seconds to full black
  static const Duration _tickDur = Duration(seconds: 1);
  static const int _fillSeconds = 50; // 50s fill cycle

  Timer? _tick;
  int _fillIndex = 0; // 0..49

  // ---- decoded JSON root (ONLY for fallback title search; ProgramCatalog remains primary)
  dynamic _decodedRoot;

  // ---- slug -> keys map (built from assets/programs.json raw JSON)
  // slug -> (uuid/internalId)
  final Map<String, ({String? uuid, int? internalId})> _slugKeys = {};
  bool _slugKeysLoaded = false;
  bool _slugKeysLoading = false;

  // ---- Frequency cache (prevents jumping)
  String? _cachedProgramId;
  List<num> _cachedFreqs = const <num>[];

  // ---- detect queue changes (so My Programs updates propagate)
  int _lastQueueHash = 0;

  // ---- Cycle state for 50s window rotation (line refresh every cycle)
  int _cycleNo = 0;
  static const int _cycleWindowSize = 240;
  List<num> _cycleFreqs = const <num>[];

  @override
  void initState() {
    super.initState();

    // Ensure ProgramCatalog is loading in background (source of truth)
    ProgramCatalog.instance.ensureLoaded();

    // Load helpers in background
    _loadDecodedFallback(); // optional
    _loadSlugKeysFromProgramsJson(); // critical: slug -> (uuid/internalId)

    // timer for visual fill + curve rotation
    _tick = Timer.periodic(_tickDur, (_) {
      if (!mounted) return;
      final running = widget.player.state.isPlaying;
      if (!running) return;

      setState(() {
        if (_fillIndex < (_fillSeconds - 1)) {
          _fillIndex += 1;
        } else {
          // reset visual fill and rotate to next cycle curve
          _fillIndex = 0;
          _cycleNo += 1;
          _rebuildCycleCurve();
        }
      });
    });
  }

  Future<void> _loadDecodedFallback() async {
    try {
      final raw = await rootBundle.loadString(
        'assets/programs/Programs_decoded_full.json',
      );
      final decoded = jsonDecode(raw);
      if (!mounted) return;
      setState(() {
        _decodedRoot = decoded;
        // allow re-resolve
        _cachedProgramId = null;
        _cachedFreqs = const <num>[];
        _cycleNo = 0;
        _cycleFreqs = const <num>[];
        _fillIndex = 0;
      });
    } catch (_) {
      // ignore; fallback not mandatory
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

        // slug map now available -> force re-resolve
        _cachedProgramId = null;
        _cachedFreqs = const <num>[];
        _cycleNo = 0;
        _cycleFreqs = const <num>[];
        _fillIndex = 0;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _slugKeysLoaded = true; // stop retry loops
      });
    } finally {
      _slugKeysLoading = false;
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

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String _fmt(Duration d) {
    final s = d.inSeconds;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    return '${h}h ${m}m ${sec}s';
  }

  String? _normalizeProgramId(String? raw) {
    if (raw == null) return null;
    final s = raw.trim();
    if (s.isEmpty) return null;
    if (s.contains(':')) return s.split(':').last.trim();
    return s;
  }

  bool _looksLikeUuid(String s) {
    return RegExp(
      r'^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$',
    ).hasMatch(s);
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

      final match =
          nde == nt ||
              nen == nt ||
              (nde.isNotEmpty && (nde.contains(nt) || nt.contains(nde))) ||
              (nen.isNotEmpty && (nen.contains(nt) || nt.contains(nen)));

      if (!match) continue;

      final f = rec['Frequencies'] ?? rec['frequencies'] ?? rec['FREQUENCIES'];
      if (f is List) {
        final out = <num>[];
        for (final e in f) {
          if (e is num) out.add(e);
          if (e is String) {
            final v = num.tryParse(e.trim());
            if (v != null) out.add(v);
          }
        }
        return out;
      }
      return const <num>[];
    }
    return const <num>[];
  }

  List<num> _extractFrequenciesFromRec(dynamic rec) {
    if (rec is! Map) return const <num>[];

    dynamic freqs = rec['Frequencies'] ?? rec['frequencies'] ?? rec['FREQUENCIES'];
    if (freqs == null && rec['data'] is Map) {
      final m = rec['data'] as Map;
      freqs = m['Frequencies'] ?? m['frequencies'];
    }

    if (freqs is List) {
      final out = <num>[];
      for (final e in freqs) {
        if (e is num) out.add(e);
        if (e is String) {
          final v = num.tryParse(e.trim());
          if (v != null) out.add(v);
        }
      }
      return out;
    }
    return const <num>[];
  }

  List<num> _freqsForProgramId(String programId) {
    // 1) if already UUID
    if (_looksLikeUuid(programId)) {
      try {
        final rec = ProgramCatalog.instance.byUuid(programId);
        return _extractFrequenciesFromRec(rec);
      } catch (_) {}
    }

    // 2) try slug map
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

    // 3) trailing internalId
    final trailing = _extractTrailingInt(programId);
    if (trailing != null && trailing >= 1000) {
      try {
        final rec = ProgramCatalog.instance.byInternalId(trailing);
        final f = _extractFrequenciesFromRec(rec);
        if (f.isNotEmpty) return f;
      } catch (_) {}
    }

    // 4) optional decoded title fallback
    final title = widget.resolveTitle(programId);
    final byTitle = (_decodedRoot != null)
        ? _freqsFromDecodedByTitle(_decodedRoot, title)
        : const <num>[];
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
    final series = _freqsForProgramId(currentId);

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

    _cachedProgramId = null;
    _cachedFreqs = const <num>[];
    _cycleFreqs = const <num>[];
    _fillIndex = 0;
    _cycleNo = 0;
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

              final currentId = _normalizeProgramId(st.currentProgramId);
              _ensureCachedSeries(currentId);

              final title = currentId == null ? 'Playlist leer' : widget.resolveTitle(currentId);

              final bool isRunning = st.isPlaying;
              final double visualProgress = isRunning
                  ? (_fillIndex / (_fillSeconds - 1)).clamp(0.0, 1.0)
                  : 0.0;

              final bool uploading = widget.player.isUploading;

              return SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(title, style: Theme.of(context).textTheme.titleLarge),

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

                      // Controls: Stop (Cube) only (UI is display-only)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            icon: const Icon(Icons.stop),
                            label: const Text('Stop (Cube)'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () async {
                              try {
                                await CubeDeviceService.instance.stopProgram();
                              } catch (e) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Stop failed: ${e.toString()}')),
                                );
                                return;
                              }

                              // Stop UI timer and reset fill
                              try {
                                widget.player.stop();
                              } catch (_) {}
                              if (mounted) setState(() {
                                _fillIndex = 0;
                                _cycleNo = 0;
                              });
                            },
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Fortschritt', style: Theme.of(context).textTheme.bodyMedium),
                          Text(_fmt(st.remaining)),
                        ],
                      ),

                      const SizedBox(height: 12),

                      Align(
                        alignment: Alignment.centerRight,
                        child: ElevatedButton(
                          onPressed: () {
                            if (Navigator.of(context).canPop()) Navigator.of(context).pop();
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
