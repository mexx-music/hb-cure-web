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
import 'package:hbcure/services/my_programs_service.dart';
import 'package:hbcure/l10n/gen/app_localizations.dart';

class AvailableProgramsPage extends StatefulWidget {
  const AvailableProgramsPage({super.key});

  @override
  State<AvailableProgramsPage> createState() => _AvailableProgramsPageState();
}

class _AvailableProgramsPageState extends State<AvailableProgramsPage> {
  final ProgramRepository _repo = ProgramRepository();
  List<ProgramCategory> _categories = [];
  bool _loading = true;
  late final VoidCallback _langListener;
  ProgramCategory? _selectedCategory;
  // Maintain a small stack of opened categories/subcategories so the back arrow
  // can navigate one level up instead of jumping back to the top overview.
  final List<ProgramCategory> _categoryStack = [];

  @override
  void initState() {
    super.initState();
    _langListener = () {
      if (mounted) _load();
    };
    ProgramLangController.instance.addListener(_langListener);
    _load();
  }

  @override
  void dispose() {
    ProgramLangController.instance.removeListener(_langListener);
    super.dispose();
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
    const redIds = {'homeopathic_medicine_dosing_frequency', 'psychiatry'};

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

    final l10n = AppLocalizations.of(context)!;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: FractionallySizedBox(
              heightFactor: 0.85,
              child: Material(
                color: AppColors.cardBackground,
                elevation: 8,
                shadowColor: Colors.black45,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(22)),
                ),
              child: StatefulBuilder(
                builder: (cctx, setModalState) {
                  List<ProgramItem> filtered() {
                    final langCode =
                        (ProgramLangController.instance.lang == ProgramLang.de)
                        ? 'de'
                        : 'en';
                    final q = _norm(query);
                    if (q.isEmpty) return programs;

                    return programs
                        .where((p) {
                          final label = ProgramNameLocalizer.instance
                              .displayName(keyEn: p.name, langCode: langCode);

                          final hay = _norm('$label ${p.name} ${p.id}');
                          return hay.contains(q);
                        })
                        .toList(growable: false);
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
                                  decoration: InputDecoration(
                                    hintText: l10n.searchPrograms,
                                    prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
                                    filled: true,
                                    fillColor: Colors.white12,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.all(Radius.circular(18)),
                                      borderSide: BorderSide.none,
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.all(Radius.circular(18)),
                                      borderSide: BorderSide.none,
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.all(Radius.circular(18)),
                                      borderSide: const BorderSide(color: Colors.white24, width: 1.5),
                                    ),
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
                              ? Center(child: Text(l10n.noResults))
                              : ListView.separated(
                                  itemCount: list.length,
                                  separatorBuilder: (_, __) =>
                                      const Divider(height: 1, indent: 20, endIndent: 20),
                                  itemBuilder: (ctx2, idx) {
                                    final p = list[idx];
                                    final langCode =
                                        (ProgramLangController.instance.lang ==
                                            ProgramLang.de)
                                        ? 'de'
                                        : 'en';
                                    final label = ProgramNameLocalizer.instance
                                        .displayName(
                                          keyEn: p.name,
                                          langCode: langCode,
                                        );

                                    return ListTile(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                                      splashColor: Colors.white12,
                                      title: Text(
                                        label,
                                        style: const TextStyle(
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                      subtitle: null,
                                      onTap: () async {
                                        final isDe = ProgramLangController.instance.lang == ProgramLang.de;
                                        final confirmed = await showDialog<bool>(
                                          context: context,
                                          builder: (dlgCtx) => AlertDialog(
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(16),
                                            ),
                                            backgroundColor: AppColors.cardBackground,
                                            title: Text(
                                              label,
                                              style: const TextStyle(color: AppColors.textPrimary),
                                            ),
                                            content: Text(
                                              isDe
                                                  ? 'Dieses Programm zu „Meine Programme" hinzufügen?'
                                                  : 'Add this program to "My Programs"?',
                                              style: const TextStyle(color: AppColors.textSecondary),
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.of(dlgCtx).pop(false),
                                                child: Text(isDe ? 'Abbrechen' : 'Cancel'),
                                              ),
                                              TextButton(
                                                onPressed: () => Navigator.of(dlgCtx).pop(true),
                                                child: Text(
                                                  isDe ? 'Hinzufügen' : 'Add',
                                                  style: TextStyle(
                                                    color: Theme.of(context).colorScheme.primary,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (confirmed != true) return;
                                        if (!context.mounted) return;
                                        await MyProgramsService().add(p.id);
                                        if (!context.mounted) return;
                                        Navigator.of(ctx).pop();
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
                                                    isDe
                                                        ? '$label wurde zu „Meine Programme" hinzugefügt'
                                                        : '$label added to "My Programs"',
                                                    style: const TextStyle(color: Colors.white),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
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
        ),
      );
      },
    );
  }

  Widget _buildCategoryView(ProgramCategory category) {
    final langCode = (ProgramLangController.instance.lang == ProgramLang.de)
        ? 'de'
        : 'en';

    return ValueListenableBuilder<ProgramMode>(
      valueListenable: AppMemory.instance.programModeNotifier,
      builder: (context, mode, _) {
        // ---------- Color handling (single source of truth) ----------
        final baseColor = AppColors.primaryMuted;

        Color markerFrom(String? color) {
          final c = (color ?? '').trim().toLowerCase();
          if (c == 'yellow') return AppColors.yellow;
          if (c == 'red') return AppColors.accentRed;
          return baseColor;
        }

        final categoryMarkerColor = markerFrom(category.color);

        // ---------- Filter visible subcategories ----------
        final visibleSubcategories = category.subcategories.where((sub) {
          if (sub.programs.isEmpty) return false;

          final subColor = (sub.color ?? category.color ?? '')
              .trim()
              .toLowerCase();
          final isYellowOrRed = (subColor == 'yellow' || subColor == 'red');

          if (mode == ProgramMode.beginner && isYellowOrRed) return false;
          return true;
        }).toList();

        return GradientBackground(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 20.0,
            ),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 12.0),
              children: [
                // ---------- Header ----------
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back,
                        color: AppColors.textPrimary,
                      ),
                      onPressed: () {
                        // Pop one level from the internal category stack. If the
                        // stack becomes empty, clear the selection to return to
                        // the overall overview.
                        setState(() {
                          if (_categoryStack.isNotEmpty) {
                            _categoryStack.removeLast();
                            _selectedCategory = _categoryStack.isNotEmpty
                                ? _categoryStack.last
                                : null;
                          } else {
                            _selectedCategory = null;
                          }
                        });
                      },
                    ),
                    Expanded(
                      child: Builder(
                        builder: (_) {
                          final isDe =
                              ProgramLangController.instance.lang ==
                              ProgramLang.de;
                          final id = category.id;
                          final titleText = (id == 'seven_chakras')
                              ? (isDe
                                    ? '7 Chakra Frequenzen'
                                    : '7 Chakra Frequencies')
                              : ProgramNameLocalizer.instance.displayName(
                                  keyEn: category.title,
                                  langCode: langCode,
                                );
                          return Text(
                            titleText,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: AppColors.textPrimary,
                                  fontSize: 18,
                                ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // ---------- Programs in this category ----------
                if (category.programs.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Text(
                      'Programme',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  for (final p in category.programs)
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
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: categoryMarkerColor,
                              child: const Icon(
                                Icons.play_arrow,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            title: Text(
                              ProgramNameLocalizer.instance.displayName(
                                keyEn: p.name,
                                langCode: langCode,
                              ),
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            trailing: _AddButton(
                              onAdd: () async {
                                final l10n = AppLocalizations.of(context)!;
                                final svc = MyProgramsService();
                                await svc.add(p.id);
                                if (!context.mounted) return;
                                final programName = ProgramNameLocalizer
                                    .instance
                                    .displayName(
                                      keyEn: p.name,
                                      langCode:
                                          ProgramLangController.instance.lang ==
                                              ProgramLang.de
                                          ? 'de'
                                          : 'en',
                                    );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    behavior: SnackBarBehavior.floating,
                                    duration: const Duration(
                                      milliseconds: 1500,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    backgroundColor: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    content: Row(
                                      children: [
                                        const Icon(
                                          Icons.check,
                                          color: Colors.white,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            ProgramLangController
                                                        .instance
                                                        .lang ==
                                                    ProgramLang.de
                                                ? '$programName wurde zu „Meine Programme” hinzugefügt'
                                                : '$programName added to “My Programs”',
                                            style: const TextStyle(
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                            onTap: () {
                              // Program detail navigation removed in UI refactor.
                              // Keep tap as no-op and log for debugging/testing.
                              debugPrint(
                                'AvailableProgramsPage: program tapped ${p.id}',
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                ],
                // ---------- Subcategories ----------
                if (visibleSubcategories.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Text(
                      'Unterkategorien',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  for (final sub in visibleSubcategories)
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
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: markerFrom(
                                sub.color ?? category.color,
                              ),
                              child: const Icon(
                                Icons.folder,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            title: Text(
                              ProgramNameLocalizer.instance.displayName(
                                keyEn: sub.title,
                                langCode: langCode,
                              ),
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            trailing: const Icon(
                              Icons.chevron_right,
                              color: AppColors.textSecondary,
                            ),
                            onTap: () {
                              // Push the subcategory onto the internal stack so the
                              // back arrow will return only one level.
                              debugPrint(
                                'AvailableProgramsPage: subcategory tapped ${sub.id}',
                              );
                              final subAsCategory = ProgramCategory(
                                id: sub.id,
                                title: sub.title,
                                color: sub.color ?? category.color,
                                programs: sub.programs ?? const [],
                                subcategories: const [],
                              );
                              setState(() {
                                // Ensure the parent category is on the stack first.
                                if (_categoryStack.isEmpty ||
                                    _categoryStack.last.id != category.id) {
                                  _categoryStack.add(category);
                                }
                                _categoryStack.add(subAsCategory);
                                _selectedCategory = subAsCategory;
                              });
                            },
                          ),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final langCode = (ProgramLangController.instance.lang == ProgramLang.de)
        ? 'de'
        : 'en';

    // Current mode for filtering visible categories
    final mode = AppMemory.instance.programMode;

    // IMPORTANT: Filter by inferred color (not raw c.color), otherwise yellow/red with missing
    // JSON color would be treated as green and behave inconsistently.
    final visibleCategories = _categories.where((cat) {
      final color = _inferColor(cat) ?? 'green';
      if (mode == ProgramMode.beginner) return color == 'green';
      if (mode == ProgramMode.advanced)
        return color == 'green' || color == 'yellow';
      return true; // expert
    }).toList();

    if (_selectedCategory != null) {
      return _buildCategoryView(_selectedCategory!);
    }

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
                  l10n.availableProgramsTitle,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                  ),
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
                      child: Builder(
                        builder: (ctx) {
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
                              child: const Icon(
                                Icons.apps,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            title: Builder(
                              builder: (_) {
                                // HOTFIX: special-case the known 'seven_chakras' top-folder id
                                final id = fixedCategory.id;
                                final titleText = (id == 'seven_chakras')
                                    ? l10n.sevenChakraFrequencies
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
                              },
                            ),
                            trailing: const Icon(
                              Icons.chevron_right,
                              color: AppColors.textSecondary,
                            ),
                            onTap: () {
                              final progCount =
                                  (fixedCategory.programs?.length ?? 0);
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
                                  SnackBar(content: Text(l10n.categoryEmpty)),
                                );
                                return;
                              }

                              if (modeNow == ProgramMode.beginner && isYellow) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      l10n.categoryNotAvailableInMode,
                                    ),
                                  ),
                                );
                                return;
                              }

                              // Always open CategoriesPage. It shows programs (with +) and subcategories together.
                              setState(() {
                                _categoryStack.clear();
                                _categoryStack.add(fixedCategory);
                                _selectedCategory = fixedCategory;
                              });
                            },
                          );
                        },
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

// Add a small local transient Add button widget that briefly shows a checkmark when done.
class _AddButton extends StatefulWidget {
  final Future<void> Function() onAdd;
  const _AddButton({required this.onAdd});

  @override
  State<_AddButton> createState() => _AddButtonState();
}

class _AddButtonState extends State<_AddButton>
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
