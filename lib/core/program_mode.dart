// Zentrale Definition des Programm-Modus und einfache Mapping-Helpers.
// Minimal, ohne UI-Abhängigkeiten – dient als kleine Logik-Bibliothek.

/// Programm-Modi für die Programmauswahl / Beschränkungen.
/// - beginner: Anfänger
/// - advanced: Fortgeschritten
/// - expert: Experte
enum ProgramMode {
  beginner,
  advanced,
  expert,
}

/// Liefert das maximale Level, das einem [ProgramMode] zugeordnet ist.
/// - beginner -> 1
/// - advanced -> 2
/// - expert -> 3
int maxLevelForMode(ProgramMode mode) {
  switch (mode) {
    case ProgramMode.beginner:
      return 1;
    case ProgramMode.advanced:
      return 2;
    case ProgramMode.expert:
      return 3;
  }
}
