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
import 'package:hbcure/services/app_memory.dart';

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

  /// Bumped every time device info (hardware/build/connection) changes.
  /// UI widgets can listen to this to refresh.
  final ValueNotifier<int> deviceInfoRevision = ValueNotifier<int>(0);

  void _notifyDeviceInfoChanged() {
    deviceInfoRevision.value++;
  }
  // ---------------------------------------------------

  // ---------------- progStatus polling ----------------
  Timer? _progStatusTimer;
  StreamController<CureProgStatus>? _progStatusCtrl;
  bool _progStatusPollBusy = false;

  Stream<CureProgStatus> get progStatusStream =>
      _progStatusCtrl?.stream ?? const Stream.empty();
  // ---------------------------------------------------

  bool get isNativeConnected => _sharedDeviceId != null && _sharedTransport.isConnected;
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
      _notifyDeviceInfoChanged();
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
        // If already connected and READY for this device, skip reconnect
        if (_sharedDeviceId == deviceId) {
          debugPrint('[CureDeviceUnlockService] already connected to $deviceId, skipping reconnect');
          onStatus?.call(CureUnlockStatus.connecting);
        } else {
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
      // No pre-delay: Android parity – send response immediately after building signature.
      final respLines = await transport.sendCommandAndWaitLines(
        'response=$sigHex',
        timeout: const Duration(seconds: 20),
      );

      // On iOS, the native plugin returns "SYNTHETIC_OK" when the device was
      // silent after the response= burst (timer fallback or silent disconnect).
      // A real device OK is the string "OK".
      final bool _isIos = Platform.isIOS;
      bool ok = respLines.any((l) => l.trim().toUpperCase() == 'OK');
      bool _syntheticOk = _isIos &&
          !ok &&
          respLines.any((l) => l.trim().toUpperCase() == 'SYNTHETIC_OK');
      if (_syntheticOk) ok = true; // treat as tentative success for now

      if (kDebugMode && _isIos) {
        if (_syntheticOk) {
          debugPrint('[CureDeviceUnlockService] IOS_UNLOCK_RESULT synthetic_ok');
        } else if (ok) {
          debugPrint('[CureDeviceUnlockService] IOS_UNLOCK_RESULT real_ok');
        }
      }

      // The device may silently reboot/reconnect immediately after a successful
      // unlock and NOT send an explicit OK in the first attempt. Treat an empty
      // response (result: []) as a soft failure and retry once — the firmware
      // typically reconnects and accepts the handshake on the second attempt.
      if (!ok && respLines.isEmpty) {
        // Wait briefly to allow the device to reconnect after silent reboot
        if (kDebugMode) {
          debugPrint('[CureDeviceUnlockService] response= got empty result – waiting 3s for device to reconnect and retrying...');
        }
        await Future.delayed(const Duration(milliseconds: 3000));

        // If still not connected after the wait, attempt an active reconnect.
        if (!transport.isConnected) {
          if (kDebugMode) {
            debugPrint('[CureDeviceUnlockService] still disconnected after wait – attempting active reconnect for retry...');
          }
          try {
            await transport.connect(deviceId);
            _sharedDeviceId = deviceId;
            if (kDebugMode) {
              debugPrint('[CureDeviceUnlockService] reconnected to $deviceId for unlock retry');
            }
          } catch (reconnectErr) {
            if (kDebugMode) {
              debugPrint('[CureDeviceUnlockService] reconnect for retry failed: $reconnectErr');
            }
          }
        }

        if (transport.isConnected) {
          // Retry: re-send challenge → response round-trip on the new connection
          if (kDebugMode) {
            debugPrint('[CureDeviceUnlockService] retrying unlock after reconnect...');
          }
          final retryChallengeLines = await transport.sendCommandAndWaitLines(
            'challenge',
            timeout: const Duration(seconds: 10),
          );
          final retryChallengeHex = retryChallengeLines
              .map((l) => l.trim())
              .firstWhere(
                (l) => RegExp(r'^[0-9A-Fa-f]{64}$').hasMatch(l),
            orElse: () => '',
          );
          if (retryChallengeHex.isNotEmpty) {
            final retrySigHex = await CureCryptoDart.buildUnlockResponseNative(retryChallengeHex);
            if (retrySigHex.isNotEmpty) {
              final retryRespLines = await transport.sendCommandAndWaitLines(
                'response=$retrySigHex',
                timeout: const Duration(seconds: 20),
              );
              final retryRealOk = retryRespLines.any((l) => l.trim().toUpperCase() == 'OK');
              final retrySynthOk = _isIos &&
                  !retryRealOk &&
                  retryRespLines.any((l) => l.trim().toUpperCase() == 'SYNTHETIC_OK');
              ok = retryRealOk || retrySynthOk;
              _syntheticOk = _isIos && retrySynthOk && !retryRealOk;
              if (kDebugMode) {
                debugPrint('[CureDeviceUnlockService] retry result ok=$ok lines=$retryRespLines');
                if (_isIos) {
                  debugPrint('[CureDeviceUnlockService] IOS_UNLOCK_RESULT ${_syntheticOk ? 'synthetic_ok' : 'real_ok'} (retry)');
                }
              }
            }
          }
        }
      }

      if (!ok) {
        final detail = respLines.isEmpty
            ? 'No response from device (timeout or disconnect after response= burst)'
            : respLines.join(' | ');
        return CureUnlockResult(
          success: false,
          errorMessage: detail,
        );
      }

      // ── iOS synthetic-OK verification (diagnostic sequence) ──────────────
      // When the only OK was the timer-fallback synthetic OK, we cannot be sure
      // the device is actually unlocked. Run a small verification sequence and
      // log every step explicitly so we can diagnose what the device accepts.
      //
      // Sequence:
      //   1. wait 150ms → send progClear
      //   2. if progClear empty+disconnect → reconnect once, wait 500ms
      //   3. send getHardware → log result
      //   4. send getBuild    → log result
      //   5. unlock confirmed if getHardware OR getBuild returned a non-empty
      //      result (device answered a gated command → it is unlocked).
      //      If all three commands returned empty → unlock not confirmed.
      if (_isIos && _syntheticOk) {
        if (kDebugMode) {
          debugPrint('[CureDeviceUnlockService] IOS_UNLOCK_VERIFY_START progClear');
          debugPrint('[CureDeviceUnlockService] IOS_UNLOCK_NOT_CONFIRMED (pending verification)');
        }

        // ── step 1: settle + progClear ─────────────────────────────────────
        await Future.delayed(const Duration(milliseconds: 150));
        // Reconnect if needed before progClear.
        if (!transport.isConnected) {
          try {
            await transport.connect(deviceId);
            _sharedDeviceId = deviceId;
            await Future.delayed(const Duration(milliseconds: 300));
          } catch (_) {}
        }

        List<String> progClearLines = [];
        if (transport.isConnected) {
          if (kDebugMode) debugPrint('[CureDeviceUnlockService] IOS_VERIFY_STEP progClear');
          try {
            progClearLines = await transport.sendCommandAndWaitLines(
              'progClear',
              timeout: const Duration(seconds: 10),
            );
          } catch (e) {
            if (kDebugMode) {
              debugPrint('[CureDeviceUnlockService] IOS_VERIFY_RESULT progClear EXCEPTION $e (treating as empty)');
            }
          }
          if (kDebugMode) {
            debugPrint('[CureDeviceUnlockService] IOS_VERIFY_RESULT progClear lines=$progClearLines');
          }
        } else {
          if (kDebugMode) debugPrint('[CureDeviceUnlockService] IOS_VERIFY_STEP progClear SKIPPED (not connected)');
        }

        final progClearOk = progClearLines.any((l) => l.trim().toUpperCase() == 'OK');

        // ── step 2: reconnect if progClear caused disconnect ───────────────
        if (!transport.isConnected) {
          if (kDebugMode) debugPrint('[CureDeviceUnlockService] IOS_VERIFY_STEP reconnect (progClear caused disconnect)');
          try {
            await Future.delayed(const Duration(milliseconds: 500));
            await transport.connect(deviceId);
            _sharedDeviceId = deviceId;
            await Future.delayed(const Duration(milliseconds: 500));
            if (kDebugMode) debugPrint('[CureDeviceUnlockService] IOS_VERIFY_STEP reconnected OK');
          } catch (e) {
            if (kDebugMode) debugPrint('[CureDeviceUnlockService] IOS_VERIFY_STEP reconnect FAILED: $e');
          }
        }

        // ── step 3: getHardware ────────────────────────────────────────────
        String verifyHw = '';
        if (transport.isConnected) {
          if (kDebugMode) debugPrint('[CureDeviceUnlockService] IOS_VERIFY_STEP getHardware');
          try {
            final hwLines = await transport.sendCommandAndWaitLines(
              'getHardware',
              timeout: const Duration(seconds: 15),
            );
            verifyHw = hwLines
                .map((l) => l.trim())
                .firstWhere((l) => l.isNotEmpty && l.toUpperCase() != 'OK', orElse: () => '');
            if (kDebugMode) {
              debugPrint('[CureDeviceUnlockService] IOS_VERIFY_RESULT getHardware lines=$hwLines value=$verifyHw');
            }
          } catch (e) {
            if (kDebugMode) {
              debugPrint('[CureDeviceUnlockService] IOS_VERIFY_RESULT getHardware EXCEPTION $e (treating as empty)');
            }
          }
        } else {
          if (kDebugMode) debugPrint('[CureDeviceUnlockService] IOS_VERIFY_STEP getHardware SKIPPED (not connected)');
        }

        // ── step 4: getBuild ───────────────────────────────────────────────
        String verifyBuild = '';
        if (transport.isConnected) {
          await Future.delayed(const Duration(milliseconds: 200));
          if (kDebugMode) debugPrint('[CureDeviceUnlockService] IOS_VERIFY_STEP getBuild');
          try {
            final buildLines = await transport.sendCommandAndWaitLines(
              'getBuild',
              timeout: const Duration(seconds: 15),
            );
            verifyBuild = buildLines
                .map((l) => l.trim())
                .firstWhere((l) => l.isNotEmpty && l.toUpperCase() != 'OK', orElse: () => '');
            if (kDebugMode) {
              debugPrint('[CureDeviceUnlockService] IOS_VERIFY_RESULT getBuild lines=$buildLines value=$verifyBuild');
            }
          } catch (e) {
            if (kDebugMode) {
              debugPrint('[CureDeviceUnlockService] IOS_VERIFY_RESULT getBuild EXCEPTION $e (treating as empty)');
            }
          }
        } else {
          if (kDebugMode) debugPrint('[CureDeviceUnlockService] IOS_VERIFY_STEP getBuild SKIPPED (not connected)');
        }

        // ── step 5: verdict ────────────────────────────────────────────────
        // Device is considered unlocked if:
        //   • progClear returned OK  (direct confirmation), OR
        //   • getHardware returned a value (post-unlock command answered), OR
        //   • getBuild returned a value (post-unlock command answered).
        // All three empty → device did not respond to any gated command → fail.
        final verifyConfirmed = progClearOk || verifyHw.isNotEmpty || verifyBuild.isNotEmpty;
        if (kDebugMode) {
          debugPrint(
            '[CureDeviceUnlockService] IOS_VERIFY_SUMMARY '
            'progClearOk=$progClearOk hw=$verifyHw build=$verifyBuild confirmed=$verifyConfirmed',
          );
          if (verifyConfirmed) {
            debugPrint('[CureDeviceUnlockService] IOS_UNLOCK_VERIFY_OK');
          } else {
            debugPrint('[CureDeviceUnlockService] IOS_UNLOCK_VERIFY_FAIL all commands returned empty');
            debugPrint('[CureDeviceUnlockService] IOS_UNLOCK_NOT_CONFIRMED');
          }
        }

        if (!verifyConfirmed) {
          return const CureUnlockResult(
            success: false,
            errorMessage: 'Unlock not confirmed: progClear/getHardware/getBuild all returned empty (synthetic OK was false positive)',
          );
        }

        // Store verified info so the post-unlock block below can skip redundant queries.
        hardwareInfo ??= verifyHw.isNotEmpty ? verifyHw : null;
        buildInfo ??= verifyBuild.isNotEmpty ? verifyBuild : null;
      }

      onStatus?.call(CureUnlockStatus.doneOk);

      // -------- Qt-like post-unlock info --------
      // iOS-STABILISATION (2026-04-02):
      //   On iOS the firmware triggers a BLE connection-parameter renegotiation
      //   immediately after unlock. Sending the first command too quickly causes
      //   a disconnect. Strategy (iOS only):
      //     1. ALWAYS force-disconnect (even if still "connected") + reconnect fresh.
      //     2. After READY: wait 1000 ms before any command.
      //     3. Send getHardware, then wait 400 ms, then send getBuild.
      //     4. If getBuild returns empty / disconnect: reconnect + 1000 ms + retry getBuild once.
      //     5. A getBuild failure does NOT mark the unlock as failed.
      //   On Android: keep the previous behaviour (no force-disconnect, 500 ms delay).

      final bool _iosMode = Platform.isIOS;

      /// Helper: extract first non-empty, non-OK line from a response list.
      String _extractResult(List<String> lines) => lines
          .map((l) => l.trim())
          .firstWhere((l) => l.isNotEmpty && l.toUpperCase() != 'OK',
              orElse: () => '');

      /// Helper: reconnect with up to [maxAttempts] tries, [waitAfterMs] after READY.
      Future<bool> _reconnectWithDelay(int waitAfterMs, {int maxAttempts = 2}) async {
        for (int attempt = 1; attempt <= maxAttempts; attempt++) {
          try {
            if (kDebugMode) {
              debugPrint('[CureDeviceUnlockService] post-unlock reconnect attempt $attempt for $deviceId');
            }
            await transport.connect(deviceId);
            _sharedDeviceId = deviceId;
            if (kDebugMode) {
              debugPrint('[CureDeviceUnlockService] reconnected (attempt $attempt) to $deviceId for post-unlock info');
            }
            if (waitAfterMs > 0) {
              if (kDebugMode) {
                debugPrint('[CureDeviceUnlockService] IOS_POST_RECONNECT_DELAY_START ${waitAfterMs}ms');
              }
              await Future.delayed(Duration(milliseconds: waitAfterMs));
              if (kDebugMode) {
                debugPrint('[CureDeviceUnlockService] IOS_POST_RECONNECT_DELAY_END');
              }
            }
            return true;
          } catch (reconnectErr) {
            if (kDebugMode) {
              debugPrint('[CureDeviceUnlockService] post-unlock reconnect attempt $attempt failed: $reconnectErr');
            }
            if (attempt < maxAttempts) {
              await Future.delayed(const Duration(milliseconds: 1500));
            } else {
              _sharedDeviceId = null;
            }
          }
        }
        return false;
      }

      try {
        if (_iosMode) {
          // ── iOS path ──────────────────────────────────────────────────────
          // Step 1: ALWAYS disconnect (force-clean), even if still "connected".
          if (kDebugMode) {
            debugPrint('[CureDeviceUnlockService] IOS_POST_UNLOCK_FORCE_RECONNECT – disconnecting first');
          }
          if (transport.isConnected) {
            try {
              await transport.disconnect();
            } catch (_) {}
            _sharedDeviceId = null;
            await Future.delayed(const Duration(milliseconds: 500));
          }

          // Step 2: Reconnect + wait 1000 ms after READY.
          final connected = await _reconnectWithDelay(1000);
          if (!connected || !transport.isConnected) {
            if (kDebugMode) {
              debugPrint('[CureDeviceUnlockService] post-unlock reconnect failed – skipping info queries');
            }
            // Unlock itself succeeded; skip info gracefully.
          } else {
            // Step 3: getHardware
            if (kDebugMode) {
              debugPrint('[CureDeviceUnlockService] IOS_GET_HARDWARE_MODE – sending getHardware');
            }
            final hwLines = await transport.sendCommandAndWaitLines(
                'getHardware', timeout: const Duration(seconds: 30));
            hardwareInfo = _extractResult(hwLines);

            // 400 ms gap between getHardware and getBuild
            await Future.delayed(const Duration(milliseconds: 400));

            // Step 4: getBuild (with single retry on disconnect)
            if (kDebugMode) {
              debugPrint('[CureDeviceUnlockService] IOS_GET_BUILD_MODE – sending getBuild');
            }
            List<String> buildLines = [];
            if (transport.isConnected) {
              buildLines = await transport.sendCommandAndWaitLines(
                  'getBuild', timeout: const Duration(seconds: 30));
            }
            buildInfo = _extractResult(buildLines);

            if ((buildInfo?.isEmpty ?? true) && !transport.isConnected) {
              // getBuild failed due to disconnect – retry once
              if (kDebugMode) {
                debugPrint('[CureDeviceUnlockService] IOS_GET_BUILD_RETRY_RECONNECT – reconnecting for getBuild retry');
              }
              await Future.delayed(const Duration(milliseconds: 1500));
              final retryConnected = await _reconnectWithDelay(1000);
              if (retryConnected && transport.isConnected) {
                if (kDebugMode) {
                  debugPrint('[CureDeviceUnlockService] IOS_GET_BUILD_MODE (retry) – sending getBuild');
                }
                final retryBuildLines = await transport.sendCommandAndWaitLines(
                    'getBuild', timeout: const Duration(seconds: 30));
                buildInfo = _extractResult(retryBuildLines);
              }
            }
          }
        } else {
          // ── Android path (unchanged) ──────────────────────────────────────
          // Step 1: wait for disconnect to propagate (firmware always disconnects)
          await Future.delayed(const Duration(milliseconds: 1500));

          // Step 2: if still "connected", explicitly disconnect to clear stale state
          if (transport.isConnected) {
            if (kDebugMode) {
              debugPrint('[CureDeviceUnlockService] post-unlock: transport still shows connected – forcing disconnect before reconnect');
            }
            try {
              await transport.disconnect();
            } catch (_) {}
            _sharedDeviceId = null;
            await Future.delayed(const Duration(milliseconds: 500));
          }

          // Step 3: Reconnect – up to 2 attempts
          await _reconnectWithDelay(0);

          // Step 4: query info only if connected
          if (transport.isConnected) {
            if (kDebugMode) {
              debugPrint('[CureDeviceUnlockService] UNLOCK_OK_REACHED – POST_UNLOCK_DELAY_START (500ms)');
            }
            await Future.delayed(const Duration(milliseconds: 500));
            if (kDebugMode) {
              debugPrint('[CureDeviceUnlockService] POST_UNLOCK_DELAY_END – GET_HARDWARE_SENT');
            }

            Future<String> _queryWithRetry(String command) async {
              final lines = await transport.sendCommandAndWaitLines(
                  command, timeout: const Duration(seconds: 30));
              var result = _extractResult(lines);
              if (result.isEmpty && !transport.isConnected) {
                if (kDebugMode) {
                  debugPrint('[CureDeviceUnlockService] $command returned empty (device disconnected mid-command) – waiting 1.5s and reconnecting for retry...');
                }
                await Future.delayed(const Duration(milliseconds: 1500));
                try {
                  await transport.connect(deviceId);
                  _sharedDeviceId = deviceId;
                  if (kDebugMode) {
                    debugPrint('[CureDeviceUnlockService] reconnected (mid-${command == 'getHardware' ? 'info' : 'getBuild'} retry) to $deviceId');
                  }
                  final retryLines = await transport.sendCommandAndWaitLines(
                      command, timeout: const Duration(seconds: 30));
                  result = _extractResult(retryLines);
                } catch (retryErr) {
                  if (kDebugMode) {
                    debugPrint('[CureDeviceUnlockService] $command retry failed: $retryErr');
                  }
                }
              }
              return result;
            }

            hardwareInfo = await _queryWithRetry('getHardware');

            // Reconnect between commands if needed
            if (!transport.isConnected) {
              if (kDebugMode) {
                debugPrint('[CureDeviceUnlockService] disconnected between getHardware and getBuild – reconnecting...');
              }
              await Future.delayed(const Duration(milliseconds: 1500));
              try {
                await transport.connect(deviceId);
                _sharedDeviceId = deviceId;
              } catch (_) {}
            }

            if (transport.isConnected) {
              buildInfo = await _queryWithRetry('getBuild');
            }
          }
        }

        // supportsRemotePrograms is derived regardless of platform
        supportsRemotePrograms =
            buildInfo != null && buildInfo!.isNotEmpty && _versionAtLeast(buildInfo!, '0.1.0');

        if (kDebugMode) {
          debugPrint('[CureDeviceUnlockService] hardware=$hardwareInfo');
          debugPrint('[CureDeviceUnlockService] build=$buildInfo');
          debugPrint('[CureDeviceUnlockService] supportsRemotePrograms=$supportsRemotePrograms');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[CureDeviceUnlockService] post-unlock info failed: $e');
        }
        // Note: unlock itself already succeeded – do NOT rethrow.
      } finally {
        if (!transport.isConnected) {
          _sharedDeviceId = null;
        }
      }
      // -----------------------------------------

      // Persist device id for auto-reconnect on next app start
      AppMemory.instance.setLastDevice(deviceId);

      // Notify UI that device info changed
      _notifyDeviceInfoChanged();

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

  Future<bool> progClear() async {
    debugPrint('[PLAYLIST_TIME] progClear() called');
    debugPrint('[PLAYLIST_TIME] progClear stackTrace:\n${StackTrace.current.toString().split('\n').take(8).join('\n')}');
    return _sendAndCheckOk('progClear', timeout: const Duration(seconds: 10));
  }

  Future<bool> progStart() async {
    debugPrint('[PLAYLIST_TIME] progStart() called');
    debugPrint('[PLAYLIST_TIME] progStart stackTrace:\n${StackTrace.current.toString().split('\n').take(8).join('\n')}');
    return _sendAndCheckOk('progStart', timeout: const Duration(seconds: 10));
  }

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
