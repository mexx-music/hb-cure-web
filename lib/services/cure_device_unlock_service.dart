// lib/services/cure_device_unlock_service.dart

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import 'cure_ble_transport_native.dart';
import 'cure_crypto.dart';

enum CureUnlockStatus {
  connecting,
  challengeRequested,
  challengeReceived,
  buildingResponse,
  sendingResponse,
  doneOk,
  doneError,
}

class CureUnlockResult {
  final bool success;
  final String? errorMessage;
  const CureUnlockResult({required this.success, this.errorMessage});
}

/// Qt-like progStatus model
class CureProgStatus {
  final bool running;
  final bool paused;
  final int elapsedSec;
  final int totalSec;
  final String programIdHex;
  final String pcHex;
  final double waitTimeSec;
  final String? rawLine;

  CureProgStatus({
    required this.running,
    required this.paused,
    required this.elapsedSec,
    required this.totalSec,
    required this.programIdHex,
    required this.pcHex,
    required this.waitTimeSec,
    this.rawLine,
  });

  @override
  String toString() =>
      'CureProgStatus(running=$running, paused=$paused, elapsed=$elapsedSec, total=$totalSec, programId=$programIdHex, pc=$pcHex, wait=$waitTimeSec)';
}

class CureDeviceUnlockService {
  CureDeviceUnlockService._();
  static final CureDeviceUnlockService instance = CureDeviceUnlockService._();

  static const MethodChannel _method = MethodChannel('cure_ble_native/methods');

  // Shared native transport
  final CureBleTransportNative _sharedTransport = CureBleTransportNative();
  String? _sharedDeviceId;

  // -------- Post-unlock device info (Qt-like) --------
  String? hardwareInfo;
  String? buildInfo;
  bool supportsRemotePrograms = false;
  // ---------------------------------------------------

  // ---------------- progStatus polling ----------------
  Timer? _progStatusTimer;
  StreamController<CureProgStatus>? _progStatusCtrl;

  Stream<CureProgStatus> get progStatusStream =>
      _progStatusCtrl?.stream ?? const Stream.empty();
  // ---------------------------------------------------

  bool get isNativeConnected => _sharedDeviceId != null;
  String? get nativeConnectedDeviceId => _sharedDeviceId;

  // ===================== CONNECT =====================

  Future<void> nativeConnect(String deviceId) async {
    if (kDebugMode) {
      debugPrint('[CureDeviceUnlockService] nativeConnect -> $deviceId');
    }
    await _sharedTransport.connect(deviceId);
    _sharedDeviceId = deviceId;
  }

  Future<void> nativeDisconnect() async {
    if (_sharedDeviceId == null) return;
    if (kDebugMode) {
      debugPrint('[CureDeviceUnlockService] nativeDisconnect from $_sharedDeviceId');
    }
    try {
      await _sharedTransport.disconnect();
    } finally {
      _sharedDeviceId = null;
    }
  }

  // ===================== UNLOCK =====================

