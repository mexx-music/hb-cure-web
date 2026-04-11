// Minimal BLE helper service for scanning and connecting to "CureBase" devices.
// This file intentionally keeps logic small and defensive: it wraps flutter_blue_plus
// and exposes streams and simple connect/disconnect operations.

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter/services.dart';
import 'package:pointycastle/export.dart' as pc;
import 'package:convert/convert.dart';

import 'package:hbcure/core/cure_protocol/cure_program_compiler.dart';
import 'package:hbcure/core/cure_protocol/cure_program_model.dart';
import 'package:hbcure/services/cure_protocol.dart';
import 'package:hbcure/services/cure_device_unlock_service.dart';
import 'package:hbcure/core/config/cure_transport_mode.dart';
import 'cure_ble_transport_native.dart';

// UUIDs for CureBase (Nordic UART-like)
final Guid cureUartServiceUuid =
Guid('6e400001-b5a3-f393-e0a9-e50e24dcca9e');
final Guid cureUartRxCharUuid =
Guid('6e400002-b5a3-f393-e0a9-e50e24dcca9e'); // write (RX)
final Guid cureUartTxCharUuid =
Guid('6e400003-b5a3-f393-e0a9-e50e24dcca9e'); // notify (TX)

class _CureChars {
  final BluetoothCharacteristic writeChar;
  final BluetoothCharacteristic? notifyChar;
  _CureChars(this.writeChar, this.notifyChar);
}

Future<_CureChars> _findCureCharacteristics(BluetoothDevice device) async {
  final services = await device.discoverServices();
  BluetoothCharacteristic? writeChar;
  BluetoothCharacteristic? notifyChar;
  for (final s in services) {
    if (s.uuid == cureUartServiceUuid) {
      for (final c in s.characteristics) {
        if (c.uuid == cureUartRxCharUuid) writeChar = c;
        if (c.uuid == cureUartTxCharUuid) notifyChar = c;
      }
    }
  }
  if (writeChar == null) {
    throw Exception('CureBase write characteristic not found');
  }
  return _CureChars(writeChar, notifyChar);
}

class BleCureDeviceService {
  static final BleCureDeviceService instance = BleCureDeviceService._internal();

  final Map<String, CureProtocol> _protocolByDeviceId = {};
  // Native unlock service helper (delegation target in native transport mode)
  final CureDeviceUnlockService _native = CureDeviceUnlockService.instance;
  // Optional: track currently connected device id for native transport usage
  String? _connectedDeviceId;
  // Merkt sich das vom UI ausgewählte Gerät im native-Mode
  BluetoothDevice? _selectedDevice;

  BleCureDeviceService._internal();

  StreamController<List<BluetoothDevice>>? _devicesCtrl;
  StreamController<String?>? _errorCtrl;
  StreamSubscription<List<ScanResult>>? _scanSub;
  final Map<String, BluetoothDevice> _found = {};
  bool _isScanning = false;

  bool _isUnlocked = false;
  bool get isUnlocked => _isUnlocked;
  int? _activeKeyIndex;

