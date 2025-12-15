import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hbcure/core/cure_protocol/cure_program_compiler.dart';
import 'package:hbcure/core/cure_protocol/cure_crc32.dart';
import 'package:hbcure/core/cure_protocol/cure_test_programs.dart';

void main() {
  test('CureProgramCompiler produces correct header (programId, length, crc)', () {
    final program = buildSimpleTestProgram();
    final bytes = CureProgramCompiler().compile(program);

    // Basic layout checks
    expect(bytes.length >= 9, true);

    // first byte == programId (0x03)
    expect(bytes[0], equals(0x03));

    // read programLen (u32 little-endian) at bytes[1..4]
    final bdLen = ByteData.sublistView(Uint8List.fromList(bytes), 1, 5);
    final programLen = bdLen.getUint32(0, Endian.little);

    // payload starts at index 9
    final payload = bytes.sublist(9);
    expect(programLen, equals(payload.length));

    // read crc (u32 little-endian) at bytes[5..8]
    final bdCrc = ByteData.sublistView(Uint8List.fromList(bytes), 5, 9);
    final headerCrc = bdCrc.getUint32(0, Endian.little);

    // compute crc over payload
    final computedCrc = CureCrc32.compute(Uint8List.fromList(payload));
    expect(headerCrc, equals(computedCrc));
  });
}

