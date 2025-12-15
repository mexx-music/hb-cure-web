# PROJECT_STATE

## 1. Projektname
HB CURE – Flutter BLE App + ESP32 Firmware Integration

## 2. Aktueller Stand (Kurzfassung)
Dieses Repository enthält eine Flutter-App („hbcure“) mit einer Reihe von Modulen zur Anzeige und Verwaltung von „Cure“-Programmen sowie initialer BLE-Integration für die Kommunikation mit einer CureBase (ESP32) Firmware über ein textbasiertes UART-Protokoll.

Aktuell wurde eine neue Dart-Implementierung des device-protokolls angelegt: `lib/services/cure_protocol.dart` (zeilenbasiertes Textprotokoll + Chunked Writes + Retry/Backoff). Die Unlock-Handshake-Logik (challenge/response) wurde modelliert: `sendChallengeAndGetRandom()` und `sendResponseSignature()` sind vorhanden; außerdem `prog*` Kommandos (progClear, progAppend, progStart, progStop, progStatus, uploadProgram) sind implementiert.

Bekannte Problemfelder (siehe auch Abschnitt 6) bestehen weiterhin bei Android BLE: GATT_BUSY / ERROR_GATT_WRITE_REQUEST_BUSY (201) und GATT_ERROR (133) Disconnects beim großen Daten-Upload (progAppend), Timing/MTU/Durchsatz-Parameter sowie Signatur/Key-Handling für das Unlock.

## 3. Implementierte Flutter-Komponenten (relevante Dateien)
- lib/services/cure_protocol.dart (neu):
  - Zeilenbasiertes Textprotokoll (UART-over-BLE)
  - `sendRawCommand()` (CRLF-terminiert, chunked writes, notification parsing, timeout)
  - Spezifische Befehle: `sendChallengeAndGetRandom()`, `sendResponseSignature()`, `clearProgram()`, `appendProgramChunk()`, `uploadProgram()`, `startProgram()`, `stopProgram()`, `getProgramStatus()`
  - Exponentielles Backoff für write-BUSY (mehrere Versuche pro Chunk)
  - Interner Unlock-Status (`_isUnlocked`), Guard-Logik für Befehle wenn gesperrt
  - resetState(), dispose() und sauberes Pending-State-Management

- (In Arbeit / Erwähnt in Gesprächen, aber nicht in dieser Datei erstellt von Copilot in dieser Session):
  - lib/services/ble_cure_device_service.dart — zentrale BLE-Integration (wurde im Verlauf diskutiert und vielfach angepasst, Änderungen in diesem Repo sind aktuell nur in `cure_protocol.dart` vorgenommen worden)
  - tools/generate_programs_json.dart — Script zur Erzeugung von assets/programs.json (vom Nutzer angefordert, in Repo vorhanden/planned)
  - tools/test_programs_json.dart — Smoke-Test-Skript (vom Nutzer angefordert/planned)
  - lib/services/my_programs_service.dart — Service für gespeicherte Programme (gefordert in Konversation)
  - lib/ui/pages/... und weitere UI-Dateien — zahlreiche Anpassungen in Konversation besprochen

> Hinweis: Die obigen Einträge reflektieren den Diskussionsstand; die einzige neue Datei, die Copilot in dieser Session tatsächlich erstellt/angepasst hat, ist `lib/services/cure_protocol.dart`.

## 4. Firmware-Knowledge / relevante C-Dateien (aus der ESP32-Firmware)
Die Firmware verarbeitet ein zeilenbasiertes Textprotokoll (`CommStringParserStateMachine`) und stellt Interpreter-/Programmfunktionen bereit. Relevante C-Quellen (im Firmware-Repo):
- `comm.c` / `CommStringParserStateMachine(char c)` — zentrale Parser-Logik (Zeilenbildung, CR/LF/NUL Terminatoren)
- `interpreter.c` — Programminterpreter, Funktionen: `Interpreter_clearProgram()`, `Interpreter_appendProgramm()`, `Interpreter_start()` usw.
- `ble_uart_server.c` (oder ähnliche) — BLE GATT-Service Implementierung (UART-SVC), typische Nordic UART Service UUIDs
- `main/comm.c`, `main/comm.h` — weitere glue- und state-machine code

Wichtige Firmware-Verhaltensweisen:
- Bei `challenge` sendet die Firmware entweder 64 hex Zeichen (32 bytes) + CRLF und dann `OK` oder `UNAVAILABLE` wenn nicht genug Zufallsdaten vorhanden sind.
- Bei `response=<128hex>` prüft Firmware gegen Keys[]; bei gültiger Signatur: `OK` und `CureBaseUnlocked = 1`, sonst `ERROR`.
- `progAppend=<hex>` erfordert geradzahlige Hex-Zeichen; bei Überlauf/Fehler => `ERROR` und Clear.
- Antwort-Formate: Datenzeile(s) gefolgt von `OK` oder `ERROR`.

## 5. Wichtige BLE-Kommandos (Übersicht)
- `challenge` — Firmware sendet 64 hex Zeichen (32 bytes) + `OK` oder `UNAVAILABLE`
- `response=<128Hex>` — Client-Signatur (r||s = 64 bytes -> 128 hex), Firmware setzt Unlock bei Erfolg
- `progClear` — Firmware löscht Puffer, sendet `OK`
- `progAppend=<Hex>` — fügt Binärdaten in Form von Hex-String ein, sendet `OK` oder `ERROR`
- `progStart`, `progPause`, `progResume`, `progStop` — Steuerbefehle -> `OK`
- `progStatus` — liefert CSV: running,paused,elapsed,total,ProgramIdHex,PCHex,WaitTime + `OK`
- `progRead` — sendet den Programmpuffer in 32-Byte-Hex-Zeilen + `OK`
- `getBuild`, `getHardware` — Info + `OK`

