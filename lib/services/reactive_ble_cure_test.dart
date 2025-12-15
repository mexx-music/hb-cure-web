import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:convert/convert.dart';
import 'package:pointycastle/export.dart' as pc;

class ReactiveBleCureTest {
  ReactiveBleCureTest._();
  static final ReactiveBleCureTest instance = ReactiveBleCureTest._();

  final _ble = FlutterReactiveBle();

  // UART UUIDs
  final _serviceUuid = Uuid.parse("6e400001-b5a3-f393-e0a9-e50e24dcca9e");
  final _rxUuid = Uuid.parse("6e400002-b5a3-f393-e0a9-e50e24dcca9e"); // write
  final _txUuid = Uuid.parse("6e400003-b5a3-f393-e0a9-e50e24dcca9e"); // notify

  final _privateKeyHex =
      "E40783F681A5BB852CAB1E106B6641EFB43C1923C1EBE25CA36865CDFAB06548";

  StreamSubscription<DiscoveredDevice>? _scanSub;
  StreamSubscription<ConnectionStateUpdate>? _connSub;
  StreamSubscription<List<int>>? _notifySub;
  QualifiedCharacteristic? _writeChar;

  void _log(String msg) {
    if (kDebugMode) debugPrint('RBLE[TEST] $msg');
  }

  /// Startet einen Scan und führt automatisch das Unlock-Test-Szenario aus,
  /// wenn ein Gerät mit Namen "CureBase" gefunden wird.
  Future<void> startUnlockTest() async {
    // Stop previous scan if any
    try {
      await _scanSub?.cancel();
    } catch (_) {}
    _scanSub = null;

    _log('startUnlockTest: scanning...');

    _scanSub = _ble.scanForDevices(
      withServices: const [],
      scanMode: ScanMode.lowLatency,
    ).listen((device) async {
      try {
        final name = device.name ?? '';
        _log('discovered id=${device.id} name="${name}" rssi=${device.rssi}');

        if (name.toLowerCase().contains('curebase')) {
          _log('found CureCube: ${device.id} – connecting...');
          try {
            await _scanSub?.cancel();
          } catch (_) {}
          _scanSub = null;

          await _connectAndRunUnlockTest(device);
        }
      } catch (e, st) {
        _log('scan callback error: $e');
        if (kDebugMode) debugPrint(st.toString());
      }
    }, onError: (e) {
      _log('scan error: $e');
    });
  }

  Future<void> stopScan() async {
    try {
      await _scanSub?.cancel();
    } catch (_) {}
    _scanSub = null;
  }

  Future<void> _connectAndRunUnlockTest(DiscoveredDevice device) async {
    final id = device.id;
    _log('connectToDevice $id...');

    try {
      // Listen for connection updates once
      _connSub = _ble.connectToDevice(id: id, connectionTimeout: const Duration(seconds: 10)).listen(
        (update) async {
          _log('conn state=${update.connectionState}');
          if (update.connectionState == DeviceConnectionState.connected) {
            // cancel connection subscription here; we'll manage lifecycle inside
            try {
              await _connSub?.cancel();
            } catch (_) {}
            _connSub = null;

            // proceed
            await _runUnlockFlowAfterConnected(id);
          }
        },
        onError: (e) {
          _log('connect stream error: $e');
        },
        cancelOnError: true,
      );
    } catch (e) {
      _log('connectToDevice failed: $e');
    }
  }

