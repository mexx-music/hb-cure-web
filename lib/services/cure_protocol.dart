import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

// Minimal CureProtocol implementation that provides the necessary
// public API for the rest of the app and contains the requested
// _writeBytesOnce behavior (prefer writeWithoutResponse, fallback to writeWithResponse).

class CureProtocolException implements Exception {
  final String message;
  CureProtocolException(this.message);
  @override
  String toString() => 'CureProtocolException: $message';
}

class CureProtocol {
  final BluetoothDevice device;
  final BluetoothCharacteristic txCharacteristic; // write (UART RX on peripheral)
  final BluetoothCharacteristic rxCharacteristic; // notify (UART TX on peripheral)

  StreamSubscription<List<int>>? _notifSub;
  bool _notifyEnabled = false;

  // Pending command state
  Completer<void>? _pendingCompleter;
  List<String>? _pendingCollectedLines;
  Timer? _pendingTimer;
  String? _currentCommandName;

  // debug id
  final int _debugId = DateTime.now().microsecondsSinceEpoch & 0x7FFFFFFF;

  CureProtocol({
    required this.device,
    required this.txCharacteristic,
    required this.rxCharacteristic,
  }) {
    if (kDebugMode) {
      debugPrint('CureProtocol[#${_debugId}] created for device ${device.remoteId}');
    }
    // setup notify listener lazily when first command runs; optional here
  }

  Future<void> dispose() async {
    if (kDebugMode) debugPrint('CureProtocol[#${_debugId}] disposed for device ${device.remoteId}');
    _cleanupPending();
    try {
      await _notifSub?.cancel();
    } catch (_) {}
    _notifSub = null;
    // leave notifications enabled to avoid descriptor write races
    _notifyEnabled = true;
  }

  void _log(String s) {
    if (kDebugMode) debugPrint(s);
  }

  Future<void> _ensureNotify() async {
    if (_notifyEnabled) return;
    try {
      await rxCharacteristic.setNotifyValue(true);
      _notifSub = rxCharacteristic.value.listen((bytes) {
        try {
          _onNotifyBytes(Uint8List.fromList(bytes));
        } catch (e, st) {
          debugPrint('CureProtocol[#${_debugId}]._onNotifyBytes handler error: $e');
        }
      });
      _notifyEnabled = true;
    } catch (e) {
      // log but don't rethrow here; callers will attempt ops and see errors
      _log('CureProtocol[#${_debugId}] _ensureNotify failed: $e');
    }
  }

  /// Send a raw ascii command line and return the concatenated response lines
  /// up to and including OK/ERROR. The function sets a single pending completer
  /// and waits for _onNotifyBytes() to complete it when OK/ERROR arrives.
  Future<String> sendRawCommand(
    String command, {
    Duration timeout = const Duration(seconds: 5),
    bool longWrite = false,
  }) async {
    // serialize per-instance: disallow concurrent commands
    if (_pendingCompleter != null) {
      throw Exception('Another command is already in progress for command="${_currentCommandName ?? 'unknown'}"');
    }

    await _ensureNotify();

    _currentCommandName = command;
    _pendingCollectedLines = <String>[];
    _pendingCompleter = Completer<void>();

    _pendingTimer = Timer(timeout, () {
      if (!(_pendingCompleter?.isCompleted ?? true)) {
        _pendingCompleter?.completeError(TimeoutException('Timeout waiting for OK/ERROR for "${_currentCommandName}"'));
      }
    });

    // write once (no chunking)
    try {
      await _writeBytesOnce(command, longWrite: longWrite);
    } catch (e) {
      // If write fails but pending already completed (device already answered), treat as non-fatal
      if (_pendingCompleter != null && _pendingCompleter!.isCompleted) {
        _log('CureProtocol[#${_debugId}].sendRawCommand: write failed but pending already completed -> ignoring write error: $e');
      } else {
        // cleanup pending state then rethrow
        _cleanupPending();
        rethrow;
      }
    }

    try {
      await _pendingCompleter!.future;
    } finally {
      _pendingTimer?.cancel();
      _pendingTimer = null;
    }

    final lines = List<String>.from(_pendingCollectedLines ?? []);
    _cleanupPending();
    return lines.join('\r\n');
  }

