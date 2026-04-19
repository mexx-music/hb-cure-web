import 'package:flutter/material.dart';
import 'package:hbcure/models/program_category.dart';
import 'package:hbcure/ui/pages/program_list_page.dart';
import 'package:hbcure/ui/pages/program_detail_page.dart' as detail;
import '../widgets/gradient_background.dart';
import '../theme/app_colors.dart';
import 'package:hbcure/i18n/program_name_localizer.dart';
import 'package:hbcure/services/program_language_controller.dart';
import 'package:hbcure/services/app_memory.dart';
import 'package:hbcure/core/program_mode.dart';
import 'package:hbcure/services/cure_device_unlock_service.dart';
import 'package:hbcure/services/my_programs_service.dart';

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

          final subColor = (sub.color ?? category.color ?? '').trim().toLowerCase();
          final isYellowOrRed = (subColor == 'yellow' || subColor == 'red');

          if (mode == ProgramMode.beginner && isYellowOrRed) return false;
          return true;
        }).toList();

        return GradientBackground(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 12.0),
              children: [
                // ---------- Header ----------
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Builder(builder: (_) {
                        final isDe =
                            ProgramLangController.instance.lang == ProgramLang.de;
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
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: AppColors.textPrimary,
                            fontSize: 18,
                          ),
                        );
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // ---------- Programs directly in category ----------
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
                              backgroundColor: categoryMarkerColor,
                              child: const Icon(Icons.bubble_chart,
                                  color: AppColors.textPrimary),
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
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _CatAddButton(
                                  onAdd: () async {
                                    debugPrint(
                                        'Add to My Programs: ${p.id} (${p.name})');
                                    await MyProgramsService().add(p.id);
                                  },
                                ),
                                const SizedBox(width: 10),
                              ],
                            ),
                            // Tap no longer opens the old details page
                            onTap: () {
                              debugPrint('Category program tap: details screen removed');
                            },
                          ),
                        ),
                      ),
                    ),
                ],

                // ---------- Subcategories ----------
                for (final sub in visibleSubcategories)
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
                            backgroundColor:
                            markerFrom(sub.color ?? category.color),
                            child: const Icon(Icons.folder,
                                color: AppColors.textPrimary),
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
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (sub.programs.length == 1)
                                _CatAddButton(
                                  onAdd: () async {
                                    final p = sub.programs.first;
                                    debugPrint(
                                        'Add to My Programs: ${p.id} (${p.name})');
                                    await MyProgramsService().add(p.id);
                                  },
                                ),
                              if (sub.programs.length == 1)
                                const SizedBox(width: 10),
                            ],
                          ),
                          onTap: () {
                            final progs = sub.programs;
                            if (progs.length == 1) {
                              final p = progs.first;
                              debugPrint('Subcategory single program tap: details screen removed');
                              return;
                            }

                            // If subcategory has no explicit color, infer from parent marker
                            final inferredColor = (() {
                              final ck = (sub.color ?? '').trim().toLowerCase();
                              if (ck == 'yellow' || ck == 'red') return ck;
                              if (categoryMarkerColor == AppColors.yellow) return 'yellow';
                              if (categoryMarkerColor == AppColors.accentRed) return 'red';
                              return null;
                            })();

                            // Build a ProgramCategory object (always) to pass to CategoriesPage.
                            final effectiveColor = inferredColor ?? (category.color ?? '').trim().toLowerCase();

                            final fixedCategory = ProgramCategory(
                              id: sub.id,
                              title: sub.title,
                              color: effectiveColor.isNotEmpty ? effectiveColor : null,
                              programs: sub.programs ?? const [],
                              subcategories: const [],
                            );

                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CategoriesPage(category: fixedCategory),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Animated add button: briefly shows checkmark with scale pop after tap.
class _CatAddButton extends StatefulWidget {
  final Future<void> Function() onAdd;
  const _CatAddButton({required this.onAdd});

  @override
  State<_CatAddButton> createState() => _CatAddButtonState();
}

class _CatAddButtonState extends State<_CatAddButton>
    with SingleTickerProviderStateMixin {
  bool _done = false;
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _scale = Tween<double>(begin: 1.0, end: 1.25).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    if (_done) return;
    await widget.onAdd();
    if (!mounted) return;
    setState(() => _done = true);
    await _ctrl.forward();
    await _ctrl.reverse();
    await Future.delayed(const Duration(milliseconds: 900));
    if (mounted) setState(() => _done = false);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      child: ScaleTransition(
        scale: _scale,
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

