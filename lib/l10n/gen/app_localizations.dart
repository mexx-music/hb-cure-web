import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
  ];

  /// No description provided for @startProgram.
  ///
  /// In en, this message translates to:
  /// **'Start program'**
  String get startProgram;

  /// No description provided for @stop.
  ///
  /// In en, this message translates to:
  /// **'STOP'**
  String get stop;

  /// No description provided for @help.
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get help;

  /// No description provided for @programTimer.
  ///
  /// In en, this message translates to:
  /// **'Program Timer'**
  String get programTimer;

  /// No description provided for @timerNotStarted.
  ///
  /// In en, this message translates to:
  /// **'Timer: not started'**
  String get timerNotStarted;

  /// No description provided for @duration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get duration;

  /// No description provided for @intensity.
  ///
  /// In en, this message translates to:
  /// **'Intensity'**
  String get intensity;

  /// No description provided for @myProgramsTitle.
  ///
  /// In en, this message translates to:
  /// **'My Programs'**
  String get myProgramsTitle;

  /// No description provided for @noSavedPrograms.
  ///
  /// In en, this message translates to:
  /// **'No saved programs'**
  String get noSavedPrograms;

  /// No description provided for @navMyPrograms.
  ///
  /// In en, this message translates to:
  /// **'My Programs'**
  String get navMyPrograms;

  /// No description provided for @navAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get navAvailable;

  /// No description provided for @navDevices.
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get navDevices;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @availableProgramsTitle.
  ///
  /// In en, this message translates to:
  /// **'Available Programs'**
  String get availableProgramsTitle;

  // --- My Programs page ---
  String get playPlaylist;
  String get noClient;
  String get settingsSaved;
  String get chooseClient;
  String get customFrequency;
  String get unknownProgram;
  String get playlistUploadFailed;
  String get singleStartFailed;

  // --- Custom Frequencies nav/title ---
  String get navCustomFrequencies;
  String get customFrequenciesTitle;

  // --- Custom Frequencies page ---
  String get cfExpertOnly;
  String get cfNoEntries;
  String get cfNoEntriesHint;
  String get cfFrequency;
  String get cfNote;
  String get cfInfoText;
  String get cfRemoveFromMyPrograms;
  String get cfRemovedFromMyPrograms;
  String get cfStart;
  String get cfStartFlowNext;
  String get cfEdit;
  String get cfDelete;
  String get cfDeleted;
  String get cfDefaultName;
  String get cfFreqHint;
  String get cfElectricFields;
  String get cfMagneticFields;
  String get cfCancel;
  String get cfSave;
  String get cfErrorName;
  String get cfErrorFrequency;

  // --- Available Programs page ---
  String get searchPrograms;
  String get noResults;
  String get playNow;
  String get addToMyPrograms;
  String get addedToMyPrograms;
  String get openDetails;
  String get sevenChakraFrequencies;
  String get categoryEmpty;
  String get categoryNotAvailableInMode;

  // --- Settings page ---
  String get settingsProgramFilter;
  String get settingsNovice;
  String get settingsStandard;
  String get settingsExpert;
  String get settingsReconnect;
  String get settingsSwitchAfterAdd;
  String get settingsClients;
  String get settingsClientsMgmt;
  String get settingsReturnToStart;
  String get settingsReturnToStartSub;
  String get settingsCureBaseInfo;

  // --- Playlist item setup dialog ---
  String get setupTitle;
  String get setupDurationMinutes;
  String get setupElectric;
  String get setupElectricWaveform;
  String get setupMagnetic;
  String get setupMagneticWaveform;
  String get setupCancel;
  String get setupSave;
  String get waveformSine;
  String get waveformTriangle;
  String get waveformRectangle;
  String get waveformSawtooth;

  // --- Devices page ---
  String get devicesTitle;
  String get devicesScan;
  String get devicesScanning;
  String get devicesAdapter;
  String get devicesBluetoothOff;
  String get devicesBluetoothUnauthorized;
  String get devicesBluetoothUnknown;
  String get devicesScanError;
  String get devicesAvailableDevices;
  String get devicesCureDevice;
  String get devicesNoDeviceConnected;
  String get devicesTipScan;
  String devicesFoundCount(int count);
  String get devicesNoDevicesDiscovered;
  String get devicesScanFailed;
  String get devicesConnected;
  String get devicesDisconnect;
  String get devicesConnect;
  // adapter state labels
  String get btStateOn;
  String get btStateOff;
  String get btStateUnauthorized;
  String get btStateTurningOn;
  String get btStateTurningOff;
  String get btStateUnknown;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
