import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// A simple bottom-sheet intensity picker from 0 to 100 percent.
/// Use via showModalBottomSheet(...) and provide initialValue and onSelected callback.
class IntensityPicker extends StatefulWidget {
  final int initialValue;
  final ValueChanged<int> onSelected;

  const IntensityPicker({super.key, required this.initialValue, required this.onSelected});

  @override
  State<IntensityPicker> createState() => _IntensityPickerState();
}

class _IntensityPickerState extends State<IntensityPicker> {
  late double _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue.clamp(0, 100).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox(width: 48),
              const Text('Intensity', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18, decoration: TextDecoration.none), textScaleFactor: 1.0),
              ElevatedButton(
                onPressed: () {
                  widget.onSelected(_value.round());
                  Navigator.of(context).pop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                child: const Text('Done'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            color: Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '${_value.round()} %',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.none,
              ),
              textScaleFactor: 1.0,
            ),
          ),
          const SizedBox(height: 20),
          SliderTheme(
            data: SliderThemeData(
              thumbColor: AppColors.primary,
              activeTrackColor: AppColors.primary,
              inactiveTrackColor: AppColors.primaryMuted,
              activeTickMarkColor: Colors.transparent,
              inactiveTickMarkColor: Colors.transparent,
              overlayColor: AppColors.primary.withOpacity(0.12),
              valueIndicatorColor: AppColors.primary,
              showValueIndicator: ShowValueIndicator.never,
              trackHeight: 4.0,
              tickMarkShape: const RoundSliderTickMarkShape(tickMarkRadius: 0),
            ),
            child: Slider(
              value: _value,
              min: 0,
              max: 100,
              divisions: null,
              label: '${_value.round()}%',
              onChanged: (v) => setState(() => _value = v),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
