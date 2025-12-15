// tools/test_sign_dart.dart
import 'dart:typed_data';
import 'package:convert/convert.dart';
import 'package:pointycastle/export.dart' as pc;

Uint8List bigIntToFixedLength(BigInt v, int length) {
  final mask = (BigInt.one << (length * 8)) - BigInt.one;
  final truncated = v & mask;
  final hexStr = truncated.toRadixString(16).padLeft(length * 2, '0');
  return Uint8List.fromList(hex.decode(hexStr));
}

Future<Uint8List> signSecp256k1Raw(Uint8List challenge32, String privateKeyHex) async {
  final hexKey = privateKeyHex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
  final d = BigInt.parse(hexKey, radix: 16);
  final domain = pc.ECDomainParameters('secp256k1');
  final privParams = pc.PrivateKeyParameter<pc.ECPrivateKey>(pc.ECPrivateKey(d, domain));

  final pc.ECDSASigner baseSigner = pc.ECDSASigner(null, pc.HMac(pc.SHA256Digest(), 64));
  final pc.NormalizedECDSASigner signer = pc.NormalizedECDSASigner(baseSigner);
  signer.init(true, privParams);
  final sig = signer.generateSignature(challenge32) as pc.ECSignature;
  final rBytes = bigIntToFixedLength(sig.r, 32);
  final sBytes = bigIntToFixedLength(sig.s, 32);
  return Uint8List.fromList([...rBytes, ...sBytes]);
}

void main() async {
  final challengeHex = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';
  final challenge = Uint8List.fromList(hex.decode(challengeHex));
  final privHex = 'E40783F681A5BB852CAB1E106B6641EFB43C1923C1EBE25CA36865CDFAB06548';
  final sig = await signSecp256k1Raw(challenge, privHex);
  final sigHex = hex.encode(sig);
  print('DART_SIG: $sigHex');
}

