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

  @override
  String get myProgramsTitle => 'My Programs';

  @override
  String get noSavedPrograms => 'No saved programs';

  @override
  String get navMyPrograms => 'My Programs';

  @override
  String get navAvailable => 'Available';

  @override
  String get navDevices => 'Devices';

  @override
  String get navSettings => 'Settings';

  @override
  String get availableProgramsTitle => 'Available Programs';

  // --- My Programs page ---
  @override
  String get playPlaylist => 'Play Playlist';
  @override
  String get noClient => 'No client';
  @override
  String get settingsSaved => 'Settings saved';
  @override
  String get chooseClient => 'Choose client';
  @override
  String get customFrequency => 'Custom Frequency';
  @override
  String get unknownProgram => 'Unknown Program';
  @override
  String get playlistUploadFailed => 'Playlist upload failed';
  @override
  String get singleStartFailed => 'Single start failed';

  // --- Custom Frequencies nav/title ---
  @override
  String get navCustomFrequencies => 'Custom\nFrequencies';
  @override
  String get customFrequenciesTitle => 'Custom Frequencies';

  // --- Custom Frequencies page ---
  @override
  String get cfExpertOnly => 'Only available in Expert mode.';
  @override
  String get cfNoEntries => 'No entries yet';
  @override
  String get cfNoEntriesHint => 'Tap + to create a custom frequency.';
  @override
  String get cfFrequency => 'Frequency';
  @override
  String get cfNote => 'Note';
  @override
  String get cfInfoText => 'In Expert mode you can save and start custom frequencies (a single number). These entries are experimental and not part of the curated program list.';
  @override
  String get cfRemoveFromMyPrograms => 'Remove from My Programs';
  @override
  String get cfRemovedFromMyPrograms => 'Removed from My Programs.';
  @override
  String get cfStart => 'Start';
  @override
  String get cfStartFlowNext => 'Start flow is next.';
  @override
  String get cfEdit => 'Edit';
  @override
  String get cfDelete => 'Delete';
  @override
  String get cfDeleted => 'Deleted.';
  @override
  String get cfDefaultName => 'My Cure Program';
  @override
  String get cfFreqHint => 'e.g. 963';
  @override
  String get cfElectricFields => 'Electric fields';
  @override
  String get cfMagneticFields => 'Magnetic fields';
  @override
  String get cfCancel => 'Cancel';
  @override
  String get cfSave => 'Save';
  @override
  String get cfErrorName => 'Please enter a name.';
  @override
  String get cfErrorFrequency => 'Please enter a valid frequency.';

  // --- Available Programs page ---
  @override
  String get searchPrograms => 'Search programs';
  @override
  String get noResults => 'No results';
  @override
  String get playNow => 'Play now';
  @override
  String get addToMyPrograms => 'Add to My Programs';
  @override
  String get addedToMyPrograms => 'Added to My Programs';
  @override
  String get openDetails => 'Open details';
  @override
  String get sevenChakraFrequencies => '7 Chakra Frequencies';
  @override
  String get categoryEmpty => 'This category is currently empty.';
  @override
  String get categoryNotAvailableInMode => 'This category is only available in Standard mode.';

  // --- Settings page ---
  @override
  String get settingsProgramFilter => 'Program Filter';
  @override
  String get settingsNovice => 'Novice';
  @override
  String get settingsStandard => 'Standard';
  @override
  String get settingsExpert => 'Expert';
  @override
  String get settingsReconnect => 'Reconnect to last Cure Device';
  @override
  String get settingsSwitchAfterAdd => 'Switch view after adding a program';
  @override
  String get settingsClients => 'Clients';
  @override
  String get settingsClientsMgmt => 'Client management will be added later.';
  @override
  String get settingsReturnToStart => 'Return to Start Page';
  @override
  String get settingsReturnToStartSub => 'Show the start screen again';
  @override
  String get settingsCureBaseInfo => 'CureBase Info';

  // --- Playlist item setup dialog ---
  @override
  String get setupTitle => 'Setup';
  @override
  String get setupDurationMinutes => 'Duration (minutes)';
  @override
  String get setupElectric => 'Electric';
  @override
  String get setupElectricWaveform => 'Electric waveform';
  @override
  String get setupMagnetic => 'Magnetic';
  @override
  String get setupMagneticWaveform => 'Magnetic waveform';
  @override
  String get setupCancel => 'Cancel';
  @override
  String get setupSave => 'Save';
  @override
  String get waveformSine => 'Sine';
  @override
  String get waveformTriangle => 'Triangle';
  @override
  String get waveformRectangle => 'Rectangle';
  @override
  String get waveformSawtooth => 'Sawtooth';

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
