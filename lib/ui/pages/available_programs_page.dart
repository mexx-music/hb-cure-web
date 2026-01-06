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

  @override
  Widget build(BuildContext context) {
    final langCode = (ProgramLangController.instance.lang == ProgramLang.de) ? 'de' : 'en';
    // compute current mode and visible categories here (cannot declare 'final' inside a list literal)
    final mode = AppMemory.instance.programMode;
    final visibleCategories = _categories.where((cat) {
      final raw = (cat.color ?? '').toString().trim().toLowerCase();
      final color = raw.isEmpty ? 'green' : raw; // default = green
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
                // slightly smaller title and reduced top spacing
                Text(
                  ProgramNameLocalizer.instance.displayName(
                    keyEn: 'Available Programs',
                    langCode: langCode,
                  ),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AppColors.textPrimary, fontSize: 18),
                ),
                IconButton(icon: const Icon(Icons.search, color: AppColors.textPrimary), onPressed: () => debugPrint('Search pressed')),
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
                         // compute a marker color based on the category color field
                         final markerColor = (c.color != null && c.color!.trim().toLowerCase() == 'yellow')
                             ? AppColors.yellow
                             : AppColors.primaryMuted;
                         // Debug: output the configured color/key so we can verify mappings
                         debugPrint('CAT_COLOR id=${c.id} color=${c.color}');
                         return ListTile(
                           leading: CircleAvatar(backgroundColor: markerColor, child: Icon(Icons.apps, color: AppColors.textPrimary)),
                           title: Builder(builder: (_) {
                             // HOTFIX: special-case the known 'seven_chakras' top-folder id
                             final isDe = ProgramLangController.instance.lang == ProgramLang.de;
                             final id = c.id;
                             final titleText = (id == 'seven_chakras')
                                 ? (isDe ? '7 Chakra Frequenzen' : '7 Chakra Frequencies')
                                 : ProgramNameLocalizer.instance.displayName(keyEn: c.title, langCode: langCode);
                             return Text(
                               titleText,
                               style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                             );
                           }),
                           trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
                           onTap: () {
                             // Pre-checks and small rules before navigation
                             final isYellow = (c.color ?? '').trim().toLowerCase() == 'yellow';
                             final mode = AppMemory.instance.programMode; // global mode
                             final progCount = (c.programs?.length ?? 0);
                             final subCount = (c.subcategories?.length ?? 0);
                             final isEmpty = (progCount == 0 && subCount == 0);

                             // debug info
                             debugPrint(
                               'TAP category id=${c.id} title=${c.title} programs=$progCount subcats=$subCount '
                               'yellow=$isYellow mode=$mode',
                             );

                             if (isEmpty) {
                               ScaffoldMessenger.of(context).showSnackBar(
                                 const SnackBar(content: Text('Diese Kategorie ist aktuell leer.')),
                               );
                               return;
                             }

                             if (mode == ProgramMode.beginner && isYellow) {
                               ScaffoldMessenger.of(context).showSnackBar(
                                 const SnackBar(content: Text('Diese Kategorie erscheint erst im Standard-Modus.')),
                               );
                               return;
                             }

                             Navigator.push(
                               context,
                               MaterialPageRoute(builder: (_) => CategoriesPage(category: c)),
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
