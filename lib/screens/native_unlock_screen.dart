import 'package:flutter/material.dart';
import 'package:hbcure/services/cure_device_unlock_service.dart';
import 'package:hbcure/services/native_unlock_test.dart';

// Ensure _selectedDeviceId is defined in the class or state.
// Example:
// String? _selectedDeviceId;

class YourWidget extends StatelessWidget {
  // Define _selectedDeviceId in your class or state
  final String? _selectedDeviceId;

  YourWidget(this._selectedDeviceId);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ...existing buttons for Blitz/Verbinden, Unlock, ReactiveBleUnlock, Testprogramm, Programm Start, Prog Clear...

        if (_selectedDeviceId != null) ...[
          const SizedBox(height: 24),
          const Text(
            'Native Unlock Tests',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          NativeUnlockTester.buildTestUI(context, _selectedDeviceId!),
        ],
      ],
    );
  }
}
