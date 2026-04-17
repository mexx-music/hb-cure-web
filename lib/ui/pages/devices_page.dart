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
  StreamSubscription<bool>? _unlockSub;
  bool _unlockInProgressLocal = false;

  // UI-only: Unlock result per deviceId (null=unknown, true=OK, false=failed)
  final Map<String, bool?> _unlockOkById = {};

  // UI-only: Unlock running per deviceId
  final Set<String> _unlockBusyById = {};

  // UI-only: remember expansion state
  bool _devExpanded = false;

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
      await _checkLocationAndScan();
    });
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
      final result = await _nativeCh.invokeMethod<bool>('isLocationServiceEnabled');
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
    if (svc.isNativeConnected && svc.nativeConnectedDeviceId == deviceId) return;
    await svc.nativeConnect(deviceId);
  }
  // ----------------------------------------------------------

  Widget _buildDeviceRow(BluetoothDevice d) {
    return StreamBuilder<BluetoothConnectionState>(
      stream: _ble.deviceState(d),
      builder: (context, snap) {
        final state = snap.data ?? BluetoothConnectionState.disconnected;
        final connected = state == BluetoothConnectionState.connected;

        final deviceId = d.remoteId.toString();
        final unlockOk = _unlockOkById[deviceId]; // null/true/false
        final unlockBusy = _unlockBusyById.contains(deviceId);

        // bolt color: orange while running, green if ok, red otherwise (unknown/fail)
        final Color boltColor = unlockBusy
            ? Colors.orange
            : (unlockOk == true
            ? Colors.green
            : (unlockOk == false ? Colors.red : Colors.red));

        // blue even when disabled
        final ButtonStyle connectedBlueStyle = ButtonStyle(
          backgroundColor: MaterialStateProperty.resolveWith((states) => Colors.blue),
          foregroundColor: MaterialStateProperty.all(Colors.white),
          padding: MaterialStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        );

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Builder(builder: (ctx) {
                      final deviceName =
                      (d.platformName != null && d.platformName.isNotEmpty)
                          ? d.platformName
                          : d.remoteId.toString();
                      return Text(
                        deviceName,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    }),
                    const SizedBox(height: 6),
                    Text(
                      'ID: ${d.remoteId}',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (connected) ...[
                ElevatedButton(
                  style: connectedBlueStyle,
                  onPressed: null,
                  child: Text(AppLocalizations.of(context)!.devicesConnected),
                ),
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _unlockOkById[deviceId] = null;
                          _unlockBusyById.remove(deviceId);
                        });
                        _ble.disconnect(d);
                      },
                      child: Text(AppLocalizations.of(context)!.devicesDisconnect),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: 'Native Unlock Test',
                      icon: Icon(Icons.bolt, color: boltColor),
                      onPressed: unlockBusy
                          ? null
                          : () async {
                        setState(() {
                          _unlockBusyById.add(deviceId);
                          _unlockOkById[deviceId] = null;
                        });

                        try {
                          await NativeUnlockTester.instance
                              .testNativeUnlock(deviceId);

                          if (!mounted) return;
                          setState(() {
                            _unlockOkById[deviceId] = true;
                          });
                        } catch (e) {
                          if (!mounted) return;
                          setState(() {
                            _unlockOkById[deviceId] = false;
                          });
                          if (kDebugMode) {
                            debugPrint(
                                'Native unlock test failed for $deviceId: $e');
                          }
                        } finally {
                          if (!mounted) return;
                          setState(() {
                            _unlockBusyById.remove(deviceId);
                          });
                        }
                      },
                    ),
                  ],
                ),
              ] else ...[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                      ),
                      onPressed: () {
                        setState(() {
                          _unlockOkById[deviceId] = null;
                          _unlockBusyById.remove(deviceId);
                        });
                        _ble.connect(d);
                      },
                      child: Text(AppLocalizations.of(context)!.devicesConnect),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: 'Native Unlock Test',
                      icon: Icon(Icons.bolt, color: boltColor),
                      onPressed: unlockBusy
                          ? null
                          : () async {
                        setState(() {
                          _unlockBusyById.add(deviceId);
                          _unlockOkById[deviceId] = null;
                        });

                        try {
                          await NativeUnlockTester.instance
                              .testNativeUnlock(deviceId);

                          if (!mounted) return;
                          setState(() {
                            _unlockOkById[deviceId] = true;
                          });
                        } catch (e) {
                          if (!mounted) return;
                          setState(() {
                            _unlockOkById[deviceId] = false;
                          });
                          if (kDebugMode) {
                            debugPrint(
                                'Native unlock test failed for $deviceId: $e');
                          }
                        } finally {
                          if (!mounted) return;
                          setState(() {
                            _unlockBusyById.remove(deviceId);
                          });
                        }
                      },
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildDeveloperPanel(String deviceId) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
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

                        final connected = await FlutterBluePlus.connectedDevices;
                        if (connected.isEmpty) throw Exception('No connected device');
                        final String did = connected.first.remoteId.toString();

                        if (!(svc.isNativeConnected && svc.nativeConnectedDeviceId == did)) {
                          await svc.nativeConnect(did);
                        }

                        final programModel = buildSimpleTestProgram();
                        final program = CureProgramCompiler().compile(programModel);
                        final ok = await svc.uploadProgramBytes(program);

                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                ok ? 'Testprogramm übertragen (ohne Start)' : 'Upload FAILED (kein OK)',
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
                              content: Text(ok ? 'Programm gestartet' : 'Start fehlgeschlagen (kein OK)'),
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
                              content: Text(ok ? 'progClear OK' : 'progClear FAILED (kein OK)'),
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
                        final connected = await FlutterBluePlus.connectedDevices;
                        final has = connected.any((d) {
                          final n = (d.platformName ?? '').toLowerCase();
                          final id = (d.remoteId.str ?? d.remoteId.toString()).toLowerCase();
                          return n.contains('curebase') || id.contains('curebase');
                        });

                        if (!has) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Keine CureBase verbunden')),
                            );
                          }
                          return;
                        }

                        final device = connected.firstWhere((d) {
                          final n = (d.platformName ?? '').toLowerCase();
                          final id = (d.remoteId.str ?? d.remoteId.toString()).toLowerCase();
                          return n.contains('curebase') || id.contains('curebase');
                        });

                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Unlock gestartet...')),
                          );
                        }

                        final result = await CureDeviceUnlockService.instance.unlockDevice(
                          device.remoteId.toString(),
                          onStatus: (s) => debugPrint('HBDBG ensureUnlocked status: $s'),
                        );

                        if (result.success) {
                          // Persist device id for auto-reconnect
                          AppMemory.instance.setLastDevice(device.remoteId.toString());
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Unlock OK')),
                            );
                          }
                        } else {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Unlock failed: ${result.errorMessage}')),
                            );
                          }
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Unlock failed: ${e.toString()}')),
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
                        final connected = await FlutterBluePlus.connectedDevices;
                        final has = connected.any((d) {
                          final n = (d.platformName ?? '').toLowerCase();
                          final id = (d.remoteId.str ?? d.remoteId.toString()).toLowerCase();
                          return n.contains('curebase') || id.contains('curebase');
                        });

                        if (!has) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Keine CureBase verbunden')),
                            );
                          }
                          return;
                        }

                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Reactive BLE Unlock-Test gestartet')),
                          );
                        }

                        // ReactiveBleCureTest removed (flutter_reactive_ble removed).
                        // iOS/Android now use native CureBleNativePlugin; keep this button disabled
                        // or implement native test call via CureDeviceUnlockService if needed.
                        debugPrint('Reactive BLE Unlock-Test disabled (reactive_ble removed)');
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Reactive BLE Test failed: ${e.toString()}')),
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

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bottomPad = media.padding.bottom + 12;

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
                // Header + Scan-Button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.devicesTitle,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(color: AppColors.textPrimary),
                    ),
                    ElevatedButton.icon(
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
                        } catch (e) {
                          final msg = e.toString();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('${AppLocalizations.of(context)!.devicesScanFailed}: $msg')),
                            );
                          }
                          if (mounted) {
                            setState(() {
                              _scanError = msg;
                            });
                          }
                          if (kDebugMode) {
                            debugPrint('Scan action failed: $e');
                          }
                        } finally {
                          if (mounted) {
                            setState(() {
                              _isScanningLocal = false;
                            });
                          }
                        }
                      },
                      icon: const Icon(Icons.refresh),
                      label: Text(AppLocalizations.of(context)!.devicesScan),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                if (_isScanningLocal)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 6),
                    child: Row(
                      children: [
                        CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          AppLocalizations.of(context)!.devicesScanning,
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),

                // Bluetooth adapter state diagnostic
                StreamBuilder<BluetoothAdapterState>(
                  stream: FlutterBluePlus.adapterState,
                  builder: (context, snap) {
                    final t = AppLocalizations.of(context)!;
                    final state = snap.data;
                    final String stateLabel;
                    String hint = '';
                    if (state == null) {
                      stateLabel = t.btStateUnknown;
                    } else {
                      switch (state) {
                        case BluetoothAdapterState.on:
                          stateLabel = t.btStateOn;
                        case BluetoothAdapterState.off:
                          stateLabel = t.btStateOff;
                          hint = t.devicesBluetoothOff;
                        case BluetoothAdapterState.unauthorized:
                          stateLabel = t.btStateUnauthorized;
                          hint = t.devicesBluetoothUnauthorized;
                        case BluetoothAdapterState.turningOn:
                          stateLabel = t.btStateTurningOn;
                        case BluetoothAdapterState.turningOff:
                          stateLabel = t.btStateTurningOff;
                        default:
                          stateLabel = t.btStateUnknown;
                          hint = t.devicesBluetoothUnknown;
                      }
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${t.devicesAdapter}: $stateLabel',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                        if (hint.isNotEmpty)
                          Text(
                            hint,
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        if (_scanError != null)
                          Text(
                            '${t.devicesScanError}: $_scanError',
                            style: const TextStyle(
                              color: Colors.orange,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 8),
                Text(
                  AppLocalizations.of(context)!.devicesAvailableDevices,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),

                // Devices + Current Device Card + Developer collapse
                StreamBuilder<List<BluetoothDevice>>(
                  stream: _devicesStream,
                  builder: (context, snap) {
                    final rawDevices = snap.data ?? [];

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

                    final String? deviceId =
                    devices.isNotEmpty ? devices.first.remoteId.toString() : null;

                    // Determine if any device in the list is actually connected
                    final bool hasConnected = connId != null &&
                        devices.any((d) => d.remoteId.toString() == connId);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Current device summary card
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
                              if (hasConnected)
                                Text(
                                  '${AppLocalizations.of(context)!.devicesConnected}: $connId',
                                  style: TextStyle(
                                    color: Colors.green,
                                    fontWeight: FontWeight.w600,
                                  ),
                                )
                              else
                                Text(
                                  AppLocalizations.of(context)!.devicesNoDeviceConnected,
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              const SizedBox(height: 6),
                              if (devices.isEmpty)
                                Text(
                                  AppLocalizations.of(context)!.devicesTipScan,
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                  ),
                                )
                              else
                                Text(
                                  AppLocalizations.of(context)!.devicesFoundCount(devices.length),
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                  ),
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
                                AppLocalizations.of(context)!.devicesNoDevicesDiscovered,
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                          )
                        else ...[
                          for (final d in devices) _buildDeviceRow(d),
                          const SizedBox(height: 12),

                          // Collapsible developer/native block (restored)
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
  const _NativeDebugPanel({
    super.key,
    required this.deviceId,
  });

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
      if (svc.isNativeConnected && svc.nativeConnectedDeviceId == deviceId) return;
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
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                minimumSize: const Size(140, 40),
              ),
              onPressed: () async {
                try {
                  await _ensureNativeConnected();
                  final ok = await svc.progStart();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(ok ? 'Programm gestartet' : 'Start fehlgeschlagen (kein OK)'),
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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                minimumSize: const Size(140, 40),
              ),
              onPressed: () async {
                try {
                  await _ensureNativeConnected();
                  final ok = await svc.progClear();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(ok ? 'progClear OK' : 'progClear FAILED (kein OK)'),
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('progClear failed: ${e.toString()}')),
                    );
                  }
                }
              },
              child: const Text('progClear'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                minimumSize: const Size(140, 40),
              ),
              onPressed: () async {
                try {
                  final st = await svc.fetchProgStatus(timeout: const Duration(seconds: 5));
                  final msg = (st == null)
                      ? 'progStatus: (no data)'
                      : 'progStatus: ${st.rawLine ?? st.toString()}';
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('progStatus failed: $e')),
                    );
                  }
                }
              },
              child: const Text('Prog Status'),
            ),
            ElevatedButton(
              onPressed: () async {
                final svc = CureDeviceUnlockService.instance;

                if (kCureTransportMode == CureTransportMode.native) {
                  try {
                    await _ensureNativeConnected();

                    final uuid16 = Uint8List.fromList(List.generate(16, (i) => i + 1));
                    final name = "Test 1kHz 60s";
                    final eIntensity = 5;
                    final hIntensity = 3;
                    final eWaveForm = 0x00;
                    final hWaveForm = 0x02;
                    final steps = [
                      (freqHz: 1000.0, dwellSec: 60),
                    ];

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
                      debugPrint('Prog Status: ${status?.rawLine ?? status.toString()}');
                      await Future.delayed(const Duration(milliseconds: 500));
                    }

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Program uploaded and started successfully')),
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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                      const SnackBar(content: Text('Program uploaded and started successfully')),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Failed to upload and start program')),
                    );
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
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
