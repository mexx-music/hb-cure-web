import 'package:flutter/material.dart';
import 'package:hbcure/models/program_item.dart';
import 'package:hbcure/ui/pages/program_detail_page.dart' as detail;
import '../../services/my_programs_service.dart';
import '../../services/cure_device_unlock_service.dart';
import 'package:hbcure/i18n/program_name_localizer.dart';
import 'package:hbcure/services/program_language_controller.dart';
import '../widgets/gradient_background.dart';
import '../theme/app_colors.dart';
import 'package:hbcure/core/program_mode.dart';

class ProgramListPage extends StatefulWidget {
  final String title;
  final List<ProgramItem> programs;
  // Mode-based level filtering: default is expert (no filtering)
  final ProgramMode mode;

  const ProgramListPage({super.key, required this.title, required this.programs, this.mode = ProgramMode.expert});

  @override
  State<ProgramListPage> createState() => _ProgramListPageState();
}

class _ProgramListPageState extends State<ProgramListPage> {
  @override
  void initState() {
    super.initState();
    // Ensure the name-localizer CSV is loaded and rebuild so DE labels appear.
    ProgramNameLocalizer.instance.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    }).catchError((e) {
      debugPrint('ProgramNameLocalizer.ensureLoaded failed: $e');
    });

    // Listen for language changes and rebuild
    ProgramLangController.instance.addListener(_onLangChanged);
  }

  void _onLangChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    ProgramLangController.instance.removeListener(_onLangChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final programs = widget.programs;
    final mode = widget.mode;

    // TEMPORARY: disable level filtering so all programs are visible during debugging
    debugPrint("LEVEL_SANITY (filter disabled) total=${programs.length} lvl1=${programs.where((p)=>p.level==1).length} lvl2=${programs.where((p)=>p.level==2).length} lvl3=${programs.where((p)=>p.level==3).length} mode=$mode");
    final filtered = programs;

    return GradientBackground(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 20.0),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary), onPressed: () => Navigator.pop(context)),
                Expanded(child: Text(widget.title, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AppColors.textPrimary))),
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
              child: ListView.builder(
                // Small bottom gap so items don't touch the nav bar; rely on Scaffold default for safe insets
                padding: const EdgeInsets.only(bottom: 12.0),
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final p = filtered[index];
                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    decoration: BoxDecoration(
                      color: AppColors.cardBackground,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.borderSubtle),
                      boxShadow: const [BoxShadow(color: Color(0x11000000), blurRadius: 4, offset: Offset(0, 2))],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          // HBDBG: log program tap info for debugging translation/mapping
                          debugPrint('TAP program id=${p.id} name=${p.name} uuid=${p.uuid} internalId=${p.internalId} level=${p.level}');
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => detail.ProgramDetailPage(program: p, deviceId: CureDeviceUnlockService.instance.nativeConnectedDeviceId ?? '')),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: AppColors.primaryMuted,
                                child: Icon(Icons.bubble_chart, color: AppColors.textPrimary),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  ProgramNameLocalizer.instance.displayName(
                                    keyEn: p.name,
                                    langCode: (ProgramLangController.instance.lang == ProgramLang.de) ? 'de' : 'en',
                                  ),
                                  style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () async {
                                  debugPrint('Add to My Programs: ${p.id} (${p.name})');
                                  await MyProgramsService().add(p.id);
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Zu My Programs hinzugefügt: ${p.name}')));
                                },
                                child: CircleAvatar(
                                  radius: 20,
                                  backgroundColor: AppColors.primary,
                                  child: const Icon(Icons.add, color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