  // Candidate private keys list (hex).
  // *** WICHTIG: Kandidat 0 ist jetzt der echte private_key_CureApp ***
  static const List<String> _candidatePrivateKeysHex = <String>[
    // private_key_CureApp[32] aus C-Code:
    // {0xE4, 0x07, 0x83, 0xF6, 0x81, 0xA5, 0xBB, 0x85,
    //  0x2C, 0xAB, 0x1E, 0x10, 0x6B, 0x66, 0x41, 0xEF,
    //  0xB4, 0x3C, 0x19, 0x23, 0xC1, 0xEB, 0xE2, 0x5C,
    //  0xA3, 0x68, 0x65, 0xCD, 0xFA, 0xB0, 0x65, 0x48};
    'E40783F681A5BB852CAB1E106B6641EFB43C1923C1EBE25CA36865CDFAB06548',

    // Restliche Kandidaten Platzhalter (optional später mit echten Keys befüllen)
    '0000000000000000000000000000000000000000000000000000000000000000',
    '0000000000000000000000000000000000000000000000000000000000000000',
    '0000000000000000000000000000000000000000000000000000000000000000',
    '0000000000000000000000000000000000000000000000000000000000000000',
    '0000000000000000000000000000000000000000000000000000000000000000',
    '0000000000000000000000000000000000000000000000000000000000000000',
    '0000000000000000000000000000000000000000000000000000000000000000',
    '0000000000000000000000000000000000000000000000000000000000000000',
    '0000000000000000000000000000000000000000000000000000000000000000',
    '0000000000000000000000000000000000000000000000000000000000000000',
    '0000000000000000000000000000000000000000000000000000000000000000',
    '0000000000000000000000000000000000000000000000000000000000000000',
    '0000000000000000000000000000000000000000000000000000000000000000',
    '0000000000000000000000000000000000000000000000000000000000000000',
    '0000000000000000000000000000000000000000000000000000000000000000',
    '0000000000000000000000000000000000000000000000000000000000000000',
    '0000000000000000000000000000000000000000000000000000000000000000',
  ];

  // Guard: track whether an unlock is in progress per device to avoid parallel unlock attempts
  final Map<String, bool> _unlockInProgressByDeviceId = {};

  // Completers per device to allow callers to await ongoing unlock
  final Map<String, Completer<void>> _unlockCompleterByDeviceId = {};

  // simple global flag indicating an unlock operation is running (UI-friendly)
  bool _unlockInProgress = false;
  bool get unlockInProgress => _unlockInProgress;

  // unlock progress stream so UI can disable buttons while unlocking
  StreamController<bool>? _unlockCtrl;
  Stream<bool> get unlockStream {
    _unlockCtrl ??= StreamController<bool>.broadcast();
    return _unlockCtrl!.stream;
  }

  // Helper to update unlock progress state and notify listeners
  void _setUnlockInProgress(bool v) {
    _unlockInProgress = v;
    try {
      _unlockCtrl?.add(v);
    } catch (_) {}
  }

  // Map to track ongoing unlock operations that return a boolean result per device
  // This prevents starting multiple unlock flows for the same device concurrently.
  final Map<String, Completer<bool>> _unlockInProgressFutureByDeviceId = {};

  // Helper to require the CureProtocol instance for a connected device
  CureProtocol _requireCureProtocolFor(BluetoothDevice device) {
    final id = device.remoteId.toString();
    final proto = _protocolByDeviceId[id];
    if (proto == null) {
      throw Exception(
          'CureProtocol not initialized for device $id – connect() must succeed first');
    }
    return proto;
  }

  // --------- Scan API --------------------------------------------------------
  Stream<List<BluetoothDevice>> scanForCureDevices() {
    _devicesCtrl ??=
    StreamController<List<BluetoothDevice>>.broadcast();
    _errorCtrl ??= StreamController<String?>.broadcast();
    Future.microtask(
            () => _devicesCtrl?.add(_found.values.toList()));
    return _devicesCtrl!.stream;
  }

  Stream<String?> get errorStream {
    _errorCtrl ??= StreamController<String?>.broadcast();
    return _errorCtrl!.stream;
  }

