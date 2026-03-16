import 'package:shared_preferences/shared_preferences.dart';

class CustomFrequencyNameStore {
  CustomFrequencyNameStore._();
  static final CustomFrequencyNameStore instance = CustomFrequencyNameStore._();

  String _key(String id) => 'custom_name_$id';

  Future<void> setName(String id, String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(id), name);
  }

  Future<String?> getName(String id) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key(id));
  }

  Future<void> remove(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(id));
  }
}