## 6. Bekannte Probleme (Status & Details)
- Android BLE GATT Busy / Timeout Fehler:
  - `ERROR_GATT_WRITE_REQUEST_BUSY` (201) bei `writeCharacteristic` (häufig auf Android) während schneller aufeinander folgender writes.
  - `GATT_ERROR (133)` Disconnects während oder kurz nach großen writes (z. B. progAppend/response), führt zu Abbrüchen.
  - Ursache: Timing/MTU / write-Fenster / Firmware-Flow-Handling. Mögliche Gegenmaßnahmen: chunking, backoff, notify-Management, MTU negotiation, reduce payload size, inter-chunk delays.
- Unlock-Signatur & Keys:
  - Signatur-Implementierung (secp256k1) benötigt exakten privKey (32 Bytes). Der App-Stand umfasst eine Signatur-Funktion, mehrere Kandidatenschlüssel wurden in Konversation erwähnt.
  - Falls falscher Key/Format -> Firmware antwortet `ERROR`.
- Program upload:
  - `progAppend` große Datenmengen können zu BUSY/133 führen; Upload-Strategien müssen robust sein (retries/exponential backoff / inter-chunk delays).
- Pending-State-Hänger:
  - Früher gab es Probleme mit hängenden `_pendingCompleter` Zuständen; `sendRawCommand()` wurde robust gemacht (try/catch/finally) um Pending-State immer aufzuräumen.

## 7. Todos (kurze, priorisierte Liste)
1. Stabilisiere Upload-Fluss (high priority):
   - Feinabstimmung Backoff/Retry für progAppend, evtl. adaptive delays basierend auf MTU.
   - Sicherstellen, dass `progAppend` nicht doppelt gesendet wird und Firmware nicht überfahren wird.
2. Unlock keys (medium):
   - Kandidaten-Keys aus Firmware auslesen (Keys[] in C) und validen Key persistieren.
   - Option: verschlüsselte Speicherung des funktionierenden Key.
3. BLE-Platform-Fixes (medium):
   - Android: besseres Notify-Management, Erkennung ob Notify aktiv ist, Fehlerbehandlung für `write` vs `writeWithoutResponse`.
   - iOS: CocoaPods / Info.plist Einträge prüfen (Permissions, NSBluetoothAlwaysUsageDescription falls nötig).
4. Integration und Tests (medium):
   - UI: Buttons für Testprogramm Upload / progClear / Unlock testen (Devices page).
   - Unit-Tests: CureProgram Compiler + CRC32 + Upload-Simulation.
5. Dokumentation & CHANGELOG (low):
   - Immer alle Copilot-Änderungen in PROJECT_STATE.md eintragen (siehe Abschnitt 8)

## 8. Änderungslog (alle Änderungen, die Copilot in diesem Projekt durchgeführt hat)
> Regel: Jede weitere Änderung, die Copilot vornimmt, wird hier anhängig dokumentiert.

- 2025-11-29: `lib/services/cure_protocol.dart` — Datei angelegt und iterativ erweitert.
  - Implementiert: sendRawCommand(), chunked writes, notification parsing, timeout handling.
  - Implementiert: `sendChallengeAndGetRandom()`, `sendResponseSignature()`, `clearProgram()`, `appendProgramChunk()`, `uploadProgram()`, `startProgram()`, `stopProgram()`, `getProgramStatus()`.
  - Implementiert: interner Unlock-Status `_isUnlocked` mit Getter `isUnlocked`.
  - Implementiert: `resetState()` und `dispose()` ruft `resetState()` auf.
  - Implementiert: robuste Pending-State-Bereinigung im `sendRawCommand()` (try/catch/finally, `rethrow` bei Fehlern).
  - Implementiert: special handling von `UNAVAILABLE` in `sendChallengeAndGetRandom()`.
  - Implementiert: exponentielles Backoff per-chunk beim Schreiben mit max 5 Versuchen (Delays: 100/200/400/800/1600 ms) und Prüfung auf `ERROR_GATT_WRITE_REQUEST_BUSY` bzw. `writeCharacteristic() returned 201`.
  - Implementiert: Guard in `sendRawCommand()` um Befehle zu blockieren, wenn `CureBase` nicht unlocked ist (nur `challenge`, `response=`, `getBuild`, `getHardware` erlaubt).

(Anmerkung: viele weitere Änderungen an anderen Dateien wurden im Gespräch besprochen — diese sind hier absichtlich nicht als durchgeführt gelistet, da Copilot in dieser Session nur die oben genannten Änderungen wirklich in das Projekt geschrieben hat.)

---

## Hinweise zur weiteren Zusammenarbeit
- Ab jetzt: Jedes Mal, wenn du mich bittest, eine Datei zu ändern, werde ich `PROJECT_STATE.md` öffnen und die Änderung im Änderungslog (Abschnitt 8) eintragen. Ich füge nur die minimalen, klaren Einträge hinzu, damit der Verlauf nachvollziehbar ist.
- Wenn du möchtest, kann ich jetzt noch kleine Beispiele/Usage-Snippets in `PROJECT_STATE.md` ergänzen, z. B. wie man `CureProtocol` instanziiert und `sendChallengeAndGetRandom()` / `sendResponseSignature()` benutzt.

---

*Datei auto-generiert von Copilot (auf Nutzeranfrage) am 2025-11-29.*

