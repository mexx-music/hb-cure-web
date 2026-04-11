// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get startProgram => 'Programm starten';

  @override
  String get stop => 'STOP';

  @override
  String get help => 'Hilfe';

  @override
  String get programTimer => 'Programm-Timer';

  @override
  String get timerNotStarted => 'Timer: nicht gestartet';

  @override
  String get duration => 'Dauer';

  @override
  String get intensity => 'Intensität';

  // --- Devices page ---
  @override
  String get devicesTitle => 'Geräte';
  @override
  String get devicesScan => 'Suchen';
  @override
  String get devicesScanning => 'Suche läuft...';
  @override
  String get devicesAdapter => 'Adapter';
  @override
  String get devicesBluetoothOff => 'Bluetooth ist deaktiviert. Bitte einschalten.';
  @override
  String get devicesBluetoothUnauthorized => 'Bluetooth Berechtigung verweigert. Einstellungen → Bluetooth prüfen.';
  @override
  String get devicesBluetoothUnknown => 'Bluetooth Status unbekannt.';
  @override
  String get devicesScanError => 'Scan-Fehler';
  @override
  String get devicesAvailableDevices => 'Verfügbare Cure-Geräte';
  @override
  String get devicesCureDevice => 'Cure-Gerät';
  @override
  String get devicesNoDeviceConnected => 'Kein Gerät verbunden';
  @override
  String get devicesTipScan => 'Tipp: Suchen drücken um CureBase-Geräte zu finden';
  @override
  String devicesFoundCount(int count) => '$count Gerät(e) gefunden';
  @override
  String get devicesNoDevicesDiscovered => 'Keine CureBase-Geräte gefunden';
  @override
  String get devicesScanFailed => 'Suche fehlgeschlagen';
  @override
  String get devicesConnected => 'Verbunden';
  @override
  String get devicesDisconnect => 'Trennen';
  @override
  String get devicesConnect => 'Verbinden';
  @override
  String get btStateOn => 'Ein';
  @override
  String get btStateOff => 'Aus';
  @override
  String get btStateUnauthorized => 'Keine Berechtigung';
  @override
  String get btStateTurningOn => 'Wird eingeschaltet';
  @override
  String get btStateTurningOff => 'Wird ausgeschaltet';
  @override
  String get btStateUnknown => 'Unbekannt';
}
