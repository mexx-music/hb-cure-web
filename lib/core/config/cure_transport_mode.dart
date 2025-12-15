/// Globaler Modus für die Cure-BLE-Kommunikation.
/// - flutterBluePlus: alles wie bisher über FBP/CureProtocol.
/// - native: FlutterBluePlus nur zum Scannen, GATT-Owner ist der native Transport.
enum CureTransportMode {
  flutterBluePlus,
  native
}

/// Aktueller globaler Modus.
/// Für die aktuelle Debug-/Fix-Runde verwenden wir standardmäßig `native`.
const CureTransportMode kCureTransportMode = CureTransportMode.native;
