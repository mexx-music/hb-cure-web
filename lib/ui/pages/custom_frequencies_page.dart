import 'package:flutter/material.dart';
import 'package:hbcure/ui/widgets/gradient_background.dart';
import 'package:hbcure/ui/theme/app_colors.dart';
import 'package:hbcure/services/program_language_controller.dart';
import 'package:hbcure/core/program_mode.dart';
import 'package:hbcure/i18n/program_name_localizer.dart';

class CustomFrequenciesPage extends StatelessWidget {
  const CustomFrequenciesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final langCode =
        (ProgramLangController.instance.lang == ProgramLang.de) ? 'de' : 'en';

    return GradientBackground(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ProgramNameLocalizer.instance.displayName(
                keyEn: 'Custom Frequencies',
                langCode: langCode,
              ),
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(color: AppColors.textPrimary),
            ),
            const SizedBox(height: 12),
            Text(
              ProgramNameLocalizer.instance.displayName(
                keyEn: 'Coming soon',
                langCode: langCode,
              ),
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

