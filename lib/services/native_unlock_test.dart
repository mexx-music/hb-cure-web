// lib/services/native_unlock_test.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'cure_device_unlock_service.dart';

/// Kleiner Debug-Helper zum manuellen Testen des nativen BLE-Transports.
///
/// Nutzung (z.B. in einem Debug-Panel / auf der DevicesPage):
/// NativeUnlockTester.buildTestUI(context, deviceId)
class NativeUnlockTester {
  NativeUnlockTester._internal();
  static final NativeUnlockTester instance = NativeUnlockTester._internal();

  /// Alter One-Shot-Test:
  /// - baut eigene Verbindung auf
  /// - führt Unlock aus
  /// - trennt wieder
  Future<void> testNativeUnlock(String deviceId) async {
    debugPrint('[NativeUnlockTester] Starting ONE-SHOT unlock test for $deviceId');

    try {
      final res = await CureDeviceUnlockService.instance.unlockDevice(
        deviceId,
        onStatus: (s) =>
            debugPrint('[NativeUnlockTester] one-shot status=$s'),
        manageConnection: true, // eigener Connect/Disconnect
      );

      if (res.success) {
        debugPrint('[NativeUnlockTester] ONE-SHOT Unlock succeeded');
      } else {
        debugPrint('[NativeUnlockTester] ONE-SHOT Unlock failed: ${res.errorMessage}');
      }
    } catch (e, st) {
      debugPrint('[NativeUnlockTester] ONE-SHOT ERROR: $e');
      debugPrint('$st');
    }
  }

  /// Trusted Sign Test mit wählbarem Verbindungsmanagement.
  Future<void> testTrustedSign(String deviceId,
      {bool manageConnection = false}) async {
    debugPrint('[NativeUnlockTester] Starting Trusted Sign Test for $deviceId (manageConnection=$manageConnection)');

    try {
      await CureDeviceUnlockService.instance.runSignRoundtripTest(
        deviceId: deviceId,
        manageConnection: manageConnection,
        onLog: (msg) => debugPrint('[NativeUnlockTester] $msg'),
      );
    } catch (e, st) {
      debugPrint('[NativeUnlockTester] ERROR during Trusted Sign Test: $e');
      debugPrint('$st');
    }
  }

  /// Führt den sign-Test durch (Shared native connection erwartet).
  Future<void> _runSignTest(BuildContext context, String deviceId) async {
    debugPrint('[NativeUnlockTester] Starting sign-Test for $deviceId');

    try {
      // Challenge-Hex vom User abfragen (vorerst manuell)
      final challengeHex = await _askForChallengeHex(context);
      if (challengeHex == null || challengeHex.isEmpty) {
        debugPrint('[NativeUnlockTester] Aborted: No challenge provided');
        return;
      }

      debugPrint('[NativeUnlockTester] sign-Test läuft...');

      // 1) sign=<challengeHex> an Gerät senden (Shared-Verbindung)
      final lines = await CureDeviceUnlockService.instance.sendSignTest(
        deviceId: deviceId,
        challengeHex: challengeHex,
      );

      if (lines.isEmpty) {
        debugPrint('[NativeUnlockTester] Keine Signatur vom Gerät erhalten (Timeout)');
        return;
      }

      // Wir erwarten 1 Zeile mit 128 Hex-Zeichen
      final sigLine = lines.first.trim();
      if (sigLine.length != 128 ||
          !RegExp(r'^[0-9A-Fa-f]{128}$').hasMatch(sigLine)) {
        debugPrint('[NativeUnlockTester] Unerwartete Antwort: "$sigLine"');
        return;
      }

      final isValid =
      await CureDeviceUnlockService.instance.verifyDeviceSignature(
        challengeHex: challengeHex,
        signatureHex: sigLine,
      );

      if (isValid) {
        debugPrint(
            '[NativeUnlockTester] sign-Test: Firmware-Signatur GÜLTIG\nsig=$sigLine');
      } else {
        debugPrint(
            '[NativeUnlockTester] sign-Test: Firmware-Signatur UNGÜLTIG\nsig=$sigLine');
      }
    } catch (e, st) {
      debugPrint('[NativeUnlockTester] sign-Test Fehler: $e');
      debugPrint('$st');
    }
  }

