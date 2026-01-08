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
                  onPressed: () => debugPrint('Search pressed'),
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