  Future<Uint8List> sendChallengeAndGetRandom({Duration timeout = const Duration(seconds: 5)}) async {
    final resp = await sendRawCommand('challenge', timeout: timeout, longWrite: false);
    final parts = resp.split(RegExp(r'\r?\n'));
    String? dataLine;
    for (final p in parts) {
      final t = p.trim();
      if (t.isEmpty) continue;
      final up = t.toUpperCase();
      if (up == 'OK' || up == 'ERROR') continue;
      dataLine = t;
      break;
    }
    if (dataLine == null) throw Exception('No data line in challenge response');
    final cleaned = dataLine.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    if (cleaned.length != 64) throw Exception('Invalid challenge length: ${cleaned.length}');
    final bytes = Uint8List.fromList(hex.decode(cleaned));
    // Debug: expose challenge hex for external crypto cross-checks
    if (kDebugMode) {
      final challengeHex = hex.encode(bytes);
      debugPrint('HBDBG SIGN TEST: challengeHex=$challengeHex');
    }
    return bytes;
  }

  Future<bool> sendResponseSignature(List<int> signatureBytes, {Duration timeout = const Duration(seconds: 5)}) async {
    if (signatureBytes.length != 64) throw ArgumentError('signature must be 64 bytes');
    final sigHex = hex.encode(signatureBytes);
    // Debug: expose signature hex for external crypto cross-checks
    if (kDebugMode) {
      debugPrint('HBDBG SIGN TEST: sigHex=$sigHex');
    }
    final resp = await sendRawCommand('response=$sigHex', timeout: timeout, longWrite: true);
    final up = resp.toUpperCase();
    final ok = up.contains('OK');
    if (ok) {
      // mark unlocked state may be handled by caller/service
    }
    return ok;
  }

  Future<bool> clearProgram() async {
    final resp = await sendRawCommand('progClear');
    return resp.toUpperCase().contains('OK');
  }

  Future<bool> appendProgramChunk(List<int> bytes) async {
    final hexLine = hex.encode(bytes);
    final resp = await sendRawCommand('progAppend=$hexLine', longWrite: true);
    return resp.toUpperCase().contains('OK');
  }

  Future<bool> uploadProgram(List<int> fullProgramBytes) async {
    if (!await clearProgram()) return false;
    // split into small chunks (e.g., 64 bytes)
    const chunkSize = 64;
    for (var i = 0; i < fullProgramBytes.length; i += chunkSize) {
      final end = (i + chunkSize < fullProgramBytes.length) ? i + chunkSize : fullProgramBytes.length;
      final chunk = fullProgramBytes.sublist(i, end);
      final ok = await appendProgramChunk(chunk);
      if (!ok) return false;
      await Future.delayed(const Duration(milliseconds: 50));
    }
    return true;
  }

  Future<bool> startProgram() async {
    final resp = await sendRawCommand('progStart');
    return resp.toUpperCase().contains('OK');
  }

  Future<Map<String, dynamic>> getProgramStatus() async {
    final resp = await sendRawCommand('progStatus');
    final parts = resp.split(RegExp(r'\r?\n'));
    if (parts.isEmpty) throw Exception('No response');
    final first = parts.first.trim();
    final fields = first.split(',');
    if (fields.length < 7) throw Exception('Unexpected progStatus format');
    return {
      'running': fields[0] == 'running',
      'paused': fields[1] == 'paused',
      'elapsed': int.tryParse(fields[2]) ?? 0,
      'total': int.tryParse(fields[3]) ?? 0,
      'programIdHex': fields[4],
      'pcHex': fields[5],
      'waitTime': int.tryParse(fields[6]) ?? 0,
    };
  }

  Future<Map<String,String>> _parseSingleLineResponse(String resp) async {
    // helper unused - placeholder
    return {};
  }

  // ------------------------- new: getHardware / getBuild -------------------------
  /// Returns the first non-OK/ERROR line for "getHardware" command
  Future<String> getHardware({Duration timeout = const Duration(seconds:5)}) async {
    final resp = await sendRawCommand('getHardware', timeout: timeout);
    final parts = resp.split(RegExp(r'\r?\n'));
    for (final p in parts) {
      final t = p.trim();
      if (t.isEmpty) continue;
      final up = t.toUpperCase();
      if (up == 'OK' || up == 'ERROR') continue;
      return t;
    }
    throw Exception('No hardware info in getHardware response');
  }

