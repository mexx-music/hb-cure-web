// lib/services/cure_ble_transport_fbp.dart

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'cure_ble_transport.dart';

/// Thin adapter that wraps existing flutter_blue_plus objects into the
/// CureBleTransport interface. This is a lightweight preparatory adapter
/// and does not change existing BleCureDeviceService/CureProtocol logic.
class CureBleTransportFbp implements CureBleTransport {
  CureBleTransportFbp({
    required this.device,
    required this.writeChar,
    required this.notifyChar,
  }) {
    _notifyCtrl = StreamController<String>.broadcast();
    // attach notify listener if notifyChar available
    if (notifyChar != null) {
      notifyChar!.value.listen((bytes) {
        try {
          final s = utf8.decode(bytes).trim();
          _notifyCtrl.add(s);
        } catch (e) {
          if (kDebugMode) debugPrint('CureBleTransportFbp: notify decode failed: $e');
        }
      });
    }
  }

  @override
  final BluetoothDevice device;
  final BluetoothCharacteristic writeChar;
  @override
  final BluetoothCharacteristic? notifyChar;

  late final StreamController<String> _notifyCtrl;

  @override
  String get id => 'fbp';

  @override
  Stream<String> get notifyLines => _notifyCtrl.stream;

  @override
  Future<void> connect(String deviceId) async {
    // TODO: integrate with existing BleCureDeviceService - for now throw to signal not used.
    throw UnimplementedError('CureBleTransportFbp.connect should be integrated with BleCureDeviceService');
  }

  @override
  Future<void> disconnect() async {
    // nothing here - higher layer manages device lifecycle
    return;
  }

  @override
  Future<void> writeLine(String line) async {
    final payload = Uint8List.fromList(utf8.encode(line + '\r\n'));
    // naive write; higher-level code (CureProtocol) will implement write semantics
    await writeChar.write(payload, withoutResponse: true);
  }

  @override
  Future<List<String>> sendCommandAndWaitLines(String line, {Duration timeout = const Duration(seconds: 30)}) async {
    // Default stub: write and then gather notifyLines until OK/ERROR or timeout.
    await writeLine(line);
    final completer = Completer<List<String>>();
    final collected = <String>[];
    late StreamSubscription<String> sub;
    sub = notifyLines.listen((ln) {
      collected.add(ln);
      final t = ln.trim().toUpperCase();
      if (t == 'OK' || t == 'ERROR') {
        completer.complete(List<String>.from(collected));
        sub.cancel();
      }
    }, onError: (e) {
      if (!completer.isCompleted) completer.completeError(e);
    });
    Future.delayed(timeout, () {
      if (!completer.isCompleted) {
        sub.cancel();
        completer.completeError(TimeoutException('timeout waiting for OK/ERROR'));
      }
    });
    return completer.future;
  }
}

