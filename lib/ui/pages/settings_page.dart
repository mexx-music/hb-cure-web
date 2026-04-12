import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:hbcure/ui/pages/start_page.dart';
import 'package:hbcure/services/cure_device_unlock_service.dart';
import '../theme/app_colors.dart';
import 'package:hbcure/l10n/gen/app_localizations.dart';
import 'package:hbcure/services/app_memory.dart';
import 'package:hbcure/core/program_mode.dart';
import 'package:hbcure/ui/pages/clients_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // ProgramMode-backed selection (replaces String _filter)
  ProgramMode _mode = ProgramMode.beginner;
  bool _reconnect = true;
  bool _switchAfterAdd = true;

  @override
  void initState() {
    super.initState();
    // initialize _mode from AppMemory.programMode
    _mode = AppMemory.instance.programMode;
    _reconnect = AppMemory.instance.reconnectEnabled;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),

          // ---- NEW: CureBase Debug/Info Card (minimal, no state mgmt) ----
          const _CureBaseInfoCard(),
          const SizedBox(height: 16),
          // -------------------------------------------------------------

          Text(l10n.settingsProgramFilter, style: TextStyle(color: AppColors.textPrimary)),
          DropdownButton<ProgramMode>(
            value: _mode,
            items: [
              DropdownMenuItem(value: ProgramMode.beginner, child: Text(l10n.settingsNovice)),
              DropdownMenuItem(value: ProgramMode.advanced, child: Text(l10n.settingsStandard)),
              DropdownMenuItem(value: ProgramMode.expert, child: Text(l10n.settingsExpert)),
            ],
            onChanged: (v) {
              final newMode = v ?? ProgramMode.beginner;
              debugPrint('SETTINGS dropdown -> $newMode');
              setState(() {
                _mode = newMode;
              });
              // update shared AppMemory state
              AppMemory.instance.programMode = newMode;
              // DEBUG: verify readback
              debugPrint('[MODE_SAVE] set=$newMode readBack=${AppMemory.instance.programMode}');
            },
            style: TextStyle(color: AppColors.textPrimary),
            dropdownColor: AppColors.cardBackground,
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            title: Text(l10n.settingsReconnect,
                style: TextStyle(color: AppColors.textPrimary)),
            value: _reconnect,
            onChanged: (v) {
              final val = v ?? false;
              setState(() => _reconnect = val);
              AppMemory.instance.setReconnectEnabled(val);
            },
            activeColor: AppColors.primary,
          ),
          CheckboxListTile(
            title: Text(l10n.settingsSwitchAfterAdd,
                style: TextStyle(color: AppColors.textPrimary)),
            value: _switchAfterAdd,
            onChanged: (v) => setState(() => _switchAfterAdd = v ?? false),
            activeColor: AppColors.primary,
          ),
          const SizedBox(height: 16),
          Text(
            l10n.settingsClients,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: 16),
          // Clients navigation
          Material(
            color: Colors.transparent,
            child: ListTile(
              leading: const Icon(Icons.person, color: AppColors.textPrimary),
              title: Text(l10n.settingsClients,
                  style: const TextStyle(color: AppColors.textPrimary)),
              trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
              onTap: () async {
                final changed = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(builder: (_) => const ClientsPage()),
                );
                if (changed == true && mounted) setState(() {});
              },
            ),
          ),

          // Return to Start Page - resets navigation stack
          Material(
            color: Colors.transparent,
            child: ListTile(
              leading:
              const Icon(Icons.restart_alt, color: AppColors.textPrimary),
              title: Text(l10n.settingsReturnToStart),
              subtitle: Text(l10n.settingsReturnToStartSub),
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
    final l10n = AppLocalizations.of(context)!;
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
              l10n.settingsCureBaseInfo,
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