  Future<CureUnlockResult> unlockDevice(
      String deviceId, {
        void Function(CureUnlockStatus status)? onStatus,
        bool manageConnection = true,
      }) async {
    final CureBleTransportNative transport =
    manageConnection ? CureBleTransportNative() : _sharedTransport;

    try {
      if (manageConnection) {
        onStatus?.call(CureUnlockStatus.connecting);
        await transport.connect(deviceId);
      }

      onStatus?.call(CureUnlockStatus.challengeRequested);
      final challengeLines = await transport.sendCommandAndWaitLines(
        'challenge',
        timeout: const Duration(seconds: 10),
      );

      final challengeHex = challengeLines
          .map((l) => l.trim())
          .firstWhere(
            (l) => RegExp(r'^[0-9A-Fa-f]{64}$').hasMatch(l),
        orElse: () => '',
      );

      if (challengeHex.isEmpty) {
        return const CureUnlockResult(
            success: false, errorMessage: 'No valid challenge received');
      }

      onStatus?.call(CureUnlockStatus.challengeReceived);

      onStatus?.call(CureUnlockStatus.buildingResponse);
      final sigHex = await _method.invokeMethod<String>(
        'buildUnlockResponse',
        {'challengeHex': challengeHex},
      );

      if (sigHex == null || sigHex.isEmpty) {
        return const CureUnlockResult(
            success: false, errorMessage: 'Signature build failed');
      }

      onStatus?.call(CureUnlockStatus.sendingResponse);
      final respLines = await transport.sendCommandAndWaitLines(
        'response=$sigHex',
        timeout: const Duration(seconds: 20),
      );

      final ok = respLines.any((l) => l.trim().toUpperCase() == 'OK');
      if (!ok) {
        return CureUnlockResult(
          success: false,
          errorMessage: respLines.join(' | '),
        );
      }

      onStatus?.call(CureUnlockStatus.doneOk);

      // -------- Qt-like post-unlock info --------
      try {
        final hwLines =
        await transport.sendCommandAndWaitLines('getHardware');
        hardwareInfo = hwLines
            .map((l) => l.trim())
            .firstWhere((l) => l.isNotEmpty && l.toUpperCase() != 'OK',
            orElse: () => '');

        final buildLines =
        await transport.sendCommandAndWaitLines('getBuild');
        buildInfo = buildLines
            .map((l) => l.trim())
            .firstWhere((l) => l.isNotEmpty && l.toUpperCase() != 'OK',
            orElse: () => '');

        supportsRemotePrograms =
            buildInfo != null && _versionAtLeast(buildInfo!, '0.1.0');

        if (kDebugMode) {
          debugPrint('[CureDeviceUnlockService] hardware=$hardwareInfo');
          debugPrint('[CureDeviceUnlockService] build=$buildInfo');
          debugPrint(
              '[CureDeviceUnlockService] supportsRemotePrograms=$supportsRemotePrograms');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[CureDeviceUnlockService] post-unlock info failed: $e');
        }
      }
      // -----------------------------------------

      return const CureUnlockResult(success: true);
    } catch (e) {
      return CureUnlockResult(success: false, errorMessage: e.toString());
    } finally {
      if (manageConnection) {
        try {
          await transport.disconnect();
        } catch (_) {}
        transport.dispose();
      }
    }
  }

  // ===================== progStatus =====================

