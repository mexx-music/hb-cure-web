import '../models/program_item.dart';
import 'package:flutter/foundation.dart';

class CubeDeviceService {
  CubeDeviceService();

  Future<void> sendProgram({required ProgramItem program, required Duration duration, required bool powerMode}) async {
    // TODO: Implement BLE communication to the Cure device.
    debugPrint('Sending program ${program.id} (${program.name}), duration: ${duration.inMinutes} min, powerMode: $powerMode');
    await Future.delayed(const Duration(milliseconds: 200));
  }
}
