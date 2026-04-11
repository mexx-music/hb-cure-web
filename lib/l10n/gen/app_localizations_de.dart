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

  @override
  String get myProgramsTitle => 'Meine Programme';

  @override
  String get noSavedPrograms => 'Keine gespeicherten Programme';

  @override
  String get navMyPrograms => 'Meine\nProgramme';

  @override
  String get navAvailable => 'Verfügbare\nProgramme';

  @override
  String get navDevices => 'Geräte';

  @override
  String get navSettings => 'Einstellungen';

  @override
  String get availableProgramsTitle => 'Verfügbare Programme';

  // --- My Programs page ---
  @override
  String get playPlaylist => 'Playlist abspielen';
  @override
  String get noClient => 'Kein Klient';
  @override
  String get settingsSaved => 'Einstellungen gespeichert';
  @override
  String get chooseClient => 'Klient wählen';
  @override
  String get customFrequency => 'Eigene Frequenz';
  @override
  String get unknownProgram => 'Unbekanntes Programm';
  @override
  String get playlistUploadFailed => 'Playlist-Upload fehlgeschlagen';
  @override
  String get singleStartFailed => 'Einzelstart fehlgeschlagen';

  // --- Custom Frequencies nav/title ---
  @override
  String get navCustomFrequencies => 'Eigene\nFrequenzen';
  @override
  String get customFrequenciesTitle => 'Eigene Frequenzen';

  // --- Custom Frequencies page ---
  @override
  String get cfExpertOnly => 'Nur im Expertenmodus verfügbar.';
  @override
  String get cfNoEntries => 'Noch keine Einträge';
  @override
  String get cfNoEntriesHint => 'Tippe auf +, um eine eigene Frequenz anzulegen.';
  @override
  String get cfFrequency => 'Frequenz';
  @override
  String get cfNote => 'Hinweis';
  @override
  String get cfInfoText => 'Hier kannst du im Expertenmodus eigene Frequenzen (eine Zahl) speichern und starten. Diese Einträge sind experimentell und nicht Teil der kuratierten Programmliste.';
  @override
  String get cfRemoveFromMyPrograms => 'Aus Meine Programme entfernen';
  @override
  String get cfRemovedFromMyPrograms => 'Entfernt aus Meine Programme.';
  @override
  String get cfStart => 'Starten';
  @override
  String get cfStartFlowNext => 'Start kommt als nächstes.';
  @override
  String get cfEdit => 'Bearbeiten';
  @override
  String get cfDelete => 'Löschen';
  @override
  String get cfDeleted => 'Gelöscht.';
  @override
  String get cfDefaultName => 'Mein Cure Programm';
  @override
  String get cfFreqHint => 'z.B. 963';
  @override
  String get cfElectricFields => 'Elektrische Felder';
  @override
  String get cfMagneticFields => 'Magnetische Felder';
  @override
  String get cfCancel => 'Abbrechen';
  @override
  String get cfSave => 'Speichern';
  @override
  String get cfErrorName => 'Bitte Name eingeben.';
  @override
  String get cfErrorFrequency => 'Bitte gültige Frequenz eingeben.';

  // --- Available Programs page ---
  @override
  String get searchPrograms => 'Programme suchen';
  @override
  String get noResults => 'Keine Ergebnisse';
  @override
  String get playNow => 'Jetzt abspielen';
  @override
  String get addToMyPrograms => 'Zu Meine Programme hinzufügen';
  @override
  String get addedToMyPrograms => 'Hinzugefügt zu Meine Programme';
  @override
  String get openDetails => 'Details öffnen';
  @override
  String get sevenChakraFrequencies => '7 Chakra Frequenzen';
  @override
  String get categoryEmpty => 'Diese Kategorie ist aktuell leer.';
  @override
  String get categoryNotAvailableInMode => 'Diese Kategorie erscheint erst im Standard-Modus.';

  // --- Settings page ---
  @override
  String get settingsProgramFilter => 'Programmfilter';
  @override
  String get settingsNovice => 'Einsteiger';
  @override
  String get settingsStandard => 'Standard';
  @override
  String get settingsExpert => 'Experte';
  @override
  String get settingsReconnect => 'Automatisch mit letztem Cure-Gerät verbinden';
  @override
  String get settingsSwitchAfterAdd => 'Ansicht wechseln nach Programmhinzufügung';
  @override
  String get settingsClients => 'Klienten';
  @override
  String get settingsClientsMgmt => 'Klientenverwaltung wird später ergänzt.';
  @override
  String get settingsReturnToStart => 'Zurück zur Startseite';
  @override
  String get settingsReturnToStartSub => 'Startbildschirm erneut anzeigen';
  @override
  String get settingsCureBaseInfo => 'CureBase-Info';

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
