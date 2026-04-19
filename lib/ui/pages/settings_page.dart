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
  ProgramMode _mode = ProgramMode.beginner;
  bool _reconnect = true;
  bool _switchAfterAdd = true;

  @override
  void initState() {
    super.initState();
    _mode = AppMemory.instance.programMode;
    _reconnect = AppMemory.instance.reconnectEnabled;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Section: Device ──
          _SectionHeader(title: l10n.settingsCureBaseInfo, icon: Icons.bluetooth_connected),
          _SettingsCard(
            children: [
              SwitchListTile(
                title: Text(l10n.settingsReconnect,
                    style: const TextStyle(color: AppColors.textPrimary)),
                value: _reconnect,
                activeColor: AppColors.primary,
                onChanged: (v) {
                  setState(() => _reconnect = v);
                  AppMemory.instance.setReconnectEnabled(v);
                },
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              const _CureBaseStatusRow(),
            ],
          ),

          const SizedBox(height: 20),

          // ── Section: Programs ──
          _SectionHeader(title: l10n.settingsProgramFilter, icon: Icons.tune),
          _SettingsCard(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(l10n.settingsProgramFilter,
                          style: const TextStyle(color: AppColors.textPrimary)),
                    ),
                    DropdownButton<ProgramMode>(
                      value: _mode,
                      underline: const SizedBox.shrink(),
                      items: [
                        DropdownMenuItem(value: ProgramMode.beginner, child: Text(l10n.settingsNovice)),
                        DropdownMenuItem(value: ProgramMode.advanced, child: Text(l10n.settingsStandard)),
                        DropdownMenuItem(value: ProgramMode.expert, child: Text(l10n.settingsExpert)),
                      ],
                      onChanged: (v) {
                        final newMode = v ?? ProgramMode.beginner;
                        setState(() => _mode = newMode);
                        AppMemory.instance.programMode = newMode;
                      },
                      style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
                      dropdownColor: AppColors.cardBackground,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              SwitchListTile(
                title: Text(l10n.settingsSwitchAfterAdd,
                    style: const TextStyle(color: AppColors.textPrimary)),
                value: _switchAfterAdd,
                activeColor: AppColors.primary,
                onChanged: (v) => setState(() => _switchAfterAdd = v),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // ── Section: Clients ──
          _SectionHeader(title: l10n.settingsClients, icon: Icons.people_outline),
          _SettingsCard(
            children: [
              ListTile(
                leading: const Icon(Icons.person, color: AppColors.primary),
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
            ],
          ),

          const SizedBox(height: 20),

          // ── Section: App ──
          _SectionHeader(title: 'App', icon: Icons.settings_outlined),
          _SettingsCard(
            children: [
              ListTile(
                leading: const Icon(Icons.restart_alt, color: AppColors.primary),
                title: Text(l10n.settingsReturnToStart),
                subtitle: Text(l10n.settingsReturnToStartSub,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
                onTap: () {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const StartPage()),
                    (route) => false,
                  );
                },
              ),
            ],
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── Reusable section header ──
class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Text(title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Reusable card wrapper ──
class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.cardBackground,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.borderSubtle, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}

// ── Compact CureBase status row (replaces old verbose info card) ──
class _CureBaseStatusRow extends StatefulWidget {
  const _CureBaseStatusRow();

  @override
  State<_CureBaseStatusRow> createState() => _CureBaseStatusRowState();
}

class _CureBaseStatusRowState extends State<_CureBaseStatusRow> {
  final _svc = CureDeviceUnlockService.instance;

  @override
  void initState() {
    super.initState();
    _svc.deviceInfoRevision.addListener(_refresh);
  }

  @override
  void dispose() {
    _svc.deviceInfoRevision.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final connected = _svc.isNativeConnected;
    final hw = (_svc.hardwareInfo ?? '').trim();
    final build = (_svc.buildInfo ?? '').trim();
    final deviceId = _svc.nativeConnectedDeviceId;

    final statusText = connected
        ? 'Verbunden${build.isNotEmpty ? ' · FW $build' : ''}${hw.isNotEmpty ? ' · HW $hw' : ''}'
        : 'Nicht verbunden';

    return ListTile(
      dense: true,
      leading: Icon(
        connected ? Icons.check_circle : Icons.cancel_outlined,
        color: connected ? AppColors.accentGreen : AppColors.textSecondary,
        size: 22,
      ),
      title: Text('CureBase',
          style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
      subtitle: Text(statusText,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      trailing: kDebugMode && deviceId != null
          ? Text(deviceId, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary))
          : null,
    );
  }
}
