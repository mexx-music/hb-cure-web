import 'package:flutter/material.dart';
import 'package:hbcure/models/program_category.dart';
import 'package:hbcure/ui/pages/program_list_page.dart';
import '../widgets/gradient_background.dart';
import '../theme/app_colors.dart';

class CategoriesPage extends StatelessWidget {
  final ProgramCategory category;

  const CategoriesPage({super.key, required this.category});

  @override
  Widget build(BuildContext context) {
    if (category.subcategories.isEmpty) {
      // No subcategories -> show programs directly
      return ProgramListPage(title: category.title, programs: category.programs);
    }

    return GradientBackground(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
        child: ListView(
          padding: const EdgeInsets.only(bottom: 12.0),
          children: [
            Row(
              children: [
                IconButton(icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary), onPressed: () => Navigator.pop(context)),
                Expanded(child: Text(category.title, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AppColors.textPrimary, fontSize: 18))),
                IconButton(icon: const Icon(Icons.tune, color: AppColors.textPrimary), onPressed: () => debugPrint('Filter')),
              ],
            ),
            const SizedBox(height: 6),
            for (final sub in category.subcategories)
              Padding(
                padding: const EdgeInsets.only(bottom: 6.0),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    decoration: BoxDecoration(color: AppColors.cardBackground, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.borderSubtle)),
                    child: ListTile(
                      leading: CircleAvatar(backgroundColor: AppColors.primaryMuted, child: const Icon(Icons.folder, color: AppColors.textPrimary)),
                      title: Text(sub.title, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                      trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProgramListPage(title: sub.title, programs: sub.programs))),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
