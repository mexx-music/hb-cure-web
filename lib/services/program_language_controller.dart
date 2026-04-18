import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Central controller for program language (DE/EN)

enum ProgramLang { de, en }

class ProgramLangController extends ChangeNotifier {
  ProgramLangController._();
  static final ProgramLangController instance = ProgramLangController._();

  static const _key = 'app_language';

  ProgramLang lang = ProgramLang.de;

  /// Load persisted language. Call once at startup before runApp.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(_key);
      if (v == 'en') lang = ProgramLang.en;
    } catch (_) {}
  }

  void setLang(ProgramLang l) {
    if (lang == l) return;
    lang = l;
    _persist();
    notifyListeners();
  }

  void toggle() {
    lang = (lang == ProgramLang.de) ? ProgramLang.en : ProgramLang.de;
    _persist();
    notifyListeners();
  }

  void _persist() {
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString(_key, lang == ProgramLang.de ? 'de' : 'en');
    }).catchError((_) {});
  }
}
