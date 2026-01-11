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
import 'package:hbcure/core/catalog/catalog_color.dart';
import 'package:hbcure/core/catalog/catalog_visibility.dart';
import 'package:hbcure/services/app_memory.dart';

class ProgramListPage extends StatefulWidget {
  final String title;
  final List<ProgramItem> programs;

  /// Optional: caller can pass a mode, but we always prefer AppMemory.programMode
  /// so that changes apply immediately without recreating the page.
  final ProgramMode mode;

  // BEGIN PATCH: optional parentColor to allow caller to pass folder color
  final String? parentColor;
  // END PATCH

  const ProgramListPage({
    super.key,
    required this.title,
    required this.programs,
    this.mode = ProgramMode.expert,
    this.parentColor,
  });

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

    // Listen for programMode changes and rebuild so filters update immediately
    AppMemory.instance.addListener(_onAppMemoryChanged);
  }

  void _onLangChanged() {
    if (mounted) setState(() {});
  }

  void _onAppMemoryChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    ProgramLangController.instance.removeListener(_onLangChanged);
    AppMemory.instance.removeListener(_onAppMemoryChanged);
    super.dispose();
  }

  // Helper: Build localized Chakra name from program id (e.g. "..._1" -> "Seven Chakras 1")
  String _chakraNameFromId(String id, {required bool isDe}) {
    final m = RegExp(r"(\d+)$").firstMatch(id.trim());
    final n = m?.group(1);
    final base = isDe ? 'Sieben Chakras' : 'Seven Chakras';
    return (n == null) ? base : '$base $n';
  }

  @override
  Widget build(BuildContext context) {
    final programs = widget.programs;

    // ✅ Always read current mode from AppMemory so changes take effect immediately
    final mode = AppMemory.instance.programMode;
    debugPrint('[MODE_SOURCES] widget.mode=${widget.mode} mem.mode=${AppMemory.instance.programMode}');
    debugPrint('[MODE_USE@ProgramList] mode=$mode');

    // NOTE:
    // ProgramItem currently has no color field. Visibility here is based on level only.
    // Yellow-only gating should already be handled on category/subcategory level.
    final color = CatalogColor.green;

    // ✅ Filter upfront (avoid building lots of SizedBox.shrink())
    final filtered = programs.where((p) {
      final lvl = parseProgramLevel(p.level);
      return isNodeVisible(mode: mode, color: color, level: lvl);
    }).toList();

    // Optional sanity log (keep or remove)
    debugPrint('[MODE_USE@ProgramList] mode=$mode');
    debugPrint(
      'LEVEL_SANITY total=${programs.length} '
          'filtered=${filtered.length} '
          'mode=$mode',
    );

    return GradientBackground(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 20.0),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: Text(
                    widget.title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 12.0),
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final p = filtered[index];

                  // BEGIN PATCH: derive marker color from optional parentColor passed by caller
                  final pc = (widget.parentColor ?? '').trim().toLowerCase();
                  final markerColor = (pc == 'yellow')
                      ? AppColors.yellow
                      : (pc == 'red')
                          ? AppColors.accentRed
                          : AppColors.primaryMuted;
                  // END PATCH

                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    decoration: BoxDecoration(
                      color: AppColors.cardBackground,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.borderSubtle),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x11000000),
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        )
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          debugPrint(
                            'TAP program id=${p.id} name=${p.name} uuid=${p.uuid} internalId=${p.internalId} level=${p.level}',
                          );
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => detail.ProgramDetailPage(
                                program: p,
                                deviceId: CureDeviceUnlockService.instance.nativeConnectedDeviceId ?? '',
                              ),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: markerColor,
                                child: Icon(Icons.bubble_chart, color: AppColors.textPrimary),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  (p.name.trim() == 'Seven Chakras')
                                      ? _chakraNameFromId(
                                          p.id,
                                          isDe: (ProgramLangController.instance.lang == ProgramLang.de),
                                        )
                                      : ProgramNameLocalizer.instance.displayName(
                                          keyEn: p.name,
                                          langCode: (ProgramLangController.instance.lang == ProgramLang.de) ? 'de' : 'en',
                                        ),
                                  style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              // trailing: Add button + chevron
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  GestureDetector(
                                    onTap: () async {
                                      debugPrint('Add to My Programs: ${p.id} (${p.name})');
                                      await MyProgramsService().add(p.id);
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Zu My Programs hinzugefügt: ${p.name}')),
                                      );
                                    },
                                    child: const CircleAvatar(
                                      radius: 16,
                                      backgroundColor: AppColors.primary,
                                      child: Icon(Icons.add, color: Colors.white, size: 18),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  const Icon(Icons.chevron_right, color: AppColors.textSecondary),
                                ],
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
