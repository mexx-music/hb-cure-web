// lib/services/cure_ble_transport.dart

import 'dart:async';

/// Transport-Abstraktion für UART-ähnliche Cure-BLE-Kommunikation.
///
/// Ziel: ermöglicht mehrere Backend-Implementierungen (FBP, native, ...)
/// ohne die höhere Protokoll-Logik (CureProtocol) zu verändern.
abstract class CureBleTransport {
  /// Eindeutige Id des Backends, z.B. 'fbp' oder 'native'
  String get id;

  /// Verbinde mit einem Gerät (deviceId platform-spezifisch)
  Future<void> connect(String deviceId);

  /// Trenne die Verbindung
  Future<void> disconnect();

  /// Schreibe eine einzelne UART-Zeile wie "challenge\r\n" oder "response=...\r\n".
  Future<void> writeLine(String line);

  /// Schicke eine Zeile und liefere empfangene Antwort-Zeilen zurück.
  ///
  /// Default-Implementierung ist nicht verfügbar - Backends sollten
  /// diese Methode selbst implementieren. Wir markieren diese Methode
  /// mit @mustCallSuper, damit Subklassen das Basisverhalten nutzen
  /// oder explizit überschreiben.
  Future<List<String>> sendCommandAndWaitLines(String line, {Duration timeout = const Duration(seconds: 30)}) async {
    // Default-Stub: Backends müssen dies implementieren. Wir liefern
    // einen klaren Fehler, damit Rückwärtskompatibilität gewährleistet ist.
    throw UnimplementedError('sendCommandAndWaitLines must be implemented by CureBleTransport backend');
  }

  /// Stream mit empfangenen Zeilen (already trimmed, ohne CRLF)
  Stream<String> get notifyLines;
}

