import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';
import 'package:hbcure/services/program_language_controller.dart';

class FirstStepsPage extends StatelessWidget {
  const FirstStepsPage({super.key});

  static const _nativeCh = MethodChannel('cure_ble_native/methods');

  Future<void> _openLocationSettings() async {
    try {
      await _nativeCh.invokeMethod('openLocationSettings');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isDe = ProgramLangController.instance.lang == ProgramLang.de;

    final List<_StepCardData> cards = [
      _StepCardData(
        icon: Icons.bluetooth,
        title: isDe ? 'Bluetooth einschalten' : 'Turn on Bluetooth',
        text: isDe
            ? 'Aktiviere Bluetooth auf deinem Smartphone, damit die App dein Gerät finden kann.'
            : 'Enable Bluetooth on your phone so the app can find your device.',
      ),
      _StepCardData(
        icon: Icons.location_on,
        title: isDe ? 'Standort aktivieren' : 'Enable Location',
        text: isDe
            ? 'Android benötigt Standortfreigabe für die Bluetooth-Gerätesuche.\nBitte Standort aktivieren und Zugriff erlauben.'
            : 'Android requires location permission for Bluetooth device discovery. Please enable location and grant access.',
        hasAction: true,
      ),
      _StepCardData(
        icon: Icons.power,
        title: isDe ? 'Gerät einschalten' : 'Turn on your Device',
        text: isDe
            ? 'Schalte deine CureBase oder CureClip ein und halte das Gerät in der Nähe.'
            : 'Turn on your CureBase or CureClip and keep the device nearby.',
      ),
      _StepCardData(
        icon: Icons.link,
        title: isDe ? 'Gerät verbinden' : 'Connect Device',
        text: isDe
            ? 'Öffne die Geräte-Seite, wähle dein Gerät aus und tippe auf Verbinden.'
            : 'Open the Devices page, select your device and tap Connect.',
      ),
      _StepCardData(
        icon: Icons.play_arrow,
        title: isDe ? 'Programm starten' : 'Start Program',
        text: isDe
            ? 'Füge Programme hinzu und starte sie über den Player.'
            : 'Add programs and start them from the player.',
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(isDe ? 'Erste Schritte' : 'First Steps', style: const TextStyle(color: Colors.white)),
        centerTitle: true,
      ),
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 6),
                ...cards.map((c) => _buildCard(context, c)).toList(),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.center,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: Text(isDe ? 'Schließen' : 'Close', style: TextStyle(color: AppColors.textPrimary.withValues(alpha: 0.75))),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard(BuildContext context, _StepCardData data) {
    return Card(
      color: AppColors.cardBackground,
      margin: const EdgeInsets.only(bottom: 12.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.accentGreen.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(data.icon, color: AppColors.accentGreen),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(data.title, style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  Text(data.text, style: TextStyle(color: AppColors.textPrimary.withValues(alpha: 0.75), fontSize: 14)),
                  if (data.hasAction) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                          onPressed: () async {
                            await _openLocationSettings();
                            // stay on this page
                          },
                          child: const Text('Standort öffnen'),
                        ),
                        const SizedBox(width: 8),
                        const SizedBox.shrink(),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepCardData {
  final IconData icon;
  final String title;
  final String text;
  final bool hasAction;
  const _StepCardData({required this.icon, required this.title, required this.text, this.hasAction = false});
}
