// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get startProgram => 'Start program';

  @override
  String get stop => 'STOP';

  @override
  String get help => 'Help';

  @override
  String get programTimer => 'Program Timer';

  @override
  String get timerNotStarted => 'Timer: not started';

  @override
  String get duration => 'Duration';

  @override
  String get intensity => 'Intensity';

  // --- Devices page ---
  @override
  String get devicesTitle => 'Devices';
  @override
  String get devicesScan => 'Scan';
  @override
  String get devicesScanning => 'Scanning...';
  @override
  String get devicesAdapter => 'Adapter';
  @override
  String get devicesBluetoothOff => 'Bluetooth is disabled. Please turn it on.';
  @override
  String get devicesBluetoothUnauthorized => 'Bluetooth permission denied. Check Settings → Bluetooth.';
  @override
  String get devicesBluetoothUnknown => 'Bluetooth status unknown.';
  @override
  String get devicesScanError => 'Scan error';
  @override
  String get devicesAvailableDevices => 'Available Cure Devices';
  @override
  String get devicesCureDevice => 'Cure Device';
  @override
  String get devicesNoDeviceConnected => 'No device connected';
  @override
  String get devicesTipScan => 'Tip: Press Scan to look for CureBase devices';
  @override
  String devicesFoundCount(int count) => '$count device(s) found';
  @override
  String get devicesNoDevicesDiscovered => 'No CureBase devices discovered';
  @override
  String get devicesScanFailed => 'Scan failed';
  @override
  String get devicesConnected => 'Connected';
  @override
  String get devicesDisconnect => 'Disconnect';
  @override
  String get devicesConnect => 'Connect';
  @override
  String get btStateOn => 'On';
  @override
  String get btStateOff => 'Off';
  @override
  String get btStateUnauthorized => 'Unauthorized';
  @override
  String get btStateTurningOn => 'Turning on';
  @override
  String get btStateTurningOff => 'Turning off';
  @override
  String get btStateUnknown => 'Unknown';
}
