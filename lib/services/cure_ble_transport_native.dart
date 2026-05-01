// lib/services/cure_ble_transport_native.dart

import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart'; // for kDebugMode, debugPrint

import 'cure_ble_transport.dart';

/// Native MethodChannel/EventChannel based transport for CureBase.
class CureBleTransportNative implements CureBleTransport {
  static const MethodChannel _method =
      MethodChannel('cure_ble_native/methods');
  static const EventChannel _notifyChannel =
      EventChannel('cure_ble_native/notify');

  // Singleton instance (minimal change so all callers share one EventChannel subscription)
  static final CureBleTransportNative _instance = CureBleTransportNative._internal();
  factory CureBleTransportNative() => _instance;

  final StreamController<String> _notifyCtrl =
      StreamController<String>.broadcast();
  StreamSubscription<dynamic>? _eventSub;

  // Cached latest central state (from native plugin). Possible values: null or strings like "poweredOn" etc.
  String? _latestCentralState;
  Completer<void>? _poweredOnCompleter;
  final StreamController<void> _disconnectCtrl = StreamController<void>.broadcast();
  Stream<void> get onDisconnected => _disconnectCtrl.stream;

  CureBleTransportNative._internal() {
    // single subscription to native notify channel — updates _latestCentralState
    _eventSub = _notifyChannel.receiveBroadcastStream().listen((event) {
      try {
        // Log every incoming BLE event
        if (kDebugMode) debugPrint('[NativeTransport] raw event: $event');

        // Variante: Native sendet Maps: { type: "line", data: "..." }
        if (event is Map) {
          // Support multiple shapes emitted by native plugin
          final type = event['type'] ?? event['event'] ?? event['kind'];
          final data = event['data'] ?? event['line'] ?? event['message'] ?? event['text'];
          final state = event['state'] ?? event['centralState'] ?? event['name'];

          if (type == 'line' && data is String) {
            if (kDebugMode) debugPrint('[NativeTransport] line event: $data');
            _notifyCtrl.add(data.trim());

            // If native emits a central state as a line, detect and cache it
            if (data.startsWith('IOS_CENTRAL_STATE') || data.startsWith('IOS_CENTRAL_CREATED')) {
              _updateCachedStateFromLine(data);
            }
          } else if (state is String) {
            // direct state map
            if (kDebugMode) debugPrint('[NativeTransport] state event: $state');
            _updateCachedState(state);
          } else if (data is String) {
            // fallback: treat as a line
            if (kDebugMode) debugPrint('[NativeTransport] fallback line event: $data');
            _notifyCtrl.add(data.trim());
            if (data.startsWith('IOS_CENTRAL_STATE') || data.startsWith('IOS_CENTRAL_CREATED')) {
              _updateCachedStateFromLine(data);
            }
          } else {
            if (kDebugMode) debugPrint('[NativeTransport] unknown map event shape: $event');
          }
        }
        // Fallback: Native sendet direkt Strings
        else if (event is String) {
          if (kDebugMode) debugPrint('[NativeTransport] string event: $event');
          _notifyCtrl.add(event.trim());
          if (event.startsWith('IOS_CENTRAL_STATE') || event.startsWith('IOS_CENTRAL_CREATED')) {
            _updateCachedStateFromLine(event);
          }
        } else {
          if (kDebugMode) debugPrint('[NativeTransport] unexpected event type: ${event.runtimeType}');
        }
      } catch (e, st) {
        if (kDebugMode) debugPrint('CureBleTransportNative: notify event parse error: $e\n$st');
      }
    }, onError: (e) {
      if (kDebugMode) debugPrint('CureBleTransportNative: notify stream error: $e');
    });

    // Probe native plugin for current central state in case it was emitted before we subscribed.
    Future.microtask(() async {
      try {
        final raw = await _method.invokeMethod<dynamic>('getCentralState');
        if (kDebugMode) debugPrint('[NativeTransport] probe getCentralState -> $raw');
        if (raw is String) {
          // native might return a line-like string
          if (raw.startsWith('IOS_CENTRAL_STATE') || raw.startsWith('IOS_CENTRAL_CREATED')) {
            _updateCachedStateFromLine(raw);
          } else {
            _updateCachedState(raw);
          }
        } else if (raw is Map) {
          final state = raw['state'] ?? raw['name'] ?? raw['centralState'];
          if (state is String) _updateCachedState(state);
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[NativeTransport] getCentralState probe failed: $e');
      }
    });
  }

  // Helper to parse native line messages like: IOS_CENTRAL_STATE name=poweredOn raw=5
  void _updateCachedStateFromLine(String line) {
    try {
      final lower = line.toLowerCase();
      if (lower.contains('poweredon') || lower.contains('powered_on') || lower.contains('powered_on')) {
        _updateCachedState('poweredOn');
      } else if (lower.contains('poweredoff') || lower.contains('powered_off')) {
        _updateCachedState('poweredOff');
      } else if (lower.contains('unknown')) {
        _updateCachedState('unknown');
      } else if (lower.contains('unauthorized')) {
        _updateCachedState('unauthorized');
      } else if (lower.contains('unsupported')) {
        _updateCachedState('unsupported');
      } else if (lower.contains('resetting')) {
        _updateCachedState('resetting');
      }
    } catch (_) {}
  }

  void _updateCachedState(String s) {
    final prev = _latestCentralState;
    _latestCentralState = s;
    if (kDebugMode) debugPrint('[NativeTransport] cached central state: $prev -> $_latestCentralState');
    if (_latestCentralState == 'poweredOn') {
      if (_poweredOnCompleter != null && !_poweredOnCompleter!.isCompleted) {
        _poweredOnCompleter!.complete();
        _poweredOnCompleter = null;
      }
    }
    if (s.toUpperCase() == 'DISCONNECTED' && prev?.toUpperCase() != 'DISCONNECTED') {
      _disconnectCtrl.add(null);
    }
  }

  /// Returns true if the native transport currently has an active BLE connection.
  /// The native plugin emits state events like "READY", "CONNECTED", "DISCONNECTED".
  bool get isConnected {
    final s = _latestCentralState?.toUpperCase();
    if (s == null) return false;
    return s == 'READY' || s == 'CONNECTED';
  }

  /// Wait until native central reports poweredOn. Resolves immediately if cached state already poweredOn.
  Future<void> waitForCentralPoweredOn({Duration timeout = const Duration(seconds: 8)}) async {
    if (_latestCentralState == 'poweredOn') return;
    _poweredOnCompleter ??= Completer<void>();
    final comp = _poweredOnCompleter!;
    try {
      await comp.future.timeout(timeout);
    } catch (e) {
      // timeout -> rethrow as informative exception
      throw Exception('Native central not powered on (timeout)');
    }
  }

  @override
  String get id => 'native';

  @override
  Stream<String> get notifyLines => _notifyCtrl.stream;

  @override
  Future<void> connect(String deviceId) async {
    await _method.invokeMethod('connect', {'deviceId': deviceId});
  }

  @override
  Future<void> disconnect() async {
    await _method.invokeMethod('disconnect');
  }

  @override
  Future<void> writeLine(String line) async {
    await _method.invokeMethod('writeLine', {'line': line});
  }

  @override
  Future<List<String>> sendCommandAndWaitLines(
    String line, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (kDebugMode) debugPrint('[NativeTransport] sendCommandAndWaitLines: $line (timeout: ${timeout.inMilliseconds}ms)');
    final resp = await _method.invokeListMethod<String>(
      'sendCommandAndWaitLines',
      {
        'line': line,
        'timeoutMs': timeout.inMilliseconds,
      },
    );
    if (kDebugMode) debugPrint('[NativeTransport] sendCommandAndWaitLines result: $resp');
    if (resp != null) {
      return resp.whereType<String>().toList();
    }
    return const <String>[];
  }

  Future<void> runSignRoundtripTest({
    required String deviceId,
    void Function(String msg)? onLog,
  }) async {
    try {
      onLog?.call('Connecting to device...');
      await connect(deviceId);

      onLog?.call('Requesting challenge...');
      final challengeLines = await sendCommandAndWaitLines('challenge', timeout: Duration(seconds: 10));
      final challengeHex = challengeLines.firstWhere(
        (line) => RegExp(r'^[0-9A-Fa-f]{64}$').hasMatch(line.trim()),
        orElse: () => '',
      );

      if (challengeHex.isEmpty) {
        onLog?.call('Failed to retrieve challenge.');
        return;
      }

      onLog?.call('Challenge received: $challengeHex');
      final signCmd = 'sign=$challengeHex';

      onLog?.call('Requesting device signature...');
      final signLines = await sendCommandAndWaitLines(signCmd, timeout: Duration(seconds: 10));
      final signatureHex = signLines.firstWhere(
        (line) => RegExp(r'^[0-9A-Fa-f]{128}$').hasMatch(line.trim()),
        orElse: () => '',
      );

      if (signatureHex.isEmpty) {
        onLog?.call('Failed to retrieve signature.');
        return;
      }

      onLog?.call('Signature received: $signatureHex');
      final isValid = await CureBleTransportNative._method.invokeMethod<bool>(
        'verifyDeviceSignature',
        {'challengeHex': challengeHex, 'sigHex': signatureHex},
      );

      if (isValid == true) {
        onLog?.call('Device sign() verification: OK');
      } else {
        onLog?.call('Device sign() verification: FAILED');
      }
    } catch (e) {
      onLog?.call('Error during sign roundtrip test: $e');
    } finally {
      onLog?.call('Disconnecting from device...');
      await disconnect();
    }
  }

  void dispose() {
    _eventSub?.cancel();
    _notifyCtrl.close();
  }
}
