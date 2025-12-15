# Domain Knowledge – Cure Devices

Platzhalter: Beschreibung der CureBase / Pyramide Geräte.

- UART-over-BLE semantics (line-based, CR/LF terminated)
- Unlock handshake: challenge / response (ECDSA secp256k1, 32-byte challenge, 64-byte signature r||s)
- Program upload via `progClear`, `progAppend=<hex>`, `progStart`

Hinweis: BLE-Profile werden später erweitert und dokumentiert.