  Future<CureProgStatus?> fetchProgStatus(
      {Duration timeout = const Duration(seconds: 5)}) async {
    if (_sharedDeviceId == null) return null;

    try {
      final lines =
      await _sharedTransport.sendCommandAndWaitLines('progStatus');
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
        paused:
        pausedStr == 'paused' || pausedStr == '1' || pausedStr == 'true',
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

  void startProgStatusPolling(Duration period) {
    if (_sharedDeviceId == null) return;

    stopProgStatusPolling();
    _progStatusCtrl = StreamController<CureProgStatus>.broadcast();
    _progStatusTimer = Timer.periodic(period, (_) async {
      final st = await fetchProgStatus();
      if (st != null && _progStatusCtrl != null && !_progStatusCtrl!.isClosed) {
        _progStatusCtrl!.add(st);
      }
    });
  }

  void stopProgStatusPolling() {
    _progStatusTimer?.cancel();
    _progStatusTimer = null;
    _progStatusCtrl?.close();
    _progStatusCtrl = null;
  }

  // ===================== PROGRAM UPLOAD =====================

  Future<bool> progClear() async =>
      _sendAndCheckOk('progClear', timeout: const Duration(seconds: 10));

  Future<bool> progStart() async =>
      _sendAndCheckOk('progStart', timeout: const Duration(seconds: 10));

  Future<bool> progAppendHex(String hex) async {
    final cleaned = hex.replaceAll(RegExp(r'\s+'), '');
    if (cleaned.isEmpty ||
        cleaned.length.isOdd ||
        !RegExp(r'^[0-9A-Fa-f]+$').hasMatch(cleaned)) {
      return false;
    }
    return _sendAndCheckOk('progAppend=$cleaned',
        timeout: const Duration(seconds: 10));
  }

  Future<bool> uploadProgramBytes(Uint8List bytes,
      {int chunkSize = 64}) async {
    if (_sharedDeviceId == null || bytes.isEmpty) return false;

    if (!await progClear()) return false;

    int offset = 0;
    while (offset < bytes.length) {
      final end = (offset + chunkSize).clamp(0, bytes.length);
      final slice = bytes.sublist(offset, end);
      final hex = slice
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      if (!await progAppendHex(hex)) return false;
      await Future.delayed(const Duration(milliseconds: 80));
      offset = end;
    }
    return true;
  }

  // ===================== HELPERS =====================

  Future<bool> _sendAndCheckOk(
      String cmd, {
        Duration timeout = const Duration(seconds: 10),
      }) async {
    if (_sharedDeviceId == null) return false;
    try {
      final lines =
      await _sharedTransport.sendCommandAndWaitLines(cmd, timeout: timeout);
      return lines.any((l) => l.trim().toUpperCase() == 'OK');
    } catch (_) {
      return false;
    }
  }

  bool _versionAtLeast(String v, String min) {
    List<int> parse(String s) =>
        s.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final a = parse(v);
    final b = parse(min);
    final len = a.length > b.length ? a.length : b.length;
    for (int i = 0; i < len; i++) {
      final ai = i < a.length ? a[i] : 0;
      final bi = i < b.length ? b[i] : 0;
      if (ai != bi) return ai > bi;
    }
    return true;
  }

  // --- Test / helper methods added per request --------------------------------
  /// Trusted sign roundtrip:
  /// - challenge vom Gerät holen
  /// - sign=<challenge> holen
  /// - Signatur mit PublicKey verifizieren (Dart-side verify)
  Future<void> runSignRoundtripTest({
    required String deviceId,
    void Function(String msg)? onLog,
    bool manageConnection = true,
  }) async {
    final CureBleTransportNative transport =
        manageConnection ? CureBleTransportNative() : _sharedTransport;

    if (!manageConnection) {
      if (_sharedDeviceId == null) {
        onLog?.call('No native connection; call nativeConnect(deviceId) first.');
        return;
      }
      if (_sharedDeviceId != deviceId) {
        onLog?.call('Native connection is active for $_sharedDeviceId, not $deviceId.');
        return;
      }
    }

    try {
      if (manageConnection) {
        await transport.connect(deviceId);
        onLog?.call('Connected to device $deviceId');
      } else {
        onLog?.call('Using existing native connection to $deviceId');
      }

      final challengeLines = await transport.sendCommandAndWaitLines(
        'challenge',
        timeout: const Duration(seconds: 10),
      );

      final challengeHex = challengeLines.firstWhere(
        (line) => RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(line.trim()),
        orElse: () => throw Exception('No valid challenge received'),
      ).trim();

      onLog?.call('Received challenge: $challengeHex');

      final signLines = await transport.sendCommandAndWaitLines(
        'sign=$challengeHex',
        timeout: const Duration(seconds: 10),
      );

      final signatureHex = signLines.firstWhere(
        (line) => RegExp(r'^[0-9a-fA-F]{128}$').hasMatch(line.trim()),
        orElse: () => throw Exception('No valid signature received'),
      ).trim();

      onLog?.call('Received signature: $signatureHex');

      final isValid = await CureCrypto.verifyDeviceSignature(challengeHex, signatureHex);

      onLog?.call(isValid ? 'Device sign() verification: OK' : 'Device sign() verification: FAILED');
    } finally {
      if (manageConnection) {
        try {
          await transport.disconnect();
        } catch (_) {}
        transport.dispose();
        onLog?.call('Disconnected from device $deviceId');
      }
    }
  }

  /// Sign-Test: sendet sign=<challengeHex> über die bestehende native-Verbindung.
  Future<List<String>> sendSignTest({
    required String deviceId,
    required String challengeHex,
  }) async {
    if (_sharedDeviceId == null) {
      throw StateError('sendSignTest: No native connection; call nativeConnect(deviceId) first.');
    }
    if (_sharedDeviceId != deviceId) {
      throw StateError('sendSignTest: Connected device is $_sharedDeviceId, but requested $deviceId.');
    }

    final cleaned = challengeHex.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
    if (cleaned.length != 64) {
      throw ArgumentError('challengeHex must be exactly 64 hex chars');
    }

    return await _sharedTransport.sendCommandAndWaitLines(
      'sign=$cleaned',
      timeout: const Duration(seconds: 10),
    );
  }

  Future<bool> verifyDeviceSignature({
    required String challengeHex,
    required String signatureHex,
  }) async {
    return CureCrypto.verifyDeviceSignature(challengeHex, signatureHex);
  }
}
