import 'package:flutter/material.dart';
import 'package:hbcure/models/program_category.dart';
import 'package:hbcure/ui/pages/program_list_page.dart';
import '../widgets/gradient_background.dart';
import '../theme/app_colors.dart';
import 'package:hbcure/i18n/program_name_localizer.dart';
import 'package:hbcure/services/program_language_controller.dart';
import 'package:hbcure/services/app_memory.dart';
import 'package:hbcure/core/program_mode.dart';

class CategoriesPage extends StatefulWidget {
  final ProgramCategory category;

  const CategoriesPage({super.key, required this.category});

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  late final VoidCallback _langListener;

  @override
  void initState() {
    super.initState();
    _langListener = () => setState(() {});
    ProgramLangController.instance.addListener(_langListener);
  }

  @override
  void dispose() {
    ProgramLangController.instance.removeListener(_langListener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final langCode =
        (ProgramLangController.instance.lang == ProgramLang.de) ? 'de' : 'en';

    return ValueListenableBuilder<ProgramMode>(
      valueListenable: AppMemory.instance.programModeNotifier,
      builder: (context, mode, _) {
        final category = widget.category;
        // Robust color selection for category avatars: only treat exact 'yellow' (trim/case-insensitive)
        // as yellow; otherwise keep existing muted primary color so nothing gets forced to green.
        final catIsYellow =
            (category.color ?? '').trim().toLowerCase() == 'yellow';
        final bgColor = catIsYellow ? AppColors.yellow : AppColors.primaryMuted;

        // ✅ Novice-Regel: gelbe Top-Kategorien komplett verstecken
        if (mode == ProgramMode.beginner && catIsYellow) {
          // NOTE: avoid returning an empty SizedBox here to prevent a black/empty screen
          // for novice users — show a small informative page with a back button instead.
          return GradientBackground(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Text(
                          ProgramNameLocalizer.instance.displayName(
                            keyEn: category.title,
                            langCode: langCode,
                          ),
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                color: AppColors.textPrimary,
                                fontSize: 18,
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Diese Kategorie ist im Novice-Modus nicht sichtbar.',
                    style: TextStyle(color: AppColors.textPrimary),
                  ),
                ],
              ),
            ),
          );
        }

        // Removed early-return for categories without subcategories so we can show
        // both programs and subcategories in a single ListView (programs first).

        // Filter subcategories once: remove completely empty entries (no programs and no sub-subcategories)
        // and, in Novice (beginner) mode, hide categories that are marked yellow.
        final visibleSubcategories = category.subcategories.where((sub) {
          // ProgramSubcategory defines only `programs` (no `subcategories`).
          // Treat a subcategory as empty if it has no programs.
          final progCount = (sub.programs.length);
          final isEmpty = (progCount == 0);
          if (isEmpty) return false;

          // Prefer sub.color if present, otherwise fall back to parent category.color
          final subIsYellow = ((sub.color ?? category.color ?? '').toString().trim().toLowerCase() == 'yellow');
          if (mode == ProgramMode.beginner && subIsYellow) return false;

          return true;
        }).toList();

        return GradientBackground(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 12.0),
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Builder(builder: (_) {
                        // HOTFIX: special-case 'seven_chakras' id to produce stable DE/EN labels
                        final isDe = ProgramLangController.instance.lang == ProgramLang.de;
                        final id = category.id;
                        final titleText = (id == 'seven_chakras')
                            ? (isDe ? '7 Chakra Frequenzen' : '7 Chakra Frequencies')
                            : ProgramNameLocalizer.instance.displayName(
                                keyEn: category.title,
                                langCode: langCode,
                              );
                        return Text(
                          titleText,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                color: AppColors.textPrimary,
                                fontSize: 18,
                              ),
                        );
                      }),
                    ),
                    IconButton(
                      icon: const Icon(Icons.tune, color: AppColors.textPrimary),
                      onPressed: () => debugPrint('Filter'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // --- NEW: show programs first, if any ---
                if (category.programs.isNotEmpty) ...[
                  for (final p in category.programs)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6.0),
                      child: Material(
                        color: Colors.transparent,
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.cardBackground,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.borderSubtle),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: bgColor,
                              child: const Icon(Icons.bubble_chart, color: AppColors.textPrimary),
                            ),
                            title: Text(
                              ProgramNameLocalizer.instance.displayName(
                                keyEn: p.name,
                                langCode: langCode,
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ProgramListPage(
                                  title: p.name,
                                  programs: [p],
                                  mode: mode,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],

                // existing subcategory loop (unchanged)
                for (final sub in visibleSubcategories)
                  Builder(builder: (ctx) {
                    // ProgramSubcategory may define its own `color`; prefer it and
                    // otherwise fall back to the parent category's color.
                    final subIsYellow = ((sub.color ?? category.color ?? '').toString().trim().toLowerCase() == 'yellow');

                    final subBgColor = subIsYellow ? AppColors.yellow : bgColor;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6.0),
                      child: Material(
                        color: Colors.transparent,
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.cardBackground,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.borderSubtle),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: subBgColor,
                              child: const Icon(Icons.folder, color: AppColors.textPrimary),
                            ),
                            title: Text(
                              ProgramNameLocalizer.instance.displayName(
                                keyEn: sub.title,
                                langCode: langCode,
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ProgramListPage(
                                  title: sub.title,
                                  programs: sub.programs,
                                  mode: mode,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
              ],
            ),
          ),
        );
      },
    );
  }
}
