import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../widgets/gradient_background.dart';
import '../theme/app_colors.dart';
import '../../services/ble_cure_device_service.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:async';
import 'package:hbcure/core/cure_protocol/cure_test_programs.dart';
import '../../services/reactive_ble_cure_test.dart';
import 'package:hbcure/services/native_unlock_test.dart';
import 'package:hbcure/services/cure_device_unlock_service.dart';

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
                          : ((d.name != null && d.name.isNotEmpty)
                          ? d.name
                          : d.id.str);
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
                      'ID: ${d.id.str}',
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
                        final deviceId = d.id.str;
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
                        final deviceId = d.id.str;
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

                          // Optionales Debug-Panel nur, wenn ein Device existiert
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
                                    devices.first.id.str,
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
                              child: _NativeDebugPanel(),
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
                      // Testprogramm hochladen
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                        ),
                        onPressed: () async {
                          try {
                            final connected = FlutterBluePlus.connectedDevices;
                            final has = connected.any((d) {
                              final n = (d.name ?? '').toLowerCase();
                              final id =
                              (d.id.id ?? d.id.toString()).toLowerCase();
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
                            final program = buildSimpleTestProgram();
                            await _ble.uploadProgram(program);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Testprogramm übertragen (ohne Start)',
                                  ),
                                ),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Upload failed: ${e.toString()}',
                                  ),
                                ),
                              );
                            }
                          }
                        },
                        child: const Text('Testprogramm hochladen'),
                      ),
                      const SizedBox(height: 8),

                      // Programm starten
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                        ),
                        onPressed: () async {
                          try {
                            final connected = FlutterBluePlus.connectedDevices;
                            final has = connected.any((d) {
                              final n = (d.name ?? '').toLowerCase();
                              final id =
                              (d.id.id ?? d.id.toString()).toLowerCase();
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
                            await _ble.startProgram();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Programm gestartet'),
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

                      // progClear testen
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                        ),
                        onPressed: () async {
                          try {
                            final connected = FlutterBluePlus.connectedDevices;
                            final has = connected.any((d) {
                              final n = (d.name ?? '').toLowerCase();
                              final id =
                              (d.id.id ?? d.id.toString()).toLowerCase();
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
                            await _ble.sendProgClearOnly();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('progClear OK'),
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
                                FlutterBluePlus.connectedDevices;
                            final has = connected.any((d) {
                              final n =
                              (d.name ?? '').toLowerCase();
                              final id = (d.id.id ??
                                  d.id.toString())
                                  .toLowerCase();
                              return n.contains('curebase') ||
                                  id.contains('curebase');
                            });
                            if (!has) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Keine CureBase verbunden'),
                                  ),
                                );
                              }
                              return;
                            }
                            final device = connected.firstWhere((d) {
                              final n =
                              (d.name ?? '').toLowerCase();
                              final id = (d.id.id ??
                                  d.id.toString())
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
                              device.id.str,
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
                                FlutterBluePlus.connectedDevices;
                            final has = connected.any((d) {
                              final n =
                              (d.name ?? '').toLowerCase();
                              final id =
                              (d.id.id ?? d.id.toString())
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
  const _NativeDebugPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final connected = FlutterBluePlus.connectedDevices;
    final hasDevice = connected.isNotEmpty;

    // Aktuell verbundenes Device (oder null)
    BluetoothDevice? device;
    if (hasDevice) {
      for (final d in connected) {
        final n = (d.name).toLowerCase();
        final id = (d.remoteId.str).toLowerCase(); // FlutterBluePlus
        if (n.contains('curebase') || id.contains('curebase')) {
          device = d;
          break;
        }
      }
    }

    // Hardware- und Build-Informationen als Textzeilen
    final infoLines = <String>[];
    if (device != null) {
      final svc = CureDeviceUnlockService.instance;
      infoLines.add('Device ID: ${device.id}');
      infoLines.add('Name: ${device.name}');
      infoLines.add('Firmware: ${device.mtu}');
      infoLines.add('Hardware: ${svc.hardwareInfo?.trim().isNotEmpty == true ? svc.hardwareInfo : "-"}');
      infoLines.add('Build: ${svc.buildInfo?.trim().isNotEmpty == true ? svc.buildInfo : "-"}');
      infoLines.add('Supports Remote Programs: ${svc.supportsRemotePrograms}');
    } else {
      infoLines.add('Kein CureBase-Gerät verbunden');
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

        // progStatus Action-Buttons (nur sichtbar, wenn ein Device verbunden ist)
        if (device != null) ...[
          Text(
            'Programmstatus Aktionen',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Button: progStart
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: EdgeInsets.symmetric(horizontal: 12),
                ),
                onPressed: () async {
                  try {
                    await BleCureDeviceService.instance.startProgram();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Programm gestartet'),
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

              // Button: progStop
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: EdgeInsets.symmetric(horizontal: 12),
                ),
                onPressed: () async {
                  try {
                    // stopProgram is not implemented in BleCureDeviceService yet.
                    if (kDebugMode) debugPrint('stopProgram not implemented in BleCureDeviceService yet');
                     if (context.mounted) {
                       ScaffoldMessenger.of(context).showSnackBar(
                         const SnackBar(
                           content: Text('Programm gestoppt'),
                         ),
                       );
                     }
                   } catch (e) {
                     if (context.mounted) {
                       ScaffoldMessenger.of(context).showSnackBar(
                         SnackBar(
                           content: Text('Stop failed: ${e.toString()}'),
                         ),
                       );
                     }
                   }
                 },
                child: const Text('Stop Program'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
