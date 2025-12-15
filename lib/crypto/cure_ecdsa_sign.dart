// filepath: lib/crypto/cure_ecdsa_sign.dart
//
// ECDSA-Signatur für Cure-App Unlock-Challenge
// - Kurve: secp256k1
// - Signiert direkt die 32-Byte-Challenge (kein zusätzliches Hashing)
// - Ausgabe: 64 Bytes (r||s) als Hex-String, kompatibel zu uECC_sign/uECC_verify
//
// Abhängigkeiten in pubspec.yaml:
//   dependencies:
//     pointycastle: ^3.9.0
//     convert: ^3.1.1

import 'dart:typed_data';

import 'package:convert/convert.dart' as convert;
import 'package:pointycastle/export.dart';

class CureEcdsaSign {
  // private_key_CureApp (32 Bytes) als Hex, exakt wie im C++-Code:
  // uint8_t private_key_CureApp[32]={0xE4, 0x07, 0x83, 0xF6, 0x81, 0xA5, 0xBB, 0x85,
  //   0x2C, 0xAB, 0x1E, 0x10, 0x6B, 0x66, 0x41, 0xEF,
  //   0xB4, 0x3C, 0x19, 0x23, 0xC1, 0xEB, 0xE2, 0x5C,
  //   0xA3, 0x68, 0x65, 0xCD, 0xFA, 0xB0, 0x65, 0x48};
  static const String _privKeyHex =
      'E40783F681A5BB852CAB1E106B6641EFB43C1923C1EBE25CA36865CDFAB06548';

  static final ECDomainParameters _domain = ECDomainParameters('secp256k1');
  static final BigInt _privD = BigInt.parse(_privKeyHex, radix: 16);
  static final ECPrivateKey _privKey = ECPrivateKey(_privD, _domain);

  /// Signiert eine 32-Byte-Challenge (als Hex-String, 64 Zeichen)
  /// und gibt die Signatur als 128-hex (r||s) zurück.
  static String signChallengeHex(String challengeHex) {
    final cleaned = challengeHex.replaceAll(RegExp(r'\s+'), '');
    if (cleaned.length != 64) {
      throw ArgumentError(
          'Challenge-Hex muss 64 Zeichen (32 Bytes) lang sein, ist aber ${cleaned.length}.');
    }

    final Uint8List challengeBytes =
    Uint8List.fromList(convert.hex.decode(cleaned));

    final Uint8List sigBytes = signChallengeBytes(challengeBytes);
    return convert.hex.encode(sigBytes);
  }

  /// Signiert 32 Bytes Challenge und gibt 64 Bytes r||s zurück.
  static Uint8List signChallengeBytes(Uint8List challenge) {
    if (challenge.length != 32) {
      throw ArgumentError(
          'Challenge muss genau 32 Bytes lang sein, ist aber ${challenge.length}.');
    }

    // Deterministische ECDSA-Variante:
    // - 1. Parameter null  -> wir übergeben bereits einen 32-Byte-Hash (hier: direkt die Challenge)
    // - 2. Parameter HMac(SHA256, 64) -> deterministisches k gemäß RFC 6979
    final ECDSASigner baseSigner =
    ECDSASigner(null, HMac(SHA256Digest(), 64));
    final NormalizedECDSASigner signer = NormalizedECDSASigner(baseSigner);

    signer.init(true, PrivateKeyParameter<ECPrivateKey>(_privKey));

    final ECSignature sig =
    signer.generateSignature(challenge) as ECSignature;

    // r und s auf je 32-Byte Big-Endian auffüllen (wie uECC)
    final Uint8List rBytes = _bigIntToFixedLength(sig.r, 32);
    final Uint8List sBytes = _bigIntToFixedLength(sig.s, 32);

    return Uint8List.fromList(<int>[...rBytes, ...sBytes]);
  }

  /// Wandelt BigInt in genau [length] Bytes Big-Endian um.
  static Uint8List _bigIntToFixedLength(BigInt value, int length) {
    if (value.sign < 0) {
      throw ArgumentError('Negative BigInt wird nicht unterstützt');
    }

    BigInt tmp = value;
    final List<int> result = List<int>.filled(length, 0);

    for (int i = length - 1; i >= 0 && tmp > BigInt.zero; i--) {
      result[i] = (tmp & BigInt.from(0xff)).toInt();
      tmp = tmp >> 8;
    }
    return Uint8List.fromList(result);
  }
}
