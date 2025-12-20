import 'package:flutter/material.dart';
import 'package:hbcure/services/program_language_controller.dart';

class ProgramLangToggle extends StatelessWidget {
  final VoidCallback? onChanged;
  const ProgramLangToggle({super.key, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final lang = ProgramLangController.instance.lang;
    final label = (lang == ProgramLang.de) ? 'DE' : 'EN';
    return TextButton(
      onPressed: () {
        ProgramLangController.instance.toggle();
        if (onChanged != null) onChanged!();
      },
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }
}