  Future<void> _runUnlockFlowAfterConnected(String deviceId) async {
    try {
      _log('discovering services...');
      final services = await _ble.discoverServices(deviceId);
      _log('discovered ${services.length} services');

      QualifiedCharacteristic? writeChar;
      QualifiedCharacteristic? notifyChar;

      for (final s in services) {
        if (s.serviceId == _serviceUuid) {
          for (final c in s.characteristics) {
            if (c.characteristicId == _rxUuid) {
              writeChar = QualifiedCharacteristic(
                serviceId: _serviceUuid,
                characteristicId: _rxUuid,
                deviceId: deviceId,
              );
            }
            if (c.characteristicId == _txUuid) {
              notifyChar = QualifiedCharacteristic(
                serviceId: _serviceUuid,
                characteristicId: _txUuid,
                deviceId: deviceId,
              );
            }
          }
        }
      }

      if (writeChar == null) {
        _log('UART service/Write char not found');
        // clean up connection subscription (acts as disconnect)
        try {
          await _connSub?.cancel();
        } catch (_) {}
        _connSub = null;
        return;
      }

      if (notifyChar == null) {
        _log('UART notify char not found – will proceed without notify subscription');
      } else {
        // subscribe to notify
        try {
          await _notifySub?.cancel();
        } catch (_) {}
        _notifySub = _ble.subscribeToCharacteristic(notifyChar).listen((data) {
          try {
            final line = ascii.decode(data).trim();
            _log('NOTIFY: "${line}"');
          } catch (e) {
            _log('notify decode error: $e');
          }
        }, onError: (e) {
          _log('notify stream error: $e');
        });
      }

      // Send challenge
      final cmd = 'challenge\r\n';
      _log('writing challenge');
      try {
        await _ble.writeCharacteristicWithResponse(writeChar, value: ascii.encode(cmd));
        _log('wrote: $cmd');
      } catch (e) {
        _log('write challenge failed: $e');
      }

      // wait for replies
      await Future.delayed(const Duration(seconds: 5));

      // cleanup
      try {
        await _notifySub?.cancel();
      } catch (_) {}
      _notifySub = null;

      try {
        await _connSub?.cancel();
      } catch (_) {}
      _connSub = null;

      _log('unlock test finished');
    } catch (e, st) {
      _log('unlock flow error: $e');
      if (kDebugMode) debugPrint(st.toString());
      try {
        await _notifySub?.cancel();
      } catch (_) {}
      _notifySub = null;
      try {
        await _connSub?.cancel();
      } catch (_) {}
      _connSub = null;
    }
  }

  Future<void> _writeLine(String line) async {
    if (_writeChar == null) return;
    final payload = Uint8List.fromList("$line\r\n".codeUnits);
    _log("RBLE: write '${line}' (${payload.length} bytes) withResponse=true");
    await _ble.writeCharacteristicWithResponse(
      _writeChar!,
      value: payload,
    );
  }

  Future<void> sendResponseForChallenge(String challengeHex) async {
    if (_writeChar == null) return;

    final challenge = Uint8List.fromList(hex.decode(challengeHex));
    final sig = await _signSecp256k1Raw(challenge, _privateKeyHex);
    final sigHex = hex.encode(sig);
    _log("RBLE: sigHex=$sigHex");

    await _writeLine("response=$sigHex");
  }

  Future<Uint8List> _signSecp256k1Raw(
      Uint8List challenge32, String privateKeyHex) async {
    final hexKey = privateKeyHex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    final d = BigInt.parse(hexKey, radix: 16);
    final domain = pc.ECDomainParameters('secp256k1');
    final privParams =
        pc.PrivateKeyParameter<pc.ECPrivateKey>(pc.ECPrivateKey(d, domain));
    final signer = pc.Signer('SHA-256/DET-ECDSA');
    signer.init(true, privParams);
    final sig = signer.generateSignature(challenge32) as pc.ECSignature;
    final rBytes = _bigIntToFixedLength(sig.r, 32);
    final sBytes = _bigIntToFixedLength(sig.s, 32);
    return Uint8List.fromList([...rBytes, ...sBytes]);
  }

  Uint8List _bigIntToFixedLength(BigInt v, int length) {
    final mask = (BigInt.one << (length * 8)) - BigInt.one;
    final truncated = v & mask;
    final hexStr = truncated.toRadixString(16).padLeft(length * 2, '0');
    return Uint8List.fromList(hex.decode(hexStr));
  }
}
