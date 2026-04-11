import 'package:flutter/material.dart';
import 'package:hbcure/ui/theme/app_colors.dart';
import 'package:hbcure/services/clients_store.dart';
import 'package:hbcure/services/program_language_controller.dart';
import 'package:hbcure/ui/widgets/gradient_background.dart';

class ClientsPage extends StatefulWidget {
  const ClientsPage({super.key});

  @override
  State<ClientsPage> createState() => _ClientsPageState();
}

class _ClientsPageState extends State<ClientsPage> {
  bool get _isDe => ProgramLangController.instance.lang == ProgramLang.de;

  late Future<List<ClientProfile>> _future;
  String? _activeId; // newly added: currently active client id
  bool _changed = false; // tracks whether any client data was mutated

  @override
  void initState() {
    super.initState();
    _future = ClientsStore.instance.loadClients();
    // load active client id once at start
    ClientsStore.instance.loadActiveClientId().then((v) {
      if (!mounted) return;
      setState(() => _activeId = v);
    });
  }

  void _reload() {
    setState(() {
      _future = ClientsStore.instance.loadClients();
    });
    // update active client id as well
    ClientsStore.instance.loadActiveClientId().then((v) {
      if (!mounted) return;
      setState(() => _activeId = v);
    });
  }

  Future<void> _addClient() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String?>(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: Text(_isDe ? 'Neuer Klient' : 'New client'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(hintText: _isDe ? 'Name' : 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(null),
            child: Text(_isDe ? 'Abbrechen' : 'Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(ctrl.text.trim()),
            child: Text(_isDe ? 'Erstellen' : 'Create'),
          ),
        ],
      ),
    );

    final v = name?.trim();
    if (v == null || v.isEmpty) return;

    final id = ClientsStore.instance.newId();
    final profile = ClientProfile(id: id, name: v);

    await ClientsStore.instance.upsertClient(profile);

    // Optional: set newly created client active
    await ClientsStore.instance.setActiveClientId(id);

    if (!mounted) return;
    _changed = true;
    _reload();
  }

  // Long-press actions: rename / delete
  Future<void> _openClientActions(ClientProfile c) async {
    final isDe = _isDe;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return SafeArea(
          child: Material(
            color: AppColors.cardBackground,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.edit, color: AppColors.textPrimary),
                  title: Text(isDe ? 'Umbenennen' : 'Rename',
                      style: const TextStyle(color: AppColors.textPrimary)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _renameClient(c);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete, color: AppColors.accentRed),
                  title: Text(isDe ? 'Löschen' : 'Delete',
                      style: const TextStyle(color: AppColors.accentRed)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _deleteClient(c);
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _renameClient(ClientProfile c) async {
    final ctrl = TextEditingController(text: c.name);
    final name = await showDialog<String?>(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: Text(_isDe ? 'Umbenennen' : 'Rename'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(hintText: _isDe ? 'Name' : 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, null),
            child: Text(_isDe ? 'Abbrechen' : 'Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dCtx, ctrl.text.trim()),
            child: Text(_isDe ? 'OK' : 'OK'),
          ),
        ],
      ),
    );

    final v = name?.trim();
    if (v == null || v.isEmpty) return;

    await ClientsStore.instance.upsertClient(ClientProfile(id: c.id, name: v));
    if (!mounted) return;
    _changed = true;
    _reload();
  }

  Future<void> _deleteClient(ClientProfile c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: Text(_isDe ? 'Löschen?' : 'Delete?'),
        content: Text(
          _isDe ? 'Klient "${c.name}" wirklich löschen?' : 'Delete client "${c.name}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: Text(_isDe ? 'Abbrechen' : 'Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dCtx, true),
            child: Text(_isDe ? 'Löschen' : 'Delete',
                style: const TextStyle(color: AppColors.accentRed)),
          ),
        ],
      ),
    );

    if (ok != true) return;

    await ClientsStore.instance.removeClient(c.id);
    if (!mounted) return;

    // activeId könnte sich durch removeClient ändern (Store setzt ggf. neues active)
    _changed = true;
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.accentGreen,
        onPressed: _addClient,
        child: const Icon(Icons.add, color: Colors.black),
      ),
      body: GradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              // Simple top bar (instead of transparent AppBar)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
                      onPressed: () => Navigator.pop(context, _changed),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _isDe ? 'Klienten' : 'Clients',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: AppColors.textPrimary,
                            fontSize: 18,
                          ),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: FutureBuilder<List<ClientProfile>>(
                  future: _future,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final clients = snap.data ?? const [];

                    if (clients.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.person_outline, size: 56, color: AppColors.textSecondary),
                            const SizedBox(height: 10),
                            Text(
                              _isDe ? 'Noch keine Klienten.' : 'No clients yet.',
                              style: const TextStyle(color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _isDe ? 'Tippe auf +, um einen Klienten anzulegen.' : 'Tap + to add a client.',
                              style: const TextStyle(color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      itemCount: clients.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (ctx, i) {
                        final c = clients[i];
                        return Container(
                          decoration: BoxDecoration(
                            color: AppColors.cardBackground,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.borderSubtle),
                          ),
                          child: ListTile(
                            title: Text(c.name, style: const TextStyle(color: AppColors.textPrimary)),
                            // show leading active marker and set active client on tap
                            leading: Icon(
                              c.id == _activeId ? Icons.check_circle : Icons.radio_button_unchecked,
                              color: c.id == _activeId ? AppColors.accentGreen : AppColors.textSecondary,
                            ),
                            subtitle: null,
                            onTap: () async {
                              await ClientsStore.instance.setActiveClientId(c.id);
                              if (!mounted) return;
                              _changed = true;
                              setState(() => _activeId = c.id);
                            },
                            // add long-press handler to show actions
                            onLongPress: () => _openClientActions(c),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
