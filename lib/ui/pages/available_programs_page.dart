import 'package:flutter/material.dart';
import 'package:hbcure/data/program_repository.dart';
import 'package:hbcure/models/program_category.dart';
import 'package:hbcure/ui/pages/categories_page.dart';
import '../widgets/gradient_background.dart';
import '../theme/app_colors.dart';
import 'package:hbcure/i18n/program_name_localizer.dart';
import 'package:hbcure/services/program_language_controller.dart';
import 'package:hbcure/services/app_memory.dart';
import 'package:hbcure/core/program_mode.dart';
import 'package:hbcure/models/program_item.dart';
import 'package:hbcure/services/cure_device_unlock_service.dart';
import 'package:hbcure/ui/pages/program_detail_page.dart';
import 'package:hbcure/services/my_programs_service.dart';

class AvailableProgramsPage extends StatefulWidget {
  const AvailableProgramsPage({super.key});

  @override
  State<AvailableProgramsPage> createState() => _AvailableProgramsPageState();
}

class _AvailableProgramsPageState extends State<AvailableProgramsPage> {
  final ProgramRepository _repo = ProgramRepository();
  List<ProgramCategory> _categories = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cats = await _repo.loadCategories();
    setState(() {
      _categories = cats;
      _loading = false;
    });
  }

  // Single source of truth for top-folder color:
  // Use the JSON field if present; otherwise infer from known IDs.
  String? _inferColor(ProgramCategory cc) {
    final ck = (cc.color ?? '').trim().toLowerCase();
    if (ck == 'yellow' || ck == 'red') return ck;

    const yellowIds = {
      'seven_chakras',
      'therapeutic',
      'detoxification',
      'post_operation',
    };
    const redIds = {
      'homeopathic_medicine_dosing_frequency',
      'psychiatry',
    };

    if (yellowIds.contains(cc.id)) return 'yellow';
    if (redIds.contains(cc.id)) return 'red';
    return null; // means "green/default"
  }

  Color _markerFromColorKey(String? key) {
    final k = (key ?? '').trim().toLowerCase();
    if (k == 'yellow') return AppColors.yellow;
    if (k == 'red') return AppColors.accentRed;
    return AppColors.primaryMuted;
  }

  void _openSearch() async {
    // --- helpers (lokal, minimal-invasiv) ---
    String _norm(String s) {
      final x = s.toLowerCase().trim();
      return x
          .replaceAll('ä', 'a')
          .replaceAll('ö', 'o')
          .replaceAll('ü', 'u')
          .replaceAll('ß', 'ss');
    }

    List<ProgramItem> _collectPrograms(List<ProgramCategory> cats) {
      final out = <ProgramItem>[];
      final seen = <String>{}; // dedupe by program.id

      void addAll(List<ProgramItem>? items) {
        if (items == null) return;
        for (final p in items) {
          if (seen.add(p.id)) out.add(p);
        }
      }

      for (final c in cats) {
        addAll(c.programs);
        for (final s in (c.subcategories ?? const [])) {
          addAll(s.programs);
        }
      }
      return out;
    }

    // flatten programs from loaded categories; if not loaded yet, load from repo
    List<ProgramItem> programs;
    if (_categories.isNotEmpty) {
      programs = _collectPrograms(_categories);
    } else {
      final cats = await _repo.loadCategories();
      programs = _collectPrograms(cats);
    }

    final controller = TextEditingController();
    String query = ''; // <-- MUSS ausserhalb vom StatefulBuilder liegen

    // local i18n helpers for the search action sheet
    bool isDe() => ProgramLangController.instance.lang == ProgramLang.de;
    String t(String de, String en) => isDe() ? de : en;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return SafeArea(
          child: FractionallySizedBox(
            heightFactor: 0.85,
            child: Material(
              color: AppColors.cardBackground,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: StatefulBuilder(
                builder: (cctx, setModalState) {
                  List<ProgramItem> filtered() {
                    final langCode = (ProgramLangController.instance.lang == ProgramLang.de) ? 'de' : 'en';
                    final q = _norm(query);
                    if (q.isEmpty) return programs;

                    return programs.where((p) {
                      final label = ProgramNameLocalizer.instance
                          .displayName(keyEn: p.name, langCode: langCode);

                      final hay = _norm('$label ${p.name} ${p.id}');
                      return hay.contains(q);
                    }).toList(growable: false);
                  }

                  final list = filtered();

                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.of(ctx).viewInsets.bottom,
                    ),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: controller,
                                  autofocus: true,
                                  decoration: const InputDecoration(
                                    hintText: 'Search programs',
                                    border: OutlineInputBorder(),
                                  ),
                                  onChanged: (v) {
                                    query = v;
                                    setModalState(() {});
                                  },
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  controller.clear();
                                  query = '';
                                  setModalState(() {});
                                },
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: list.isEmpty
                              ? const Center(child: Text('No results'))
                              : ListView.separated(
                                  itemCount: list.length,
                                  separatorBuilder: (_, __) => const Divider(height: 1),
                                  itemBuilder: (ctx2, idx) {
                                    final p = list[idx];
                                    final langCode = (ProgramLangController.instance.lang == ProgramLang.de) ? 'de' : 'en';
                                    final label = ProgramNameLocalizer.instance.displayName(
                                      keyEn: p.name,
                                      langCode: langCode,
                                    );

                                    return ListTile(
                                      title: Text(
                                        label,
                                        style: const TextStyle(color: AppColors.textPrimary),
                                      ),
                                      subtitle: null,
                                      onTap: () async {
                                        // show action sheet while keeping the search sheet (ctx) open until action chosen
                                        await showModalBottomSheet<void>(
                                          context: context,
                                          backgroundColor: Colors.transparent,
                                          builder: (actionCtx) {
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
                                                      leading: const Icon(Icons.play_arrow, color: AppColors.textPrimary),
                                                      title: Text(t('Jetzt abspielen', 'Play now'), style: const TextStyle(color: AppColors.textPrimary)),
                                                      onTap: () {
                                                        Navigator.of(actionCtx).pop(); // close actions
                                                        Navigator.of(ctx).pop(); // close search sheet
                                                        final devId = CureDeviceUnlockService.instance.nativeConnectedDeviceId ?? '';
                                                        Navigator.push(
                                                          context,
                                                          MaterialPageRoute(
                                                            builder: (_) => ProgramDetailPage(program: p, deviceId: devId),
                                                          ),
                                                        );
                                                      },
                                                    ),
                                                    ListTile(
                                                      leading: const Icon(Icons.favorite_border, color: AppColors.textPrimary),
                                                      title: Text(t('Zu My Programs hinzufügen', 'Add to My Programs'), style: const TextStyle(color: AppColors.textPrimary)),
                                                      onTap: () async {
                                                        final svc = MyProgramsService();
                                                        await svc.add(p.id);
                                                        if (!context.mounted) return;
                                                        Navigator.of(actionCtx).pop(); // close actions
                                                        ScaffoldMessenger.of(context).showSnackBar(
                                                          SnackBar(content: Text(t('Hinzugefügt zu My Programs', 'Added to My Programs'))),
                                                        );
                                                      },
                                                    ),
                                                    ListTile(
                                                      leading: const Icon(Icons.info_outline, color: AppColors.textPrimary),
                                                      title: Text(t('Details öffnen', 'Open details'), style: const TextStyle(color: AppColors.textPrimary)),
                                                      onTap: () {
                                                        Navigator.of(actionCtx).pop(); // close actions
                                                        Navigator.of(ctx).pop(); // close search sheet
                                                        final devId = CureDeviceUnlockService.instance.nativeConnectedDeviceId ?? '';
                                                        Navigator.push(
                                                          context,
                                                          MaterialPageRoute(
                                                            builder: (_) => ProgramDetailPage(program: p, deviceId: devId),
                                                          ),
                                                        );
                                                      },
                                                    ),
                                                    const SizedBox(height: 8),
                                                  ],
                                                ),
                                              ),
                                            );
                                          },
                                        );
                                      },
                                    );
                                  },
                                ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final langCode =
    (ProgramLangController.instance.lang == ProgramLang.de) ? 'de' : 'en';

    // Current mode for filtering visible categories
    final mode = AppMemory.instance.programMode;

    // IMPORTANT: Filter by inferred color (not raw c.color), otherwise yellow/red with missing
    // JSON color would be treated as green and behave inconsistently.
    final visibleCategories = _categories.where((cat) {
      final color = _inferColor(cat) ?? 'green';
      if (mode == ProgramMode.beginner) return color == 'green';
      if (mode == ProgramMode.advanced) return color == 'green' || color == 'yellow';
      return true; // expert
    }).toList();

    return GradientBackground(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
        child: ListView(
          padding: const EdgeInsets.only(bottom: 12.0),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  ProgramNameLocalizer.instance.displayName(
                    keyEn: 'Available Programs',
                    langCode: langCode,
                  ),
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(color: AppColors.textPrimary, fontSize: 18),
                ),
                IconButton(
                  icon: const Icon(Icons.search, color: AppColors.textPrimary),
                  onPressed: () => _openSearch(),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (_loading) ...[
              const SizedBox(height: 20),
              const Center(child: CircularProgressIndicator()),
            ] else ...[
              for (final c in visibleCategories)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6.0),
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: AppColors.cardBackground,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.borderSubtle),
                      ),
                      child: Builder(builder: (ctx) {
                        // Infer and fix color so the next page can inherit yellow/red correctly.
                        final inferred = _inferColor(c);
                        final markerColor = _markerFromColorKey(inferred);

                        debugPrint(
                          'CAT_COLOR id=${c.id} raw=${c.color} inferred=$inferred',
                        );

                        final fixedCategory = (inferred == null)
                            ? c
                            : ProgramCategory(
                          id: c.id,
                          title: c.title,
                          color: inferred,
                          programs: c.programs ?? const [],
                          subcategories: c.subcategories ?? const [],
                        );

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: markerColor,
                            child: const Icon(Icons.apps,
                                color: AppColors.textPrimary),
                          ),
                          title: Builder(builder: (_) {
                            // HOTFIX: special-case the known 'seven_chakras' top-folder id
                            final isDe = ProgramLangController.instance.lang ==
                                ProgramLang.de;
                            final id = fixedCategory.id;
                            final titleText = (id == 'seven_chakras')
                                ? (isDe
                                ? '7 Chakra Frequenzen'
                                : '7 Chakra Frequencies')
                                : ProgramNameLocalizer.instance.displayName(
                              keyEn: fixedCategory.title,
                              langCode: langCode,
                            );
                            return Text(
                              titleText,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            );
                          }),
                          trailing: const Icon(Icons.chevron_right,
                              color: AppColors.textSecondary),
                          onTap: () {
                            final progCount = (fixedCategory.programs?.length ?? 0);
                            final subCount =
                            (fixedCategory.subcategories?.length ?? 0);
                            final isEmpty = (progCount == 0 && subCount == 0);

                            final isYellow = (inferred == 'yellow');
                            final modeNow = AppMemory.instance.programMode;

                            debugPrint(
                              'TAP category id=${fixedCategory.id} title=${fixedCategory.title} '
                                  'programs=$progCount subcats=$subCount rawColor=${c.color} inferred=$inferred mode=$modeNow',
                            );

                            if (isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Diese Kategorie ist aktuell leer.')),
                              );
                              return;
                            }

                            if (modeNow == ProgramMode.beginner && isYellow) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Diese Kategorie erscheint erst im Standard-Modus.')),
                              );
                              return;
                            }

                            // Always open CategoriesPage. It shows programs (with +) and subcategories together.
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    CategoriesPage(category: fixedCategory),
                              ),
                            );
                          },
                        );
                      }),
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
