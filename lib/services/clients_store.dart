import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ClientProfile {
  final String id;
  final String name;

  const ClientProfile({required this.id, required this.name});

  Map<String, dynamic> toJson() => {"id": id, "name": name};

  static ClientProfile fromJson(Map<String, dynamic> j) =>
      ClientProfile(id: j["id"] as String, name: j["name"] as String);
}

class ClientsStore {
  static const _kClients = 'clients_v1';
  static const _kActive = 'clients_active_id_v1';

  static final ClientsStore instance = ClientsStore._();
  ClientsStore._();

  Future<List<ClientProfile>> loadClients() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kClients);
    if (raw == null || raw.isEmpty) return const [];
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return list.map(ClientProfile.fromJson).toList(growable: false);
  }

  Future<void> saveClients(List<ClientProfile> clients) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(clients.map((c) => c.toJson()).toList());
    await prefs.setString(_kClients, raw);
  }

  Future<String?> loadActiveClientId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kActive);
  }

  Future<void> setActiveClientId(String? id) async {
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(_kActive);
    } else {
      await prefs.setString(_kActive, id);
    }
  }

  Future<void> upsertClient(ClientProfile c) async {
    final list = (await loadClients()).toList(growable: true);
    final i = list.indexWhere((x) => x.id == c.id);
    if (i >= 0) {
      list[i] = c;
    } else {
      list.insert(0, c);
    }
    await saveClients(list);
  }

  Future<void> removeClient(String id) async {
    final list = (await loadClients()).toList(growable: true);
    list.removeWhere((x) => x.id == id);
    await saveClients(list);

    final active = await loadActiveClientId();
    if (active == id) {
      await setActiveClientId(list.isNotEmpty ? list.first.id : null);
    }
  }

  String newId() => 'client_${DateTime.now().millisecondsSinceEpoch}';
}