  /// Returns the first non-OK/ERROR line for "getBuild" command
  Future<String> getBuild({Duration timeout = const Duration(seconds:5)}) async {
    final resp = await sendRawCommand('getBuild', timeout: timeout);
    final parts = resp.split(RegExp(r'\r?\n'));
    for (final p in parts) {
      final t = p.trim();
      if (t.isEmpty) continue;
      final up = t.toUpperCase();
      if (up == 'OK' || up == 'ERROR') continue;
      return t;
    }
    throw Exception('No build info in getBuild response');
  }

  void _onNotifyBytes(Uint8List bytes) {
    final s = utf8.decode(bytes, allowMalformed: true);
    // split into lines
    final parts = s.split(RegExp(r'\r|\n|\x00'));
    for (final raw in parts) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (kDebugMode) {
        debugPrint('CureProtocol: recv line: "${line.replaceAll("\n", "\\n")}"');
        debugPrint('CureProtocol[#${_debugId}]._onNotifyBytes: line="${line}", pendingCommand=${_currentCommandName}, hasPending=${_pendingCompleter != null && !(_pendingCompleter!.isCompleted)}');
      }
      // collect
      if (_pendingCollectedLines != null) {
        _pendingCollectedLines!.add(line);
        final token = line.split(RegExp(r'\s+'))[0].toUpperCase();
        if (token == 'OK' || token == 'ERROR') {
          if (!(_pendingCompleter?.isCompleted ?? true)) {
            if (kDebugMode) debugPrint('CureProtocol[#${_debugId}]._onNotifyBytes: completing pending command "${_currentCommandName}" because line="${token}"');
            _pendingCompleter?.complete();
          } else {
            if (kDebugMode) debugPrint('CureProtocol[#${_debugId}]._onNotifyBytes: OK/ERROR received but pendingCompleter already completed (cmd=${_currentCommandName})');
          }
        }
      } else {
        // no pending command: just log
        if (kDebugMode) debugPrint('CureProtocol[#${_debugId}]._onNotifyBytes: OK/ERROR received but no pending command (cmd=${_currentCommandName})');
      }
    }
  }

  void _cleanupPending() {
    _pendingTimer?.cancel();
    _pendingTimer = null;
    _pendingCompleter = null;
    _pendingCollectedLines = null;
    _currentCommandName = null;
  }

  Future<void> _writeBytesOnce(
    String cmd, {
    bool longWrite = false,
  }) async {
    // Command inkl. CRLF
    final data = utf8.encode('$cmd\r\n');
    final len = data.length;

    _log('CureProtocol[#${_debugId}]._writeBytesOnce: will write cmd="$cmd", len=$len');

    final chr = txCharacteristic; // use the field provided in the class
    if (chr == null) {
      throw CureProtocolException('TX characteristic not set for CureProtocol');
    }

    // --- Throttling / delay before writes ---
    const int minDelayMs = 200;
    const int longDelayMs = 250;
    final int computedDelayMs = (longWrite || cmd.length > 40) ? longDelayMs : minDelayMs;
    if (computedDelayMs > 0) {
      _log('CureProtocol[#${_debugId}]._writeBytesOnce: delaying ${computedDelayMs}ms before write (longWrite=$longWrite)');
      await Future.delayed(Duration(milliseconds: computedDelayMs));
    }

    // Always try write WITHOUT response first (Nordic UART preferred); only
    // fallback to with-response if the plugin/device explicitly reports that
    // WRITE_NO_RESPONSE is not supported.
    try {
      _log('CureProtocol[#${_debugId}]._writeBytesOnce: single write cmd="$cmd", withoutResponse=true');
      await chr.write(data, withoutResponse: true);
      return;
    } on PlatformException catch (e) {
      // Log details for debugging
      debugPrint('CureProtocol[#${_debugId}]._writeBytesOnce PlatformException (no-response attempt): code=${e.code}, message=${e.message}, details=${e.details}');

      final String msg = (e.message ?? e.toString()).toString();
      final bool isNoRespUnsupported = msg.toUpperCase().contains('WRITE_NO_RESPONSE') || msg.toUpperCase().contains('NO_RESPONSE');
      final bool isBusy = msg.contains('ERROR_GATT_WRITE_REQUEST_BUSY') || msg.contains(' 201') || msg.toUpperCase().contains('BUSY');
      final bool isTimeout = msg.toLowerCase().contains('timed out') || msg.toLowerCase().contains('timeout');

      // If pending was already completed by notify/OK, ignore write error
      if (_pendingCompleter != null && _pendingCompleter!.isCompleted) {
        _log('CureProtocol[#${_debugId}]._writeBytesOnce: Platform write failed but pending already completed -> ignoring: $e');
        return;
      }

      // If device/plugin says no-response is unsupported, try one fallback with response
      if (isNoRespUnsupported) {
        _log('CureProtocol[#${_debugId}]._writeBytesOnce: writeWithoutResponse not supported, falling back to writeWithResponse for cmd="$cmd"');
        try {
          await chr.write(data, withoutResponse: false);
          return;
        } on PlatformException catch (e2) {
          debugPrint('CureProtocol[#${_debugId}]._writeBytesOnce fallback PlatformException: code=${e2.code}, message=${e2.message}, details=${e2.details}');
          final String msg2 = (e2.message ?? e2.toString()).toString();
          final bool isBusy2 = msg2.contains('ERROR_GATT_WRITE_REQUEST_BUSY') || msg2.contains(' 201') || msg2.toUpperCase().contains('BUSY');
          final bool isTimeout2 = msg2.toLowerCase().contains('timed out') || msg2.toLowerCase().contains('timeout');

          if (_pendingCompleter != null && _pendingCompleter!.isCompleted) {
            _log('CureProtocol[#${_debugId}]._writeBytesOnce: fallback write failed but pending already completed -> ignoring: $e2');
            return;
          }

          if (isBusy2 || isTimeout2) {
            _log('CureProtocol[#${_debugId}]._writeBytesOnce: UART fallback write BUSY/Timeout for cmd="$cmd" – will rely on notify/OK instead of failing immediately: $e2');
            return;
          }

          throw CureProtocolException('write failed (fallback withResponse): $msg2');
        }
      }

      // BUSY or Timeout on initial no-response write -> soft handling: rely on notify/OK
      if (isBusy || isTimeout) {
        _log('CureProtocol[#${_debugId}]._writeBytesOnce: UART write BUSY/Timeout for cmd="$cmd" – will rely on notify/OK instead of failing immediately: $e');
        return;
      }

      // Other platform errors are fatal
      throw CureProtocolException('write failed: $msg');
    } on FlutterBluePlusException catch (e) {
      // Plugin-level exception handling (similar to PlatformException)
      debugPrint('CureProtocol[#${_debugId}]._writeBytesOnce FlutterBluePlusException (no-response attempt): ${e.toString()}');
      final String msg = e.toString();
      final bool isBusy = msg.contains('ERROR_GATT_WRITE_REQUEST_BUSY') || msg.contains(' 201') || msg.toUpperCase().contains('BUSY');
      final bool isTimeout = msg.toLowerCase().contains('timed out') || msg.toLowerCase().contains('timeout');

      if (_pendingCompleter != null && _pendingCompleter!.isCompleted) {
        _log('CureProtocol[#${_debugId}]._writeBytesOnce: FBP write failed but pending already completed -> ignoring: $e');
        return;
      }

      if (isBusy || isTimeout) {
        _log('CureProtocol[#${_debugId}]._writeBytesOnce: FBP UART write BUSY/Timeout for cmd="$cmd" – will rely on notify/OK instead of failing immediately: $e');
        return;
      }

      throw CureProtocolException('write failed (FBP): ${msg}');
    } catch (e, st) {
      _log('CureProtocol[#${_debugId}]._writeBytesOnce: Unexpected write error for cmd="$cmd": $e\n$st');
      rethrow;
    }
  }

  Future<void> ensureNotify() => _ensureNotify();

  /// Reset internal state (used by BleCureDeviceService when retrying unlock)
  void resetState() {
    _log('CureProtocol[#${_debugId}].resetState()');
    _cleanupPending();
    try {
      // don't cancel notify subscription here; leave notifications enabled
    } catch (_) {}
  }
}
