import 'package:flutter/material.dart';
import 'package:hbcure/ui/pages/my_programs_page.dart';
import 'package:hbcure/ui/pages/available_programs_page.dart';
import 'package:hbcure/ui/pages/devices_page.dart';
import 'package:hbcure/ui/pages/settings_page.dart';
import 'package:hbcure/ui/theme/app_colors.dart';

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
      const MyProgramsPage(),
      const AvailableProgramsPage(),
      const DevicesPage(),
      const SettingsPage(),
    ];

    return Scaffold(
       appBar: PreferredSize(
         preferredSize: const Size.fromHeight(kToolbarHeight),
         child: AppBar(
           title: Text(_titles[_currentIndex]),
         ),
       ),
      // Pages themselves reserve bottom space for the bottom navigation where needed.
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
              child: BottomNavigationBar(
                currentIndex: _currentIndex,
                type: BottomNavigationBarType.fixed,
                backgroundColor: Colors.transparent,
                elevation: 0,
                selectedItemColor: AppColors.navBarActive,
                unselectedItemColor: AppColors.navBarInactive,
                selectedFontSize: 12,
                unselectedFontSize: 12,
                iconSize: 20,
                onTap: (idx) => setState(() => _currentIndex = idx),
                items: const [
                  BottomNavigationBarItem(icon: Icon(Icons.favorite), label: 'My Programs'),
                  BottomNavigationBarItem(icon: Icon(Icons.apps), label: 'Available'),
                  BottomNavigationBarItem(icon: Icon(Icons.devices_other), label: 'Devices'),
                  BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