    Future<void> startScan() async {
    if (_isScanning) return;
    _found.clear();
    _devicesCtrl?.add([]);

    final supported = await FlutterBluePlus.isSupported;
    if (!supported) throw Exception('BLE not supported on this platform');

    _isScanning = true;

    // Ensure native central is powered on when using native transport
    if (kCureTransportMode == CureTransportMode.native) {
      // Only perform native central wait on iOS — Android plugin may not implement getCentralState
      if (Platform.isIOS) {
       try {
         if (kDebugMode) debugPrint('HBDBG startScan: waiting for native central poweredOn...');
         await CureBleTransportNative().waitForCentralPoweredOn();
         if (kDebugMode) debugPrint('HBDBG startScan: native central poweredOn, proceeding to scan');
       } catch (e) {
         // If the native transport did not report poweredOn in time, log and
         // DO NOT call FlutterBluePlus.startScan() because CoreBluetooth may be
         // in an unknown state and startScan would fail with CBManagerStateUnknown.
         final msg = 'Scan blocked: native central not powered on (wait timed out): $e';
         _errorCtrl?.add(msg);
         if (kDebugMode) debugPrint('HBDBG startScan: $msg');
         // Stop scanning attempt and return early to avoid dual scan paths.
         _isScanning = false;
         return;
       }
      } else {
        if (kDebugMode) debugPrint('HBDBG startScan: skipping native central wait on non-iOS platform');
      }
     }

    await FlutterBluePlus.startScan();
    if (kDebugMode) debugPrint('HBDBG startScan: flutterBluePlus.startScan invoked');

    // Log discovered peripherals in detail to aid debugging when iOS scanning
    // appears to miss devices (compare with nRF Connect behavior).
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final sr in results) {
        final advName = sr.advertisementData.advName ?? '';
        final name = (sr.device.name).isNotEmpty ? sr.device.name : advName;
        final id = sr.device.id.id;
        final rssi = sr.rssi;
        if (kDebugMode) debugPrint('HBDBG scanResult: name="$name" advName="$advName" id=$id rssi=$rssi');
        final combined = (name + ' ' + id).toLowerCase();
        if (kDebugMode) {
          // In debug builds accept all discovered devices to test whether the
          // original filter was too narrow (only 'curebase'). In release builds
          // keep the original filter logic.
          _found[id] = sr.device;
        } else {
          if (combined.contains('curebase')) {
            _found[id] = sr.device;
          }
        }
        if (kDebugMode) {
          debugPrint('HBDBG scanFilter: accepted id=$id name="$name" advName="$advName" combined="$combined"');
        }
      }
      _devicesCtrl?.add(_found.values.toList());
    }, onError: (e, st) {
      _errorCtrl?.add(e?.toString());
    });
    }

  Future<void> stopScan() async {
    if (!_isScanning) return;
    try {
      await _scanSub?.cancel();
    } catch (_) {}
    _scanSub = null;
    try {
      FlutterBluePlus.stopScan();
    } catch (_) {}
    _isScanning = false;
  }

  // --------- Connect / Disconnect -------------------------------------------
  Future<void> connect(BluetoothDevice device) async {
    // Gerät immer merken – unabhängig vom Modus
    _selectedDevice = device;

    // Merke die deviceId für native transport mode
    _connectedDeviceId = device.remoteId.toString();

    // Scan immer stoppen, wenn wir ein Gerät "ausgewählt" haben
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}

    // --- NEU: Single-BLE-Owner-Logik im native-Mode -----------------------
    if (kCureTransportMode == CureTransportMode.native) {
      if (kDebugMode) {
        debugPrint(
          'HBDBG connect(native): selected CureBase device ${device.id.id} – '
          'delegating to native connect',
        );
      }
      // Delegiere an native Unlock-Service, damit _sharedDeviceId gesetzt wird
      await _native.nativeConnect(_connectedDeviceId!);
      return;
    }

    // --- Original-FBP-Verhalten (nur im flutterBluePlus-Mode) -------------
    try {
      await device.connect(license: License.free);
    } catch (e) {
      final isConnected = await device.connectionState.firstWhere(
        (s) => s == BluetoothConnectionState.connected,
        orElse: () => BluetoothConnectionState.disconnected,
      );
      if (isConnected != BluetoothConnectionState.connected) rethrow;
    }
    await Future.delayed(const Duration(milliseconds: 200));

    try {
      await device.discoverServices();
    } catch (_) {}

    try {
      final chars = await _findCureCharacteristics(device);

      final proto = CureProtocol(
        device: device,
        txCharacteristic: chars.writeChar,
        rxCharacteristic: chars.notifyChar ?? chars.writeChar,
      );
      _protocolByDeviceId[device.remoteId.toString()] = proto;

      try {
        await proto.ensureNotify();
      } catch (e) {
        if (kDebugMode) {
          debugPrint('HBDBG connect: proto.ensureNotify failed: $e');
        }
      }

      if (kDebugMode) {
        debugPrint('HBDBG connect: CureProtocol created for device ${device.id.id}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('HBDBG connect: no Cure UART service found: $e');
      }
    }
  }

  Future<void> disconnect(BluetoothDevice device) async {
    final deviceId = device.remoteId.toString();

    final proto = _protocolByDeviceId.remove(deviceId);
    if (proto != null) {
      if (kDebugMode) {
        debugPrint('HBDBG disconnect: disposing CureProtocol for device $deviceId');
      }
      try {
        await proto.dispose();
      } catch (_) {}
    }

    // Native-Mode: delegiere an native Unlock-Service und aufräumen
    if (kCureTransportMode == CureTransportMode.native) {
      // Wenn das native transport die gleiche DeviceId verwaltet, trenne dort
      try {
        await _native.nativeDisconnect();
      } catch (_) {}
      _connectedDeviceId = null;
      if (_selectedDevice?.remoteId.toString() == deviceId) {
        _selectedDevice = null;
      }
      if (kDebugMode) {
        debugPrint(
          'HBDBG disconnect(native): delegated to native disconnect for $deviceId',
        );
      }
      return;
    }

    // flutterBluePlus-Mode: Originalverhalten
    try {
      await device.disconnect();
    } catch (_) {}
  }

  Stream<BluetoothConnectionState> deviceState(
      BluetoothDevice device) =>
      device.connectionState;

  // --------- High-level CureProtocol-based APIs -----------------------------

  Future<void> uploadProgram(CureProgram program) async {
    if (kCureTransportMode == CureTransportMode.native) {
      throw Exception(
        'uploadProgram via native transport is not implemented yet (Single-BLE-Owner mode focuses on unlock).',
      );
    }

    final device = await _findConnectedCureDeviceOrThrow();

    // Ensure device unlocked before attempting upload
    final unlocked = await ensureUnlockedForCurrentDevice();
    if (!unlocked) {
      if (kDebugMode) debugPrint('HBDBG uploadProgram: unlock check failed; aborting');
      throw Exception('Device not unlocked');
    }

    final cureProto =
    _protocolByDeviceId[device.remoteId.toString()];
    if (cureProto == null) {
      throw Exception(
          'CureProtocol instance not found for device ${device.id.id}');
    }

    if (!_isUnlocked) {
      if (kDebugMode) {
        debugPrint(
            'HBDBG uploadProgram: device not unlocked; aborting upload');
      }
      throw Exception('Device not unlocked');
    }

    final bytes = CureProgramCompiler().compile(program);
    if (kDebugMode) {
      debugPrint(
          'HBDBG uploadProgram: start compiledLength=${bytes.length}');
    }
    final ok = await cureProto.uploadProgram(bytes);
    if (!ok) throw Exception('uploadProgram failed');
  }

  Future<void> startProgram() async {
    if (kCureTransportMode == CureTransportMode.native) {
      throw Exception(
        'startProgram via native transport is not implemented yet (Single-BLE-Owner mode focuses on unlock).',
      );
    }

    final device = await _findConnectedCureDeviceOrThrow();

    // Ensure device unlocked before attempting to start program
    final unlocked = await ensureUnlockedForCurrentDevice();
    if (!unlocked) {
      if (kDebugMode) debugPrint('HBDBG startProgram: unlock check failed; aborting');
      throw Exception('Device not unlocked');
    }

    final cureProto =
        _protocolByDeviceId[device.remoteId.toString()] ??
            (throw Exception(
                'CureProtocol instance not found for device ${device.id.id}'));
    final ok = await cureProto.startProgram();
    if (!ok) throw Exception('startProgram failed');
  }

  /// Public convenience wrapper that ensures the currently connected Cure device
  /// is unlocked. This is a thin wrapper that delegates to the existing
  /// `ensureUnlocked({bool force = false})` implementation and returns a bool.
  ///
  /// Use this method where callers don't have a BluetoothDevice instance
  /// available and just want to ensure the active/connected device is unlocked.
  Future<bool> ensureUnlockedForCurrentDevice({bool force = false}) async {
    try {
      final device = await _findConnectedCureDeviceOrThrow();
      final deviceId = device.remoteId.toString();

      // Fast-Path: already unlocked for this session
      if (!force && _isUnlocked) {
        if (kDebugMode) debugPrint('HBDBG ensureUnlockedForCurrentDevice: already unlocked for $deviceId');
        return true;
      }

      // Mark in-progress state
      _setUnlockInProgress(true);

      try {
        final result = await CureDeviceUnlockService.instance.unlockDevice(
          deviceId,
          onStatus: (s) {
            if (kDebugMode) {
              debugPrint('[BleCureDeviceService] unlock status: $s');
            }
          },
        );

        if (result.success) {
          _isUnlocked = true;
          if (kDebugMode) {
            debugPrint('HBDBG ensureUnlockedForCurrentDevice: unlocked OK for $deviceId');
          }
          return true;
        } else {
          _isUnlocked = false;
          if (kDebugMode) {
            debugPrint('HBDBG ensureUnlockedForCurrentDevice: unlock failed for $deviceId: ${result.errorMessage}');
          }
          return false;
        }
      } catch (e) {
        _isUnlocked = false;
        if (kDebugMode) {
          debugPrint('HBDBG ensureUnlockedForCurrentDevice: unexpected error: $e');
        }
        return false;
      } finally {
        _setUnlockInProgress(false);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('HBDBG ensureUnlockedForCurrentDevice: no connected device or other error: $e');
      }
      return false;
    }
  }

  Future<void> sendProgClearOnly() async {
    if (kCureTransportMode == CureTransportMode.native) {
      throw Exception(
        'sendProgClearOnly via native transport is not implemented yet (Single-BLE-Owner mode focuses on unlock).',
      );
    }

    final device = await _findConnectedCureDeviceOrThrow();
    final cureProto =
        _protocolByDeviceId[device.remoteId.toString()] ??
            (throw Exception(
                'CureProtocol instance not found for device ${device.id.id}'));
    final ok = await cureProto.clearProgram();
    if (!ok) throw Exception('progClear failed');
  }

  // TODO(mexx): ensureUnlocked() vor dem Aufruf von _sendCommandAndReadLinesUntilOk/WaitOk prüfen, falls nötig.
  Future<List<String>>
  _sendCommandAndReadLinesUntilOk(
      BluetoothDevice device,
      BluetoothCharacteristic writeChar,
      BluetoothCharacteristic? notifyChar,
      String line, {
        Duration timeout = const Duration(seconds: 30),
      }) async {
    final cureProto =
        _protocolByDeviceId[device.remoteId.toString()] ??
            (throw Exception(
                'CureProtocol instance not found for device ${device.id.id}'));
    final resp =
    await cureProto.sendRawCommand(line, timeout: timeout);
    final parts = resp
        .split(RegExp(r"\r?\n"))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.isEmpty) return <String>[];
    final last = parts.last.toUpperCase();
    final collected = List<String>.from(parts);
    if (last == 'OK' || last == 'ERROR') collected.removeLast();
    return collected;
  }

  Future<void> _sendCommandAndWaitOk(
      BluetoothDevice device,
      BluetoothCharacteristic writeChar,
      BluetoothCharacteristic? notifyChar,
      String line, {
        Duration timeout = const Duration(seconds: 30),
      }) async {
    await _sendCommandAndReadLinesUntilOk(
        device, writeChar, notifyChar, line,
        timeout: timeout);
  }

  // --------- Unlock flow ----------------------------------------------------
  Future<bool> _tryUnlockWithKey(
      BluetoothDevice device,
      String privateKeyHex,
      int index,
      ) async {
    final cureProto =
        _protocolByDeviceId[device.remoteId.toString()] ??
            (throw Exception(
                'CureProtocol instance not found for device ${device.id.id}'));
    if (kDebugMode) {
      debugPrint(
          'HBDBG _tryUnlockWithKey: candidate $index – calling sendChallengeAndGetRandom');
    }
    try {
      List<int> challenge;
      try {
        challenge = await cureProto.sendChallengeAndGetRandom(
            timeout: const Duration(seconds: 5));
        if (kDebugMode) {
          debugPrint(
              'HBDBG _tryUnlockWithKey: candidate $index – got random[${challenge.length}] first8=${challenge.take(8).toList()}');
        }
      } on TimeoutException catch (e) {
        if (kDebugMode) {
          debugPrint(
              'HBDBG _tryUnlockWithKey: candidate $index – challenge TimeoutException: $e');
        }
        try {
          cureProto.resetState();
        } catch (_) {}
        await Future.delayed(
            const Duration(milliseconds: 200));
        return false;
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
              'HBDBG _tryUnlockWithKey: candidate $index – challenge failed: $e');
        }
        return false;
      }

      if (challenge.length != 32) {
        if (kDebugMode) {
          debugPrint(
              'HBDBG _tryUnlockWithKey: candidate $index – invalid challenge length ${challenge.length}');
        }
        return false;
      }

      if (kDebugMode) {
        debugPrint(
            'HBDBG _tryUnlockWithKey: candidate $index – creating signature');
      }

      final sig = await _signSecp256k1Raw(
        Uint8List.fromList(challenge),
        privateKeyHex,
      );

      if (kDebugMode) {
        debugPrint(
            'HBDBG _tryUnlockWithKey: candidate $index – sending response signature');
      }

      bool ok;
      try {
        ok = await cureProto.sendResponseSignature(
          sig,
          timeout: const Duration(seconds: 10),
        );
        if (kDebugMode) {
          debugPrint(
              'HBDBG _tryUnlockWithKey: candidate $index – response sent, ok=$ok');
        }
      } on TimeoutException catch (e) {
        if (kDebugMode) {
          debugPrint(
              'HBDBG _tryUnlockWithKey: candidate $index – response TimeoutException: $e');
        }
        try {
          cureProto.resetState();
        } catch (_) {}
        await Future.delayed(
            const Duration(milliseconds: 200));
        return false;
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
              'HBDBG _tryUnlockWithKey: candidate $index – response failed: $e');
        }
        return false;
      }

      return ok;
    } finally {
      // DO NOT dispose persistent proto here
    }
  }

  Future<void> ensureUnlocked(BluetoothDevice device) async {
    if (_isUnlocked) return;

    final deviceId = device.remoteId.toString();

    if (_unlockInProgressByDeviceId[deviceId] == true) {
      final existing = _unlockCompleterByDeviceId[deviceId];
      if (existing != null) {
        if (kDebugMode) {
          debugPrint(
              'HBDBG ensureUnlocked: unlock already in progress for $deviceId - awaiting existing');
        }
        try {
          await existing.future;
        } catch (_) {}
        if (_isUnlocked) return;
      } else {
        if (kDebugMode) {
          debugPrint(
              'HBDBG ensureUnlocked: unlock in progress but no completer for $deviceId; returning');
        }
        return;
      }
    }

    _unlockInProgressByDeviceId[deviceId] = true;
    final completer = Completer<void>();
    _unlockCompleterByDeviceId[deviceId] = completer;

    _setUnlockInProgress(true);
    try {
      final proto = _protocolByDeviceId[deviceId];
      if (proto == null) {
        if (kDebugMode) {
          debugPrint(
              'HBDBG ensureUnlocked: no CureProtocol instance for $deviceId; aborting unlock');
        }
        if (!completer.isCompleted) completer.complete();
        return;
      }

      try {
        proto.resetState();
      } catch (_) {}
      await Future.delayed(
          const Duration(milliseconds: 200));

      var success = false;
      for (var i = 0; i < _candidatePrivateKeysHex.length; i++) {
        final key = _candidatePrivateKeysHex[i];
        if (kDebugMode) {
          debugPrint(
              'HBDBG ensureUnlocked: trying candidate $i');
        }
        try {
          final ok = await _tryUnlockWithKey(device, key, i);
          if (ok) {
            _isUnlocked = true;
            _activeKeyIndex = i;
            if (kDebugMode) {
              debugPrint(
                  'HBDBG ensureUnlocked: unlocked with candidate index $i');
            }
            success = true;
            break;
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint(
                'HBDBG ensureUnlocked: candidate $i failed (caught): $e');
          }
          await Future.delayed(
              const Duration(milliseconds: 200));
          continue;
        }
      }

      if (!success) {
        if (kDebugMode) {
          debugPrint(
              'HBDBG ensureUnlocked: no candidate succeeded');
        }
        if (!completer.isCompleted) completer.complete();
        return;
      }

      if (!completer.isCompleted) completer.complete();
      return;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('HBDBG ensureUnlocked: unexpected error: $e');
      }
      if (!(_unlockCompleterByDeviceId[deviceId]
          ?.isCompleted ??
          true)) {
        _unlockCompleterByDeviceId[deviceId]?.complete();
      }
      return;
    } finally {
      _unlockInProgressByDeviceId[deviceId] = false;
      _unlockCompleterByDeviceId.remove(deviceId);
      _setUnlockInProgress(false);
    }
  }

  Future<BluetoothDevice> _findConnectedCureDeviceOrThrow() async {
    // Im native-Mode gibt es keine FBP-GATT-Connection – wir verwenden
    // das zuletzt ausgewählte Gerät (_selectedDevice) als Referenz.
    if (kCureTransportMode == CureTransportMode.native) {
      final d = _selectedDevice;
      if (d == null) {
        throw Exception('No selected CureBase device in native transport mode');
      }
      return d;
    }

    // flutterBluePlus-Mode: ursprüngliches Verhalten
    final connected = await FlutterBluePlus.connectedDevices;
    return connected.firstWhere(
      (d) {
        final n = (d.name).toLowerCase();
        final id = (d.id.id ?? d.id.toString()).toLowerCase();
        return n.contains('curebase') || id.contains('curebase');
      },
      orElse: () => throw Exception('No connected CureBase device found'),
    );
  }

  // --------- Crypto helper (sign with secp256k1) ----------------------------
  //
  // WICHTIG:
  // - challenge32 ist GENAU die 32-Byte-Challenge aus dem Gerät (kein extra Hash).
  // - Wir signieren challenge32 direkt mit ECDSA secp256k1.
  // - Die Signatur ist 64 Bytes r||s, kompatibel zum C++-Tool (uECC_verify(pub, challenge, 32, sig)).
  Future<Uint8List> _signSecp256k1Raw(
      Uint8List challenge32,
      String privateKeyHex,
      ) async {
    final hexKey =
    privateKeyHex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    if (challenge32.length != 32) {
      throw Exception(
          'Challenge must be exactly 32 bytes, got ${challenge32.length}');
    }
    if (hexKey.length != 64) {
      throw Exception(
          'Private key hex must be exactly 64 hex chars (32 bytes), got ${hexKey.length}');
    }

    final d = BigInt.parse(hexKey, radix: 16);
    final domain = pc.ECDomainParameters('secp256k1');
    final privParams = pc.PrivateKeyParameter<pc.ECPrivateKey>(
        pc.ECPrivateKey(d, domain));

    // deterministische ECDSA: wir behandeln challenge32 als bereits
    // "Hash" (wie uECC_sign das macht) und verwenden RFC 6979 für k.
    final pc.ECDSASigner baseSigner =
    pc.ECDSASigner(null, pc.HMac(pc.SHA256Digest(), 64));
    final pc.NormalizedECDSASigner signer =
    pc.NormalizedECDSASigner(baseSigner);

    signer.init(true, privParams);

    final pc.ECSignature sig =
    signer.generateSignature(challenge32) as pc.ECSignature;

    final rBytes = _bigIntToFixedLength(sig.r, 32);
    final sBytes = _bigIntToFixedLength(sig.s, 32);

    return Uint8List.fromList(<int>[...rBytes, ...sBytes]);
  }

  Uint8List _bigIntToFixedLength(BigInt v, int length) {
    final mask =
        (BigInt.one << (length * 8)) - BigInt.one;
    final truncated = v & mask;
    var hexStr =
    truncated.toRadixString(16).padLeft(length * 2, '0');
    return Uint8List.fromList(hex.decode(hexStr));
  }

  // --------- Program operations delegation for native transport -------------

  /// Delegate progClear to native transport when running in native mode.
  Future<bool> progClear() async {
    if (kCureTransportMode == CureTransportMode.native) {
      return await _native.progClear();
    }
    try {
      await sendProgClearOnly();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Delegate progStart to native transport when running in native mode.
  Future<bool> progStart() async {
    if (kCureTransportMode == CureTransportMode.native) {
      return await _native.progStart();
    }
    try {
      await startProgram();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Upload raw bytes (delegates to native transport in native mode)
  Future<bool> uploadProgramBytes(Uint8List bytes,
      {int chunkSize = 64}) async {
    if (kCureTransportMode == CureTransportMode.native) {
      return await _native.uploadProgramBytes(bytes, chunkSize: chunkSize);
    }

    // Fallback: use existing FBP-based upload (requires CureProtocol)
    final device = await _findConnectedCureDeviceOrThrow();
    final cureProto = _protocolByDeviceId[device.remoteId.toString()];
    if (cureProto == null) return false;
    try {
      final ok = await cureProto.uploadProgram(bytes);
      return ok;
    } catch (_) {
      return false;
    }
  }

  /// Fetch program status, delegate to native transport when configured.
  Future<CureProgStatus?> fetchProgStatus({Duration timeout = const Duration(seconds: 5)}) async {
    if (kCureTransportMode == CureTransportMode.native) {
      return await _native.fetchProgStatus(timeout: timeout);
    }

    try {
      final device = await _findConnectedCureDeviceOrThrow();
      final chars = await _findCureCharacteristics(device);
      final lines = await _sendCommandAndReadLinesUntilOk(
        device,
        chars.writeChar,
        chars.notifyChar,
        'progStatus',
        timeout: timeout,
      );
      final payload = lines
          .map((l) => l.trim())
          .firstWhere((l) => l.isNotEmpty && l.toUpperCase() != 'OK',
              orElse: () => '');
      if (payload.isEmpty) return null;
      final parts = payload.split(',');
      if (parts.length < 7) return null;
      final runningStr = parts[0].trim().toLowerCase();
      final pausedStr = parts[1].trim().toLowerCase();
      return CureProgStatus(
        running: runningStr == 'running' ||
            runningStr == '1' ||
            runningStr == 'true',
        paused: pausedStr == 'paused' || pausedStr == '1' || pausedStr == 'true',
        elapsedSec: int.tryParse(parts[2].trim()) ?? 0,
        totalSec: int.tryParse(parts[3].trim()) ?? 0,
        programIdHex: parts[4].trim(),
        pcHex: parts[5].trim(),
        waitTimeSec: double.tryParse(parts[6].trim()) ?? 0,
        rawLine: payload,
      );
    } catch (_) {
      return null;
    }
  }

// ------------------------------- End -------------------------------------
}
