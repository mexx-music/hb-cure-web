import 'package:flutter/material.dart';
import 'package:hbcure/ui/pages/my_programs_page.dart';
import 'package:hbcure/ui/pages/available_programs_page.dart';
import 'package:hbcure/ui/pages/devices_page.dart';
import 'package:hbcure/ui/pages/settings_page.dart';
import 'package:hbcure/ui/theme/app_colors.dart';
import 'package:hbcure/ui/widgets/program_lang_toggle.dart';
import 'package:hbcure/l10n/gen/app_localizations.dart';
import 'package:hbcure/services/program_language_controller.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  static const List<String> _titles = [
    'My Programs',
    'Available Programs',
    'Devices',
    'Settings',
  ];

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      MyProgramsPage(),
      AvailableProgramsPage(),
      DevicesPage(),
      SettingsPage(),
    ];

    final t = AppLocalizations.of(context);
    // Bind bottom-nav labels to ProgramLangController (minimal, two-line German labels)
    final isDe = ProgramLangController.instance.lang == ProgramLang.de;

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: AppBar(
          title: Text(_appBarTitle(context)),
          actions: [
            ProgramLangToggle(onChanged: () => setState(() {})),
          ],
        ),
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: pages,
      ),
      bottomNavigationBar: SafeArea(
        bottom: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Material(
              color: AppColors.navBarBackground,
              elevation: 8,
              child: SizedBox(
                height: 72, // Pill-Höhe (wie vorher optisch), keine Schriftgröße geändert
                child: Row(
                  children: [
                    _NavTextTab(
                      label: isDe ? 'Meine\nProgramme' : 'My\nPrograms',
                      selected: _currentIndex == 0,
                      onTap: () => setState(() => _currentIndex = 0),
                    ),
                    _NavTextTab(
                      label: isDe ? 'Verfügbare\nProgramme' : 'Available\nPrograms',
                      selected: _currentIndex == 1,
                      onTap: () => setState(() => _currentIndex = 1),
                    ),
                    _NavTextTab(
                      label: isDe ? 'Geräte' : 'Devices',
                      selected: _currentIndex == 2,
                      onTap: () => setState(() => _currentIndex = 2),
                    ),
                    _NavTextTab(
                      label: isDe ? 'Einstellungen' : 'Settings',
                      selected: _currentIndex == 3,
                      onTap: () => setState(() => _currentIndex = 3),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Helper to provide localized AppBar titles based on the current index
  String _appBarTitle(BuildContext context) {
    final isDe = ProgramLangController.instance.lang == ProgramLang.de;

    switch (_currentIndex) {
      case 0:
        return isDe ? 'Meine Programme' : 'My Programs';
      case 1:
        return isDe ? 'Verfügbare Programme' : 'Available Programs';
      case 2:
        return isDe ? 'Geräte' : 'Devices';
      case 3:
        return isDe ? 'Einstellungen' : 'Settings';
      default:
        return '';
    }
  }
}

class _NavTextTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavTextTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Wichtig: Center + textAlign.center => 100% mittig, auch bei 2 Zeilen
    final style = TextStyle(
      fontSize: 12, // NICHT geändert
      height: 1.15, // nur Zeilenblock "ruhiger"
      color: selected ? AppColors.navBarActive : AppColors.navBarInactive,
    );

    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: style,
            maxLines: 2,
            overflow: TextOverflow.visible,
          ),
        ),
      ),
    );
  }
}
