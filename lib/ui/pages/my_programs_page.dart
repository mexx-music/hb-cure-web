import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hbcure/services/cure_device_unlock_service.dart';

import '../../data/program_repository.dart';
import '../../models/program_item.dart';
import '../../services/my_programs_service.dart';
import '../widgets/gradient_background.dart';
import '../theme/app_colors.dart';
import 'program_detail_page.dart';
import '../../services/program_catalog.dart';

class MyProgramsPage extends StatefulWidget {
  const MyProgramsPage({super.key});

  @override
  State<MyProgramsPage> createState() => _MyProgramsPageState();
}

class _MyProgramsPageState extends State<MyProgramsPage> {
  final _service = MyProgramsService();
  final _repo = ProgramRepository();

  StreamSubscription<void>? _myProgramsSub;

  // Loading guard / queue flags
  bool _isLoading = false;
  bool _pendingReload = false;

  // Existing loading indicator and data
  bool _loading = true;
  List<ProgramItem> _programs = [];
  // name enrichment cache: programId -> display name (from asset catalog)
  final Map<String, String> _displayNameById = {};

  @override
  void initState() {
    super.initState();
    _loadPrograms();
    _myProgramsSub = _service.onChange.listen((_) {
      // schedule a reload; _loadPrograms itself will coalesce concurrent calls
      _loadPrograms();
    });
  }

  @override
  void dispose() {
    _myProgramsSub?.cancel();
    super.dispose();
  }

  Future<void> _loadPrograms() async {
    if (!mounted) return;
    if (_isLoading) {
      _pendingReload = true;
      return;
    }
    _isLoading = true;
    setState(() => _loading = true);
    try {
      final ids = await _service.loadIds();
      // load all categories and build id->ProgramItem map
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

      final programs = <ProgramItem>[];
      for (final id in ids) {
        final p = map[id];
        if (p != null) programs.add(p);
      }

      // ---- name enrichment from Programs_decoded_full.json (optional) ----
      try {
        await ProgramCatalog.instance.ensureLoaded();
        _displayNameById.clear();
        for (final program in programs) {
          final current = program.name.trim();
          final isPlaceholder = current.isEmpty || current == '-' || current.toLowerCase() == 'placeholder';
          if (!isPlaceholder) {
            _displayNameById[program.id] = program.name;
            continue;
          }
          final byUuid = ProgramCatalog.instance.byUuid(program.id);
          if (byUuid != null) {
            _displayNameById[program.id] = ProgramCatalog.instance.name(byUuid, lang: 'DE');
            continue;
          }
          final intId = int.tryParse(program.id);
          if (intId != null) {
            final byInt = ProgramCatalog.instance.byInternalId(intId);
            if (byInt != null) {
              _displayNameById[program.id] = ProgramCatalog.instance.name(byInt, lang: 'DE');
              continue;
            }
          }
          _displayNameById[program.id] = program.name;
        }
      } catch (_) {
        // Non-fatal: if program catalog missing or parse fails, ignore enrichment
      }
      // -------------------------------------------------------------------

      if (!mounted) return;
      setState(() {
        _programs = programs;
      });
    } finally {
      if (!mounted) return;
      _isLoading = false;
      setState(() => _loading = false);
      if (_pendingReload) {
        _pendingReload = false;
        // schedule a single reload after current microtask
        Future.microtask(() => _loadPrograms());
      }
    }
  }

  Future<void> _remove(String id) async {
    await _service.remove(id);
    // trigger load via subscription or directly ensure reload
    _loadPrograms();
  }

  @override
  Widget build(BuildContext context) {
    // No debug prints here in production; layout adjusted to nav geometry.

    // Build a single scrollable ListView that contains the header and the programs.
    return GradientBackground(
      child: Padding(
        // slightly reduced vertical padding to save height
        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
        child: ListView(
          // Keep a small gap at bottom to avoid ListView items touching the nav bar
          padding: EdgeInsets.only(bottom: 12.0),
          children: [
            // slightly smaller in-body header
            Text('My Programs', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AppColors.textPrimary, fontSize: 18)),
            const SizedBox(height: 6),
            if (_loading) ...[
              const SizedBox(height: 36),
              Center(child: CircularProgressIndicator(color: AppColors.primary)),
            ] else if (_programs.isEmpty) ...[
              const SizedBox(height: 36),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.favorite_border, size: 64, color: AppColors.navBarInactive),
                    SizedBox(height: 10),
                    Text('Keine gespeicherten Programme', style: TextStyle(color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ] else ...[
              const SizedBox(height: 4),
              // Render each program as before
              for (final program in _programs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6.0),
                  child: Material(
                    color: AppColors.cardBackground,
                    borderRadius: BorderRadius.circular(22),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(22),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => ProgramDetailPage(program: program, deviceId: CureDeviceUnlockService.instance.nativeConnectedDeviceId ?? '')),
                        );
                        await _loadPrograms();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                        child: Row(
                          children: [
                            Icon(Icons.play_arrow, color: AppColors.primary),
                            const SizedBox(width: 10),
                            Expanded(child: Text(_displayNameById[program.id] ?? program.name, style: TextStyle(color: AppColors.textPrimary))),
                            IconButton(
                              icon: Icon(Icons.delete, color: AppColors.textSecondary),
                              onPressed: () async => _remove(program.id),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
