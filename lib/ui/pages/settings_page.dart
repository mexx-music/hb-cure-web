import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:hbcure/ui/pages/start_page.dart';
import 'package:hbcure/services/cure_device_unlock_service.dart';
import '../theme/app_colors.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _filter = 'Novice';
  bool _reconnect = true;
  bool _switchAfterAdd = true;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Settings',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: 12),

          // ---- NEW: CureBase Debug/Info Card (minimal, no state mgmt) ----
          const _CureBaseInfoCard(),
          const SizedBox(height: 16),
          // -------------------------------------------------------------

          Text('Program Filter', style: TextStyle(color: AppColors.textPrimary)),
          DropdownButton<String>(
            value: _filter,
            items: const [
              DropdownMenuItem(value: 'Novice', child: Text('Novice')),
              DropdownMenuItem(value: 'Standard', child: Text('Standard')),
              DropdownMenuItem(value: 'Expert', child: Text('Expert')),
            ],
            onChanged: (v) => setState(() => _filter = v ?? 'Novice'),
            style: TextStyle(color: AppColors.textPrimary),
            dropdownColor: AppColors.cardBackground,
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            title: Text('Reconnect to last Cure Device',
                style: TextStyle(color: AppColors.textPrimary)),
            value: _reconnect,
            onChanged: (v) => setState(() => _reconnect = v ?? false),
            activeColor: AppColors.primary,
          ),
          CheckboxListTile(
            title: Text('Switch view after adding a program',
                style: TextStyle(color: AppColors.textPrimary)),
            value: _switchAfterAdd,
            onChanged: (v) => setState(() => _switchAfterAdd = v ?? false),
            activeColor: AppColors.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'Clients',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: 8),
          Text('Client management will be added later.',
              style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          // Return to Start Page - resets navigation stack
          Material(
            color: Colors.transparent,
            child: ListTile(
              leading:
              const Icon(Icons.restart_alt, color: AppColors.textPrimary),
              title: const Text('Return to Start Page'),
              subtitle: const Text('Show the start screen again'),
              onTap: () {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const StartPage()),
                      (route) => false,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CureBaseInfoCard extends StatelessWidget {
  const _CureBaseInfoCard();

  @override
  Widget build(BuildContext context) {
    final svc = CureDeviceUnlockService.instance;

    final hw = (svc.hardwareInfo ?? '').trim();
    final build = (svc.buildInfo ?? '').trim();
    final supports = svc.supportsRemotePrograms;

    return Card(
      color: AppColors.cardBackground,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'CureBase Info',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            Text('Hardware: ${hw.isEmpty ? '-' : hw}',
                style: TextStyle(color: AppColors.textSecondary)),
            Text('Build: ${build.isEmpty ? '-' : build}',
                style: TextStyle(color: AppColors.textSecondary)),
            Text('supportsRemotePrograms: $supports',
                style: TextStyle(color: AppColors.textSecondary)),
            if (kDebugMode) ...[
              const SizedBox(height: 8),
              Text('Native connected: ${svc.isNativeConnected}',
                  style: TextStyle(color: AppColors.textSecondary)),
              Text('DeviceId: ${svc.nativeConnectedDeviceId ?? "-"}',
                  style: TextStyle(color: AppColors.textSecondary)),
            ],
          ],
        ),
      ),
    );
  }
}