  Future<String?> _askForChallengeHex(BuildContext context) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Challenge-Hex eingeben'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: '64-stellige Challenge (Hex)',
            ),
            maxLines: 1,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('Abbrechen'),
            ),
            TextButton(
              onPressed: () {
                final value = controller.text.trim();
                Navigator.of(ctx).pop(value);
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  /// Debug-UI für DevicesPage oder Native-Unlock-Screen:
  /// - Native Connect / Disconnect (shared)
  /// - Unlock über bestehende Verbindung (keine Trennung)
  /// - Trusted Sign Roundtrip (shared)
  /// - sign-Test (shared)
  /// - optional: One-Shot Unlock
  static Widget buildTestUI(BuildContext context, String deviceId) {
    final unlockService = CureDeviceUnlockService.instance;
    final isConnected = unlockService.isNativeConnected &&
        unlockService.nativeConnectedDeviceId == deviceId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Native Unlock Tests',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),

        // Verbindungs-Buttons
        Row(
          children: [
            ElevatedButton(
              onPressed: () async {
                try {
                  await unlockService.nativeConnect(deviceId);
                  if (kDebugMode) {
                    debugPrint(
                        '[NativeUnlockTester] Native connected to $deviceId');
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Native connected')),
                  );
                } catch (e) {
                  debugPrint(
                      '[NativeUnlockTester] nativeConnect ERROR: $e');
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Native connect failed: $e')),
                  );
                }
              },
              child: const Text('Native verbinden'),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: isConnected
                  ? () async {
                try {
                  await unlockService.nativeDisconnect();
                  if (kDebugMode) {
                    debugPrint(
                        '[NativeUnlockTester] Native disconnected');
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Native disconnected')),
                  );
                } catch (e) {
                  debugPrint(
                      '[NativeUnlockTester] nativeDisconnect ERROR: $e');
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('Native disconnect failed: $e')),
                  );
                }
              }
                  : null,
              child: const Text('Trennen'),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // Unlock ohne Disconnect (shared connection)
        ElevatedButton(
          onPressed: isConnected
              ? () async {
            debugPrint(
                '[NativeUnlockTester] Unlock over shared native connection');
            final res = await unlockService.unlockDevice(
              deviceId,
              manageConnection: false,
              onStatus: (s) => debugPrint(
                  '[NativeUnlockTester] shared-unlock status=$s'),
            );
            if (res.success) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Unlock OK (shared)')),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(
                        'Unlock failed (shared): ${res.errorMessage}')),
              );
            }
          }
              : null,
          child: const Text('Unlock (shared native conn)'),
        ),

        const SizedBox(height: 8),

        // Trusted Sign Roundtrip ohne Disconnect
        ElevatedButton(
          onPressed: isConnected
              ? () async {
            debugPrint(
                '[NativeUnlockTester] Trusted Sign Test over shared native connection');
            await NativeUnlockTester.instance
                .testTrustedSign(deviceId, manageConnection: false);
          }
              : null,
          child: const Text('Trusted Sign Test (shared)'),
        ),

        const SizedBox(height: 8),

        // sign-Test (sendSignTest + Verify)
        ElevatedButton(
          onPressed: isConnected
              ? () async {
            await NativeUnlockTester.instance
                ._runSignTest(context, deviceId);
          }
              : null,
          child: const Text('sign-Test (shared)'),
        ),

        const SizedBox(height: 16),

        // Optional: One-Shot Unlock (zur Sicherheit, falls man nur kurz testen will)
        ElevatedButton(
          onPressed: () async {
            await NativeUnlockTester.instance.testNativeUnlock(deviceId);
          },
          child: const Text('Quick Unlock (ONE-SHOT, eigene Verbindung)'),
        ),
      ],
    );
  }
}
