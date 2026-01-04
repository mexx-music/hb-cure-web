import 'package:flutter/foundation.dart';

// Central controller for program language (DE/EN)

enum ProgramLang { de, en }

class ProgramLangController extends ChangeNotifier {
  ProgramLangController._();
  static final ProgramLangController instance = ProgramLangController._();

  ProgramLang lang = ProgramLang.de;

  void toggle() {
    lang = (lang == ProgramLang.de) ? ProgramLang.en : ProgramLang.de;
    notifyListeners();
  }
}
