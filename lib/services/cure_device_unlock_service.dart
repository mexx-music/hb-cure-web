// lib/services/cure_device_unlock_service.dart

import 'dart:async';
import 'dart:typed_data';
import 'dart:io' show Platform;
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import 'cure_ble_transport_native.dart';
import 'cure_crypto.dart';
import 'cure_program_compiler.dart';
import 'package:hbcure/core/cure_protocol/cure_program_model.dart';
import 'package:hbcure/core/cure_protocol/cure_program_factory.dart';
import 'package:hbcure/services/cure_crypto_dart.dart';

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
  bool _progStatusPollBusy = false;

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
    // remember previous shared device id so we can restore it on failure
    final String? _prevSharedDeviceId = _sharedDeviceId;
    try {
      await _sharedTransport.connect(deviceId);
      _sharedDeviceId = deviceId;
    } catch (e) {
      // restore previous value (avoid clearing an existing shared connection)
      _sharedDeviceId = _prevSharedDeviceId;
      rethrow;
    }
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
    // Always use the shared native transport. If caller requested manageConnection,
    // ensure _sharedDeviceId is set and keep the connection open (do not disconnect in finally).
    final CureBleTransportNative transport = _sharedTransport;

    // Guard: if caller asked NOT to manage connection, ensure the shared connection
    // is already active and bound to the requested deviceId.
    if (!manageConnection) {
      if (_sharedDeviceId == null || _sharedDeviceId != deviceId) {
        throw StateError(
            'shared connection not active for deviceId=$deviceId (shared=$_sharedDeviceId)');
      }
    }

    // remember previous shared id to allow rollback on failure
    final String? _prevSharedDeviceId = _sharedDeviceId;

    try {
      if (manageConnection) {
        onStatus?.call(CureUnlockStatus.connecting);
        // Attempt to connect using the shared transport and only set the shared
        // device id after the connect succeeded. If anything fails later, we
        // will roll back to the previous value.
        try {
          await transport.connect(deviceId);
          _sharedDeviceId = deviceId;
        } catch (e) {
          // ensure we don't leave a partially set sharedDeviceId
          _sharedDeviceId = _prevSharedDeviceId;
          rethrow;
        }
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

      // ---- building response ----
      onStatus?.call(CureUnlockStatus.buildingResponse);
      // Use native buildUnlockResponse when available, fallback to Dart implementation
      final String sigHex = await CureCryptoDart.buildUnlockResponseNative(challengeHex);

      if (sigHex.isEmpty) {
        return const CureUnlockResult(
            success: false, errorMessage: 'Signature build failed');
      }

      onStatus?.call(CureUnlockStatus.sendingResponse);
      // Mini-safety delay: some devices/iOS need a short pause before sending the response
      // (helps avoid race conditions where the device is not yet ready to parse the long response)
      await Future.delayed(const Duration(milliseconds: 200));
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
      // Rollback sharedDeviceId if we set it for this manageConnection attempt
      if (manageConnection) {
        _sharedDeviceId = _prevSharedDeviceId;
      }
      return CureUnlockResult(success: false, errorMessage: e.toString());
    } finally {
      // NOTE: Do not disconnect the shared transport here when manageConnection==true.
      // The shared transport remains connected for subsequent operations (uploads etc.).
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
      if (_progStatusTimer == null) return;
      if (_progStatusCtrl == null) return;
      if (_progStatusCtrl!.isClosed) return;

      if (_progStatusPollBusy) return; // guard to avoid overlapping calls
      _progStatusPollBusy = true;
      try {
        final st = await fetchProgStatus();
        if (st != null && _progStatusCtrl != null && !_progStatusCtrl!.isClosed) {
          _progStatusCtrl!.add(st);
        }
      } finally {
        _progStatusPollBusy = false;
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
    if (cleaned.isEmpty || cleaned.length.isOdd || !RegExp(r'^[0-9-A-Fa-f]+$').hasMatch(cleaned)) {
      return false;
    }
    return _sendAndCheckOk('progAppend=$cleaned', timeout: const Duration(seconds: 10));
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

  /// Append raw program bytes (already encoded) in chunks by calling progAppendHex
  /// This does NOT call progClear() — caller must clear explicitly when needed.
  Future<bool> appendProgramBytes(Uint8List bytes, {int chunkSize = 64}) async {
    if (_sharedDeviceId == null || bytes.isEmpty) return false;

    int offset = 0;
    while (offset < bytes.length) {
      final end = (offset + chunkSize).clamp(0, bytes.length);
      final slice = bytes.sublist(offset, end);
      final hex = slice.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      if (!await progAppendHex(hex)) return false;
      await Future.delayed(const Duration(milliseconds: 80));
      offset = end;
    }
    return true;
  }

  Future<bool> uploadProgramAndStart(CureProgram program) async {
    if (_sharedDeviceId == null) {
      debugPrint('[CureDeviceUnlockService] No native connection available.');
      return false;
    }

    try {
      // Compile program bytes
      final compiler = CureProgramCompiler();
      final programBytes = compiler.compile(program);

      // Clear existing program
      if (!await progClear()) {
        debugPrint('[CureDeviceUnlockService] progClear failed.');
        return false;
      }

      // Upload program in chunks
      const chunkSize = 64; // reduced to 64 bytes for safety
      int offset = 0;
      while (offset < programBytes.length) {
        final end = (offset + chunkSize).clamp(0, programBytes.length);
        final chunk = programBytes.sublist(offset, end);
        final hexChunk = chunk.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

        if (!await progAppendHex(hexChunk)) {
          debugPrint('[CureDeviceUnlockService] progAppend failed at offset $offset.');
          return false;
        }

        offset = end;
        await Future.delayed(const Duration(milliseconds: 80));
      }

      // Start program
      if (!await progStart()) {
        debugPrint('[CureDeviceUnlockService] progStart failed.');
        return false;
      }

      // Poll program status for 10 seconds
      final endTime = DateTime.now().add(const Duration(seconds: 10));
      while (DateTime.now().isBefore(endTime)) {
        final status = await fetchProgStatus();
        if (status != null && status.running) {
          debugPrint('[CureDeviceUnlockService] Program is running.');
          return true;
        }
        await Future.delayed(const Duration(milliseconds: 500));
      }

      debugPrint('[CureDeviceUnlockService] Program did not start within the expected time.');
      return false;
    } catch (e) {
      debugPrint('[CureDeviceUnlockService] uploadProgramAndStart failed: $e');
      return false;
    }
  }

  // Upload a single-frequency custom program (built from simple parameters)
  // NOTE: removed duplicate simple delegate implementation because a full
  // implementation (with deterministic uuid16 and checks) exists later in this file.

  /// Upload a single-frequency program built from simple parameters and start it.
  /// This is a minimal helper used for 'custom_' programs stored locally.
  Future<bool> uploadCustomSingleFrequencyAndStart({
    required double frequencyHz,
    required Duration duration,
    required int intensityPct,
    required bool powerMode,
    required bool useElectric,
    required String electricWaveform,
    required bool useMagnetic,
    required String magneticWaveform,
  }) async {
    if (_sharedDeviceId == null) {
      debugPrint('[CureDeviceUnlockService] No native connection available.');
      return false;
    }

    try {
      // Build deterministic 16-byte id from frequency + duration to avoid empty UUID
      final bd = ByteData(16);
      bd.setFloat64(0, frequencyHz);
      bd.setUint64(8, duration.inSeconds.toUnsigned(64));
      final uuid16 = bd.buffer.asUint8List();

      // intensity 0..100 -> nibble 0..10
      final nibble = (intensityPct / 10.0).round().clamp(0, 10);
      final eNib = useElectric ? nibble : 0;
      final hNib = useMagnetic ? nibble : 0;

      CureWaveForm wfFrom(String s) {
        final x = s.trim().toLowerCase();
        if (x.contains('sine')) return CureWaveForm.sine;
        if (x.contains('triangle')) return CureWaveForm.triangle;
        if (x.contains('square') || x.contains('rect')) return CureWaveForm.square;
        if (x.contains('saw')) return CureWaveForm.sawtooth;
        return CureWaveForm.sine;
      }

      final program = CureProgram(
        programUuid16: uuid16,
        name: 'Custom ${frequencyHz.toStringAsFixed(0)}Hz',
        intensity: CureIntensity(eNibble: eNib, hNibble: hNib),
        waveForms: CureWaveForms(e: wfFrom(electricWaveform), h: wfFrom(magneticWaveform)),
        steps: [CureFrequencyStep(frequencyHz: frequencyHz, dwellSeconds: duration.inSeconds)],
      );

      return await uploadProgramAndStart(program);
    } catch (e) {
      debugPrint('[CureDeviceUnlockService] uploadCustomSingleFrequencyAndStart failed: $e');
      return false;
    }
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
    final CureBleTransportNative transport = _sharedTransport;

    // If caller wants the method to manage the connection, ensure we do not
    // create a parallel shared connection for another device.
    if (manageConnection) {
      if (_sharedDeviceId != null && _sharedDeviceId != deviceId) {
        throw StateError('shared connection already active for $_sharedDeviceId');
      }
      if (_sharedDeviceId == null) {
        // open shared connection
        await nativeConnect(deviceId);
        onLog?.call('Connected to device $deviceId');
      } else {
        onLog?.call('Using existing native connection to $deviceId');
      }
    } else {
      // manageConnection == false -> require shared connection active and matching
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
      // Do NOT disconnect the shared transport here; leave connection managed by caller.
      onLog?.call('runSignRoundtripTest completed for $deviceId');
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

    // Sanitize: allow only 0-9, A-F, a-f
    final cleaned = challengeHex.replaceAll(RegExp(r'[^0-9-A-Fa-f]'), '');
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
