# Architektur

Layerübersicht (Platzhalter):

- UI: Flutter Widgets unter `lib/ui/`
- Services: BLE-Services, Protokoll, Business-Logik unter `lib/services/`
- Models: Datenmodelle unter `lib/core/` oder `lib/models/`
- Persistence: zukünftig SharedPreferences/Hive/SQLite in `lib/services/` oder `lib/storage/`

Hinweis: BLE-Logik liegt ausschließlich in `lib/services/`, UI ist getrennt.

