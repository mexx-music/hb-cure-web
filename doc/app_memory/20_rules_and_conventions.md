# Regeln & Konventionen

- Services sollten auf `*Service` enden, z. B. `BleCureDeviceService`.
- BLE-Protokolle als eigene Klassen/Dateien unter `lib/services/cure_protocol.dart`.
- Keine Hardcodierung von UUIDs im UI. UUIDs in Services/Constants zentralisieren.
- Benennung: `CamelCase` für Klassen, `snake_case` für files.

Dateistruktur-Empfehlung:
```
lib/
  services/
    ble_cure_device_service.dart
    cure_protocol.dart
    app_memory.dart
  ui/
  core/
```

