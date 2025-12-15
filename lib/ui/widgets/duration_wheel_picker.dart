import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// A simple Cupertino-style wheel picker for duration minutes.
/// Use it inside `showCupertinoModalPopup(context: ..., builder: (_) => DurationWheelPicker(...))`.
class DurationWheelPicker extends StatefulWidget {
  final List<int> durationsMinutes;
  final int initialMinutes;
  final ValueChanged<int> onSelected;

  const DurationWheelPicker({super.key, required this.durationsMinutes, required this.initialMinutes, required this.onSelected});

  @override
  State<DurationWheelPicker> createState() => _DurationWheelPickerState();
}

class _DurationWheelPickerState extends State<DurationWheelPicker> {
  late int _selectedIndex;

  @override
  void initState() {
    super.initState();
    final idx = widget.durationsMinutes.indexOf(widget.initialMinutes);
    _selectedIndex = idx >= 0 ? idx : 0;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        color: AppColors.cardBackground,
        height: 260,
        child: Column(
          children: [
            SizedBox(
              height: 44,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: const Text('Done', style: TextStyle(color: Colors.black)),
                    onPressed: () {
                      widget.onSelected(widget.durationsMinutes[_selectedIndex]);
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: CupertinoPicker(
                backgroundColor: AppColors.cardBackground,
                itemExtent: 36,
                scrollController: FixedExtentScrollController(initialItem: _selectedIndex),
                onSelectedItemChanged: (i) => setState(() => _selectedIndex = i),
                children: widget.durationsMinutes
                    .map((m) => Center(
                          child: Text(
                            _formatMinutes(m),
                            style: const TextStyle(fontSize: 18, color: Colors.black),
                          ),
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatMinutes(int m) {
    if (m >= 60) {
      final h = m ~/ 60;
      final rem = m % 60;
      if (rem == 0) return '$h h';
      return '$h h $rem min';
    }
    return '$m min';
  }
}
