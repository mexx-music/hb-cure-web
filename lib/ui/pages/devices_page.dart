import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import '../widgets/gradient_background.dart';
import '../theme/app_colors.dart';
import '../../services/ble_cure_device_service.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:async';
import 'package:hbcure/core/cure_protocol/cure_test_programs.dart';
import 'package:hbcure/services/native_unlock_test.dart';
import 'package:hbcure/services/cure_device_unlock_service.dart';
import 'package:hbcure/core/cure_protocol/cure_program_compiler.dart';
import 'package:hbcure/core/config/cure_transport_mode.dart';
import 'package:hbcure/services/qt_remote_program_encoder.dart';
import 'package:hbcure/l10n/gen/app_localizations.dart';
import 'package:hbcure/services/app_memory.dart';
import 'package:hbcure/services/program_language_controller.dart';
import 'dart:typed_data';

class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key});

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  final _ble = BleCureDeviceService.instance;
  Stream<List<BluetoothDevice>>? _devicesStream;
  StreamSubscription<String?>? _bleErrorSub;
  String? _scanError;
  bool _isScanningLocal = false;
  bool? _locationServiceEnabled; // null = not checked yet; only relevant on Android
  bool _noDeviceHelpShown = false;
  bool _hasFoundDevices = false;
  StreamSubscription<bool>? _unlockSub;
  bool _unlockInProgressLocal = false;

  // UI-only: track auto-unlock attempt state per device
  // _unlockOkById: null=unknown, true=ok, false=failed
  // _unlockBusyById: currently attempting unlock
  final Map<String, bool?> _unlockOkById = {};
  final Set<String> _unlockBusyById = {};

  // UI-only: remember expansion state
  bool _devExpanded = false;

  // UI-only: cache friendly platform names per device id to keep stable labels across reconnects
  final Map<String, String> _cachedFriendlyNames = {};

  @override
  void initState() {
    super.initState();
    _devicesStream = _ble.scanForCureDevices();

    // Unlock-Progress beobachten (für den Unlock-Button in diesem Screen)
    _unlockSub = _ble.unlockStream.listen((v) {
      if (!mounted) return;
      setState(() {
        _unlockInProgressLocal = v;
      });
    });

    // Fehler vom BLE-Service anzeigen
    _bleErrorSub = _ble.errorStream.listen((err) {
      if (!mounted) return;
      setState(() {
        _scanError = err;
      });
    });

    // Auto-Scan beim Start (mit Fehler-Handling)
    Future.microtask(() async {
      if (!kIsWeb) await _checkLocationAndScan();
    });
    if (!kIsWeb && Platform.isAndroid) {
      _isLocationServiceEnabled().then((ok) {
        if (mounted) setState(() => _locationServiceEnabled = ok);
      });
    }
  }

  @override
  void dispose() {
    _ble.stopScan();
    _bleErrorSub?.cancel();
    _unlockSub?.cancel();
    super.dispose();
  }

  static const _nativeCh = MethodChannel('cure_ble_native/methods');

  Future<bool> _isLocationServiceEnabled() async {
    if (!Platform.isAndroid) return true;
    try {
      final result = await _nativeCh.invokeMethod<bool>(
        'isLocationServiceEnabled',
      );
      return result ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<void> _openLocationSettings() async {
    try {
      await _nativeCh.invokeMethod('openLocationSettings');
    } catch (_) {}
  }

  Future<void> _openAppSettings() async {
    try {
      await _nativeCh.invokeMethod('openAppSettings');
    } catch (_) {}
  }

  Future<void> _guidedOpenLocationSettings() async {
    final isDe = ProgramLangController.instance.lang == ProgramLang.de;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isDe ? 'Standort aktivieren' : 'Enable location'),
        content: Text(
          isDe
              ? 'Damit Cure-Geräte gefunden werden können:\n\n'
                '1. Standort aktivieren\n'
                '2. App auswählen\n'
                '3. „Während der Nutzung erlauben" wählen\n\n'
                'Danach bitte zur App zurückkehren.'
              : 'To find Cure devices:\n\n'
                '1. Enable location\n'
                '2. Select the app\n'
                '3. Choose \'Allow while using the app\'\n\n'
                'Then return to the app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(isDe ? 'Abbrechen' : 'Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(isDe ? 'Jetzt öffnen' : 'Open settings'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _openLocationSettings();
  }

  Future<void> _requestBlePermissions() async {
    try {
      await _nativeCh.invokeMethod('requestBlePermissions');
      if (Platform.isAndroid && mounted) {
        final ok = await _isLocationServiceEnabled();
        if (mounted) setState(() => _locationServiceEnabled = ok);
      }
      await Future.delayed(const Duration(milliseconds: 500));
      await _checkLocationAndScan();
    } catch (_) {}
  }

  Future<void> _checkLocationAndScan() async {
    if (Platform.isAndroid) {
      final locationEnabled = await _isLocationServiceEnabled();
      if (!locationEnabled && mounted) {
        final confirmed = await _showLocationDialog();
        if (confirmed == true) {
          await _openLocationSettings();
          return; // user must re-open app / press Scan again
        }
        // user dismissed – still try to scan
      }
    }
    try {
      await _ble.startScan();
    } catch (e) {
      if (kDebugMode) debugPrint('Scan failed: $e');
      if (mounted) {
        setState(() {
          _scanError = e.toString();
        });
      }
    }
  }

  Future<bool?> _showLocationDialog() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Standort erforderlich'),
        content: const Text(
          'Für die Bluetooth-Geräteerkennung muss der Standortdienst aktiviert sein.\n\n'
          'Bitte aktiviere den Standort in den Systemeinstellungen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Standort aktivieren'),
          ),
        ],
      ),
    );
  }

  // --- Minimal helpers for consistent native/shared wiring ---
  Future<String> _getConnectedDeviceIdOrThrow() async {
    final connected = await FlutterBluePlus.connectedDevices;
    if (connected.isEmpty) {
      throw Exception('No connected device');
    }
    return connected.first.remoteId.toString();
  }

  Future<void> _ensureNativeConnected(String deviceId) async {
    final svc = CureDeviceUnlockService.instance;
    if (svc.isNativeConnected && svc.nativeConnectedDeviceId == deviceId)
      return;
    await svc.nativeConnect(deviceId);
  }
  // ----------------------------------------------------------

  // compact adapter state widget to display adapter status / hints in the main card
  Widget _adapterStateWidget() {
    return StreamBuilder<BluetoothAdapterState>(
      stream: FlutterBluePlus.adapterState,
      builder: (context, snap) {
        final t = AppLocalizations.of(context)!;
        final state = snap.data;
        String stateLabel;
        String hint = '';
        if (state == null) {
          stateLabel = t.btStateUnknown;
        } else {
          switch (state) {
            case BluetoothAdapterState.on:
              stateLabel = t.btStateOn;
              break;
            case BluetoothAdapterState.off:
              stateLabel = t.btStateOff;
              hint = t.devicesBluetoothOff;
              break;
            case BluetoothAdapterState.unauthorized:
              stateLabel = t.btStateUnauthorized;
              hint = t.devicesBluetoothUnauthorized;
              break;
            case BluetoothAdapterState.turningOn:
              stateLabel = t.btStateTurningOn;
              break;
            case BluetoothAdapterState.turningOff:
              stateLabel = t.btStateTurningOff;
              break;
            default:
              stateLabel = t.btStateUnknown;
              hint = t.devicesBluetoothUnknown;
          }
        }

        final List<Widget> lines = [
          Text(
            stateLabel,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ];
        if (hint.isNotEmpty) {
          lines.add(const SizedBox(height: 4));
          lines.add(
            Text(
              hint,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          );
        }
        if (_scanError != null) {
          lines.add(const SizedBox(height: 6));
          lines.add(
            Text(
              '${t.devicesScanError}: $_scanError',
              style: const TextStyle(color: Colors.orange, fontSize: 12),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: lines,
        );
      },
    );
  }

  Widget _buildWebUnavailableCard() {
    final isDe = ProgramLangController.instance.lang == ProgramLang.de;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bluetooth_disabled, size: 40, color: AppColors.textSecondary),
          const SizedBox(height: 12),
          Text(
            isDe
                ? 'Bluetooth ist in der Web-Version nicht verfügbar.'
                : 'Bluetooth is not available in the web version.',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isDe
                ? 'Bitte verwende die Android- oder iOS-App, um Cure-Geräte zu verbinden.'
                : 'Please use the Android or iOS app to connect Cure devices.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
        ],
      ),
    );
  }

  void _scheduleNoDeviceHelper() {
    if (_noDeviceHelpShown) return;
    Future.delayed(const Duration(seconds: 4), () async {
      if (!mounted || _noDeviceHelpShown || _hasFoundDevices) return;
      _noDeviceHelpShown = true;
      await _guidedOpenLocationSettings();
    });
  }

  Widget _buildPermissionCard(bool isDe) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isDe
                ? 'Standort/Bluetooth-Berechtigung erforderlich'
                : 'Location/Bluetooth permission required',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isDe
                ? 'Damit Cure-Geräte gefunden werden können, müssen der Standortdienst und die App-Berechtigung aktiviert sein. Bitte erlaube den Zugriff während der Nutzung der App.'
                : 'To find Cure devices, location services and app permission must be enabled. Please allow access while using the app.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton(
                onPressed: _requestBlePermissions,
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                child: Text(isDe ? 'Berechtigung erlauben' : 'Allow permission'),
              ),
              if (_locationServiceEnabled == false)
                OutlinedButton(
                  onPressed: _guidedOpenLocationSettings,
                  child: Text(isDe ? 'Standort aktivieren' : 'Enable location'),
                ),
              OutlinedButton(
                onPressed: _openAppSettings,
                child: Text(isDe ? 'App-Einstellungen öffnen' : 'Open app settings'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Restyled device row: cleaner card, prominent name, small secondary id, single action button
  Widget _buildDeviceRow(BluetoothDevice d) {
    return StreamBuilder<BluetoothConnectionState>(
      stream: _ble.deviceState(d),
      builder: (context, snap) {
        final state = snap.data ?? BluetoothConnectionState.disconnected;
        final connected = state == BluetoothConnectionState.connected;

        final deviceId = d.remoteId.toString();
        final rawBattery = _ble.batteryRawByDeviceId[deviceId];

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            title: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: connected ? Colors.green : Colors.blue,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _shortDeviceLabel(d.platformName, deviceId),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (rawBattery != null) ...[
                  const SizedBox(width: 6),
                  _buildBatteryWidget(rawBattery)!,
                ],
              ],
            ),
            trailing: connected
                ? ElevatedButton(
                    onPressed: () {
                      _ble.disconnect(d);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                    child: Text(
                      AppLocalizations.of(context)!.devicesDisconnect,
                    ),
                  )
                : ElevatedButton(
                    onPressed: () {
                      _ble.connect(d);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                    ),
                    child: Text(AppLocalizations.of(context)!.devicesConnect),
                  ),
          ),
        );
      },
    );
  }

  Widget _buildDeveloperPanel(String deviceId) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: AppColors.cardBackground,
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent, // no inner divider line
        ),
        child: ExpansionTile(
          initiallyExpanded: _devExpanded,
          onExpansionChanged: (v) {
            setState(() => _devExpanded = v);
          },
          title: Text(
            'Developer / Native Tools',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          children: [
            const SizedBox(height: 8),

            // Native Unlock Tests
            Text(
              'Native Unlock Tests',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 8),
            NativeUnlockTester.buildTestUI(context, deviceId),

            const SizedBox(height: 12),

            // Native Debug Panel (progStart/progClear/status etc.)
            _NativeDebugPanel(deviceId: deviceId),

            const SizedBox(height: 12),

            // Developer test buttons (Upload/Start/Clear/Unlock/Reactive test)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.cardBackground,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                    ),
                    onPressed: () async {
                      try {
                        final svc = CureDeviceUnlockService.instance;

                        final connected =
                            await FlutterBluePlus.connectedDevices;
                        if (connected.isEmpty)
                          throw Exception('No connected device');
                        final String did = connected.first.remoteId.toString();

                        if (!(svc.isNativeConnected &&
                            svc.nativeConnectedDeviceId == did)) {
                          await svc.nativeConnect(did);
                        }

                        final programModel = buildSimpleTestProgram();
                        final program = CureProgramCompiler().compile(
                          programModel,
                        );
                        final ok = await svc.uploadProgramBytes(program);

                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                ok
                                    ? 'Testprogramm übertragen (ohne Start)'
                                    : 'Upload FAILED (kein OK)',
                              ),
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Upload failed: ${e.toString()}'),
                            ),
                          );
                        }
                      }
                    },
                    child: const Text('Testprogramm hochladen'),
                  ),
                  const SizedBox(height: 8),

                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                    ),
                    onPressed: () async {
                      try {
                        final did = await _getConnectedDeviceIdOrThrow();
                        await _ensureNativeConnected(did);

                        final svc = CureDeviceUnlockService.instance;
                        final ok = await svc.progStart();

                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                ok
                                    ? 'Programm gestartet'
                                    : 'Start fehlgeschlagen (kein OK)',
                              ),
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Start failed: ${e.toString()}'),
                            ),
                          );
                        }
                      }
                    },
                    child: const Text('Programm starten'),
                  ),
                  const SizedBox(height: 8),

                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                    ),
                    onPressed: () async {
                      try {
                        final did = await _getConnectedDeviceIdOrThrow();
                        await _ensureNativeConnected(did);

                        final svc = CureDeviceUnlockService.instance;
                        final ok = await svc.progClear();

                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                ok
                                    ? 'progClear OK'
                                    : 'progClear FAILED (kein OK)',
                              ),
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'progClear failed: ${e.toString()}',
                              ),
                            ),
                          );
                        }
                      }
                    },
                    child: const Text('progClear testen'),
                  ),
                  const SizedBox(height: 8),

                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                    ),
                    onPressed: _unlockInProgressLocal
                        ? null
                        : () async {
                            if (!mounted) return;
                            try {
                              final connected =
                                  await FlutterBluePlus.connectedDevices;
                              final has = connected.any((d) {
                                final n = (d.platformName ?? '').toLowerCase();
                                final id =
                                    (d.remoteId.str ?? d.remoteId.toString())
                                        .toLowerCase();
                                return isCureDevice(n) || isCureDevice(id);
                              });

                              if (!has) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Keine CureBase verbunden'),
                                    ),
                                  );
                                }
                                return;
                              }

                              final device = connected.firstWhere((d) {
                                final n = (d.platformName ?? '').toLowerCase();
                                final id =
                                    (d.remoteId.str ?? d.remoteId.toString())
                                        .toLowerCase();
                                return isCureDevice(n) || isCureDevice(id);
                              });

                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Unlock gestartet...'),
                                  ),
                                );
                              }

                              final result = await CureDeviceUnlockService
                                  .instance
                                  .unlockDevice(
                                    device.remoteId.toString(),
                                    onStatus: (s) => debugPrint(
                                      'HBDBG ensureUnlocked status: $s',
                                    ),
                                  );

                              if (result.success) {
                                // Persist device id for auto-reconnect
                                AppMemory.instance.setLastDevice(
                                  device.remoteId.toString(),
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Unlock OK')),
                                  );
                                }
                              } else {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Unlock failed: ${result.errorMessage}',
                                      ),
                                    ),
                                  );
                                }
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Unlock failed: ${e.toString()}',
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                    child: const Text('Unlock'),
                  ),
                  const SizedBox(height: 8),

                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                    ),
                    onPressed: () async {
                      try {
                        final connected =
                            await FlutterBluePlus.connectedDevices;
                        final has = connected.any((d) {
                          final n = (d.platformName ?? '').toLowerCase();
                          final id = (d.remoteId.str ?? d.remoteId.toString())
                              .toLowerCase();
                          return isCureDevice(n) || isCureDevice(id);
                        });

                        if (!has) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Keine CureBase verbunden'),
                              ),
                            );
                          }
                          return;
                        }

                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Reactive BLE Unlock-Test gestartet',
                              ),
                            ),
                          );
                        }

                        // ReactiveBleCureTest removed (flutter_reactive_ble removed).
                        // iOS/Android now use native CureBleNativePlugin; keep this button disabled
                        // or implement native test call via CureDeviceUnlockService if needed.
                        debugPrint(
                          'Reactive BLE Unlock-Test disabled (reactive_ble removed)',
                        );
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Reactive BLE Test failed: ${e.toString()}',
                              ),
                            ),
                          );
                        }
                      }
                    },
                    child: const Text('ReactiveBLE Unlock-Test'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Explanation: Shorten visible device labels. Update _shortDeviceLabel to also shorten platformName when it contains a technical suffix (prefix-tail),
  // keeping internal device ids unchanged. Minimal UI-only change.

  String _shortDeviceLabel(String? platformName, String? deviceId) {
    bool looksLikeRawId(String s) {
      // MAC address: XX:XX:XX:XX:XX:XX
      if (RegExp(r'^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$').hasMatch(s)) return true;
      // UUID-style remoteId: XXXXXXXX-XXXX-...
      if (RegExp(r'^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-').hasMatch(s)) return true;
      return false;
    }

    String shortenFriendly(String s) {
      if (s.contains('-')) {
        final parts = s.split('-');
        if (parts.length >= 2) {
          final prefix = parts[0];
          final tail = parts[1].replaceAll(':', '').replaceAll(' ', '');
          final tailShort = tail.length > 4 ? tail.substring(0, 4) : tail;
          return '$prefix-$tailShort...';
        }
      }
      return s;
    }

    String friendlyFallback() {
      if (deviceId != null && _ble.batteryRawByDeviceId.containsKey(deviceId)) {
        return 'CureClip';
      }
      return 'CureBase';
    }

    // Use platformName only when it is non-empty and not a raw address/UUID
    if (platformName != null && platformName.isNotEmpty && !looksLikeRawId(platformName)) {
      final shortened = shortenFriendly(platformName);
      if (deviceId != null && deviceId.isNotEmpty) {
        _cachedFriendlyNames[deviceId] = shortened;
      }
      return shortened;
    }

    // Cache populated from a previous scan where a friendly name was available
    if (deviceId != null && deviceId.isNotEmpty) {
      final cached = _cachedFriendlyNames[deviceId];
      if (cached != null && cached.isNotEmpty) return cached;
    }

    // Never show a raw MAC or remoteId — use a generic friendly label
    return friendlyFallback();
  }

  Widget? _buildBatteryWidget(int? raw) {
    if (raw == null) return null;
    final bool charging = raw >= 100;
    final int pct = charging ? raw - 100 : raw;
    final IconData icon = charging
        ? Icons.battery_charging_full
        : (pct >= 60 ? Icons.battery_full : (pct >= 20 ? Icons.battery_4_bar : Icons.battery_alert));
    final Color color = charging ? Colors.greenAccent : (pct >= 20 ? AppColors.textSecondary : Colors.orange);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 2),
        Text('$pct%', style: TextStyle(fontSize: 11, color: color)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bottomPad = media.padding.bottom + 12;

    if (kIsWeb) {
      return GradientBackground(
        child: SafeArea(
          bottom: true,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _buildWebUnavailableCard(),
          ),
        ),
      );
    }

    return GradientBackground(
      child: SafeArea(
        bottom: true,
        child: Padding(
          padding: EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 0),
          child: SingleChildScrollView(
            padding: EdgeInsets.only(bottom: bottomPad),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // NOTE: main title is provided by the app shell — avoid duplicate in-page title
                const SizedBox(height: 8),

                // Permission / location guidance card (Android only)
                if (Platform.isAndroid)
                  StreamBuilder<BluetoothAdapterState>(
                    stream: FlutterBluePlus.adapterState,
                    builder: (context, snap) {
                      final isDe = ProgramLangController.instance.lang == ProgramLang.de;
                      final isUnauthorized = snap.data == BluetoothAdapterState.unauthorized;
                      final locationMissing = _locationServiceEnabled == false;
                      if (!isUnauthorized && !locationMissing) return const SizedBox.shrink();
                      return _buildPermissionCard(isDe);
                    },
                  ),

                // Devices + Current Device Card + Developer collapse
                StreamBuilder<List<BluetoothDevice>>(
                  stream: _devicesStream,
                  builder: (context, snap) {
                    final rawDevices = snap.data ?? [];
                    if (rawDevices.isNotEmpty) _hasFoundDevices = true;

                    // Sort: connected CureBase device always first
                    final connId = _ble.connectedDeviceId;
                    final devices = List<BluetoothDevice>.from(rawDevices);
                    if (connId != null) {
                      devices.sort((a, b) {
                        final aConn = a.remoteId.toString() == connId ? 0 : 1;
                        final bConn = b.remoteId.toString() == connId ? 0 : 1;
                        return aConn.compareTo(bConn);
                      });
                    }

                    final String? deviceId = devices.isNotEmpty
                        ? devices.first.remoteId.toString()
                        : null;

                    // Determine if any device in the list is actually connected
                    final bool hasConnected =
                        connId != null &&
                        devices.any((d) => d.remoteId.toString() == connId);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Current device summary card (styled like Settings cards)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.cardBackground,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                AppLocalizations.of(context)!.devicesCureDevice,
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),

                              // Adapter state + connection summary (moved into this card for cleaner layout)
                              _adapterStateWidget(),
                              const SizedBox(height: 10),

                              if (hasConnected)
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _shortDeviceLabel(
                                        devices.first.platformName,
                                        connId,
                                      ),
                                      style: TextStyle(
                                        color: Colors.green,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                  ],
                                )
                              else
                                Text(
                                  AppLocalizations.of(
                                    context,
                                  )!.devicesNoDeviceConnected,
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              const SizedBox(height: 8),

                              if (devices.isEmpty)
                                Text(
                                  AppLocalizations.of(context)!.devicesTipScan,
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                  ),
                                )
                              else
                                Text(
                                  AppLocalizations.of(
                                    context,
                                  )!.devicesFoundCount(devices.length),
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                  ),
                                ),

                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: _isScanningLocal
                                          ? null
                                          : () async {
                                              if (mounted) {
                                                setState(() {
                                                  _scanError = null;
                                                  _isScanningLocal = true;
                                                });
                                              }
                                              try {
                                                await _ble.stopScan();
                                                await _checkLocationAndScan();
                                                _scheduleNoDeviceHelper();
                                              } catch (e) {
                                                final msg = e.toString();
                                                if (context.mounted) {
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    SnackBar(
                                                      content: Text(
                                                        '${AppLocalizations.of(context)!.devicesScanFailed}: $msg',
                                                      ),
                                                    ),
                                                  );
                                                }
                                                if (mounted) {
                                                  setState(() {
                                                    _scanError = msg;
                                                  });
                                                }
                                                if (kDebugMode) {
                                                  debugPrint(
                                                    'Scan action failed: $e',
                                                  );
                                                }
                                              } finally {
                                                if (mounted) {
                                                  setState(() {
                                                    _isScanningLocal = false;
                                                  });
                                                }
                                              }
                                            },
                                      icon: const Icon(Icons.search),
                                      label: Text(
                                        AppLocalizations.of(
                                          context,
                                        )!.devicesScan,
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.primary,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 12),

                        if (devices.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 18),
                            child: Center(
                              child: Text(
                                AppLocalizations.of(
                                  context,
                                )!.devicesNoDevicesDiscovered,
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                          )
                        else ...[
                          for (final d in devices) _buildDeviceRow(d),
                          const SizedBox(height: 12),

                          // Developer/native tools are only visible in debug builds
                          if (kDebugMode && deviceId != null)
                            _buildDeveloperPanel(deviceId!),
                        ],
                      ],
                    );
                  },
                ),

                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NativeDebugPanel extends StatelessWidget {
  const _NativeDebugPanel({super.key, required this.deviceId});

  final String deviceId;

  @override
  Widget build(BuildContext context) {
    final svc = CureDeviceUnlockService.instance;

    final infoLines = <String>[
      'Device ID: $deviceId',
      'Native connected: ${svc.isNativeConnected} (${svc.nativeConnectedDeviceId ?? "-"})',
      'Hardware: ${svc.hardwareInfo?.trim().isNotEmpty == true ? svc.hardwareInfo : "-"}',
      'Build: ${svc.buildInfo?.trim().isNotEmpty == true ? svc.buildInfo : "-"}',
      'Supports Remote Programs: ${svc.supportsRemotePrograms}',
    ];

    Future<void> _ensureNativeConnected() async {
      if (svc.isNativeConnected && svc.nativeConnectedDeviceId == deviceId)
        return;
      await svc.nativeConnect(deviceId);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Native Debug Info',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 8),
        for (final line in infoLines)
          Text(
            line,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
        const SizedBox(height: 12),
        Text(
          'Programmstatus Aktionen',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.spaceEvenly,
          spacing: 8,
          runSpacing: 8,
          children: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                minimumSize: const Size(140, 40),
              ),
              onPressed: () async {
                try {
                  await _ensureNativeConnected();
                  final ok = await svc.progStart();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          ok
                              ? 'Programm gestartet'
                              : 'Start fehlgeschlagen (kein OK)',
                        ),
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Start failed: ${e.toString()}')),
                    );
                  }
                }
              },
              child: const Text('Start Program'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                minimumSize: const Size(140, 40),
              ),
              onPressed: () async {
                try {
                  await _ensureNativeConnected();
                  final ok = await svc.progClear();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          ok ? 'progClear OK' : 'progClear FAILED (kein OK)',
                        ),
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('progClear failed: ${e.toString()}'),
                      ),
                    );
                  }
                }
              },
              child: const Text('progClear'),
            ),
            ElevatedButton(
              onPressed: () async {
                final svc = CureDeviceUnlockService.instance;

                if (kCureTransportMode == CureTransportMode.native) {
                  try {
                    await _ensureNativeConnected();

                    final uuid16 = Uint8List.fromList(
                      List.generate(16, (i) => i + 1),
                    );
                    final name = "Test 1kHz 60s";
                    final eIntensity = 5;
                    final hIntensity = 3;
                    final eWaveForm = 0x00;
                    final hWaveForm = 0x02;
                    final steps = [(freqHz: 1000.0, dwellSec: 60)];

                    final programBytes = encodeQtProgramBytes(
                      uuid16: uuid16,
                      name: name,
                      eIntensity0to10: eIntensity,
                      hIntensity0to10: hIntensity,
                      eWaveForm: eWaveForm,
                      hWaveForm: hWaveForm,
                      steps: steps,
                    );

                    await svc.uploadProgramBytes(programBytes);
                    await svc.progStart();

                    for (int i = 0; i < 3; i++) {
                      final status = await svc.fetchProgStatus();
                      debugPrint(
                        'Prog Status: ${status?.rawLine ?? status.toString()}',
                      );
                      await Future.delayed(const Duration(milliseconds: 500));
                    }

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Program uploaded and started successfully',
                        ),
                      ),
                    );
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: ${e.toString()}')),
                    );
                  }
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Native mode not enabled')),
                  );
                }
              },
              child: const Text('DEBUG: Minimal Program Start'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                minimumSize: const Size(140, 40),
              ),
              onPressed: () async {
                try {
                  await _ensureNativeConnected();

                  final svc = CureDeviceUnlockService.instance;
                  final program = buildSimpleTestProgram();
                  final success = await svc.uploadProgramAndStart(program);
                  if (success) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Program uploaded and started successfully',
                        ),
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Failed to upload and start program'),
                      ),
                    );
                  }
                } catch (e) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              },
              child: const Text('Upload+Start Test 1 kHz/60s'),
            ),
          ],
        ),
      ],
    );
  }
}
