import 'dart:typed_data';
import 'dart:io' show Platform;
import 'package:flutter/services.dart';

/// Minimal crypto bridge: prefer native implementation via MethodChannel on
/// Android and iOS. The previous pure-Dart signer used APIs that are not
/// available in this project and caused build-time errors (Method not found).
/// Keep the Dart file minimal and route to native crypto. If native is not
/// available an explicit StateError is thrown.
class CureCryptoDart {
  // MethodChannel to call native crypto when available (Android/iOS)
  static const MethodChannel _method = MethodChannel('cure_ble_native/methods');

  /// Try native implementation on Android/iOS. If native call fails an error
  /// is thrown so the caller can decide how to proceed.
  static Future<String> buildUnlockResponseNative(String challengeHex) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      throw UnsupportedError('buildUnlockResponseNative is only supported on Android/iOS');
    }

    try {
      final res = await _method.invokeMethod<String>('buildUnlockResponse', {'challengeHex': challengeHex});
      if (res == null || res.isEmpty) throw StateError('Native buildUnlockResponse returned empty');
      return res.toLowerCase();
    } catch (e) {
      throw StateError('Native buildUnlockResponse failed: $e');
    }
  }

  /// Deprecated / disabled: We don't keep a Dart signer because previous
  /// attempts relied on packages/APIs that caused build errors. If you need a
  /// pure-Dart signer, implement it in a separate file and ensure the used
  /// packages support the required API surface.
  static String buildUnlockResponse(String challengeHex, {bool enforceLowS = false}) {
    throw UnsupportedError('Pure-Dart buildUnlockResponse is disabled; use buildUnlockResponseNative');
  }
}
