import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../widgets/gradient_background.dart';
import '../theme/app_colors.dart';
import '../../services/ble_cure_device_service.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:async';
import 'package:hbcure/core/cure_protocol/cure_test_programs.dart';
import 'package:hbcure/services/native_unlock_test.dart';
import 'package:hbcure/services/cure_device_unlock_service.dart';
import 'package:hbcure/services/reactive_ble_cure_test.dart';
import 'package:hbcure/core/cure_protocol/cure_program_compiler.dart';
import 'package:hbcure/core/config/cure_transport_mode.dart';
import 'package:hbcure/services/qt_remote_program_encoder.dart';

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
      try {
        await _ble.startScan();
      } catch (e) {
        if (kDebugMode) debugPrint('Initial auto-scan failed: $e');
        if (mounted) {
          setState(() {
            _scanError = e.toString();
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _ble.stopScan();
    _bleErrorSub?.cancel();
    _unlockSub?.cancel();
    super.dispose();
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
                    // Prefer platformName (newer API), fallback to name then id.str
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
                Text(
                  'Connected',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                // Disconnect button + NativeUnlockTester Smoke-Test
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () => _ble.disconnect(d),
                      child: const Text('Disconnect'),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: 'Native Unlock Test',
                      icon: const Icon(Icons.bolt),
                      onPressed: () async {
                        final deviceId = d.remoteId.toString();
                        try {
                          await NativeUnlockTester.instance
                              .testNativeUnlock(deviceId);
                        } catch (e) {
                          if (kDebugMode) {
                            debugPrint(
                                'Native unlock test failed for $deviceId: $e');
                          }
                        }
                      },
                    ),
                  ],
                ),
              ] else ...[
                // Connect button + NativeUnlockTester Smoke-Test
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                      ),
                      onPressed: () => _ble.connect(d),
                      child: const Text('Connect'),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: 'Native Unlock Test',
                      icon: const Icon(Icons.bolt),
                      onPressed: () async {
                        final deviceId = d.remoteId.toString();
                        try {
                          await NativeUnlockTester.instance
                              .testNativeUnlock(deviceId);
                        } catch (e) {
                          if (kDebugMode) {
                            debugPrint(
                                'Native unlock test failed for $deviceId: $e');
                          }
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
                      'Devices',
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
                          await _ble.startScan();
                        } catch (e) {
                          final msg = e.toString();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Scan failed: $msg'),
                              ),
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
                      label: const Text('Scan'),
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
                          'Scanning...',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),

                // Bluetooth adapter state diagnostic
                StreamBuilder<BluetoothAdapterState>(
                  stream: FlutterBluePlus.adapterState,
                  builder: (context, snap) {
                    final stateStr =
                    snap.hasData ? snap.data.toString() : 'unknown';
                    String hint = '';
                    if (snap.hasData) {
                      final s = stateStr.toLowerCase();
                      if (s.contains('off')) {
                        hint = 'Bluetooth ist deaktiviert. Bitte einschalten.';
                      } else if (s.contains('unauthorized')) {
                        hint =
                        'Bluetooth Berechtigung verweigert. Einstellungen → Bluetooth prüfen.';
                      } else if (s.contains('unknown')) {
                        hint = 'Bluetooth Status unbekannt.';
                      }
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Adapter: $stateStr',
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
                            'Scan error: $_scanError',
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
                  'Available Cure Devices',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),

                // Devices + Current Device Card + optional DebugPanel
                StreamBuilder<List<BluetoothDevice>>(
                  stream: _devicesStream,
                  builder: (context, snap) {
                    final devices = snap.data ?? [];

                    // Prepare a deviceId variable for downstream debug panels
                    final String? deviceId =
                    devices.isNotEmpty ? devices.first.remoteId.toString() : null;

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
                                'Cure Device',
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'No device connected',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              if (devices.isEmpty)
                                Text(
                                  'Tip: Press Scan to look for CureBase devices',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                  ),
                                )
                              else
                                Text(
                                  '${devices.length} device(s) found',
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
                                'No CureBase devices discovered',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                          )
                        else ...[
                          // Liste von Device Cards (kein ListView mehr!)
                          for (final d in devices) _buildDeviceRow(d),

                          const SizedBox(height: 16),

                          Card(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            color: AppColors.cardBackground,
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Native Unlock Tests',
                                    style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  NativeUnlockTester.buildTestUI(
                                    context,
                                    deviceId!,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // NEW: Small debug panel showing native unlock info and progStatus controls
                          Card(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            color: AppColors.cardBackground,
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: _NativeDebugPanel(
                                deviceId: deviceId!,
                              ),
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),

                const SizedBox(height: 12),

                // Developer test buttons: immer sichtbar, unabhängig von Devices
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
                      // Testprogramm hochladen (NATIVE / shared)
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                        ),
                        onPressed: () async {
                          try {
                            final svc = CureDeviceUnlockService.instance;

                            // Resolve a connected device at runtime (avoid using local 'devices' here)
                            final connected = await FlutterBluePlus.connectedDevices;
                            if (connected.isEmpty) throw Exception('No connected device');
                            final String deviceId = connected.first.remoteId.toString();

                            // ensure native shared connection
                            if (!(svc.isNativeConnected && svc.nativeConnectedDeviceId == deviceId)) {
                              await svc.nativeConnect(deviceId);
                            }

                            // build and compile test program to bytes
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

                      // Programm starten (NATIVE / shared)
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                        ),
                        onPressed: () async {
                          try {
                            final deviceId = await _getConnectedDeviceIdOrThrow();
                            await _ensureNativeConnected(deviceId);

                            final svc = CureDeviceUnlockService.instance;
                            final ok = await svc.progStart();

                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    ok ? 'Programm gestartet' : 'Start fehlgeschlagen (kein OK)',
                                  ),
                                ),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Start failed: ${e.toString()}',
                                  ),
                                ),
                              );
                            }
                          }
                        },
                        child: const Text('Programm starten'),
                      ),
                      const SizedBox(height: 8),

                      // progClear testen (NATIVE / shared)
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                        ),
                        onPressed: () async {
                          try {
                            final deviceId = await _getConnectedDeviceIdOrThrow();
                            await _ensureNativeConnected(deviceId);

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

                      // Unlock via Native Unlock Service
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
                              final n =
                              (d.platformName ?? '').toLowerCase();
                              final id = (d.remoteId.str ??
                                  d.remoteId.toString())
                                  .toLowerCase();
                              return n.contains('curebase') ||
                                  id.contains('curebase');
                            });
                            if (!has) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(
                                  const SnackBar(
                                    content:
                                    Text('Keine CureBase verbunden'),
                                  ),
                                );
                              }
                              return;
                            }
                            final device = connected.firstWhere((d) {
                              final n =
                              (d.platformName ?? '').toLowerCase();
                              final id = (d.remoteId.str ??
                                  d.remoteId.toString())
                                  .toLowerCase();
                              return n.contains('curebase') ||
                                  id.contains('curebase');
                            });

                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Unlock gestartet...'),
                                ),
                              );
                            }

                            final result =
                            await CureDeviceUnlockService.instance
                                .unlockDevice(
                              device.remoteId.toString(),
                              onStatus: (s) => debugPrint(
                                'HBDBG ensureUnlocked status: $s',
                              ),
                            );

                            if (result.success) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(
                                  const SnackBar(
                                    content: Text('Unlock OK'),
                                  ),
                                );
                              }
                            } else {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(
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

                      // Reactive BLE Unlock-Test
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                        ),
                        onPressed: () async {
                          try {
                            final connected =
                            await FlutterBluePlus.connectedDevices;
                            final has = connected.any((d) {
                              final n =
                              (d.platformName ?? '').toLowerCase();
                              final id =
                              (d.remoteId.str ?? d.remoteId.toString())
                                  .toLowerCase();
                              return n.contains('curebase') ||
                                  id.contains('curebase');
                            });
                            if (!has) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content:
                                    Text('Keine CureBase verbunden'),
                                  ),
                                );
                              }
                              return;
                            }
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'Reactive BLE Unlock-Test gestartet'),
                                ),
                              );
                            }
                            ReactiveBleCureTest.instance.startUnlockTest();
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

    // Hardware- und Build-Informationen als Textzeilen
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
            // Button: progStart (native/shared)
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
                      SnackBar(
                        content: Text('Start failed: ${e.toString()}'),
                      ),
                    );
                  }
                }
              },
              child: const Text('Start Program'),
            ),

            const SizedBox(height: 8),

            // Button: progClear (native/shared)
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
                      SnackBar(
                        content: Text('progClear failed: ${e.toString()}'),
                      ),
                    );
                  }
                }
              },
              child: const Text('progClear'),
            ),


            // Button: Prog Status
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                minimumSize: const Size(140, 40),
              ),
              onPressed: () async {
                try {
                  final svc = CureDeviceUnlockService.instance;
                  final st = await svc.fetchProgStatus(timeout: const Duration(seconds: 5));
                  final msg = (st == null) ? 'progStatus: (no data)' : 'progStatus: ${st.rawLine ?? st.toString()}';
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('progStatus failed: $e')));
                  }
                }
              },
              child: const Text('Prog Status'),
            ),

            // DEBUG: Minimal Program Start
            ElevatedButton(
              onPressed: () async {
                final svc = CureDeviceUnlockService.instance;

                if (kCureTransportMode == CureTransportMode.native) {
                  try {
                    await _ensureNativeConnected();

                    // Example program
                    final uuid16 = Uint8List.fromList(List.generate(16, (i) => i + 1));
                    final name = "Test 1kHz 60s";
                    final eIntensity = 5;
                    final hIntensity = 3;
                    final eWaveForm = 0x00; // sine
                    final hWaveForm = 0x02; // rectangular
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

                    // Optional: Poll progStatus
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

            // NEW: Upload+Start Testprogramm (1 kHz, 60s)
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
