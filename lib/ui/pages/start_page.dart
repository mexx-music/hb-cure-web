import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../widgets/rotating_pyramid.dart';
import '../widgets/gradient_pill_button.dart';
import '../widgets/gradient_background.dart';
import '../theme/app_colors.dart';
import 'package:hbcure/ui/main_shell.dart';

class StartPage extends StatefulWidget {
  const StartPage({super.key});

  @override
  State<StartPage> createState() => _StartPageState();
}

class _StartPageState extends State<StartPage> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _rotation;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 12))..repeat();
    _rotation = CurvedAnimation(parent: _controller, curve: Curves.linear);
    _fade = CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.18, curve: Curves.easeIn));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _enter() {
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const MainShell()));
  }

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: LayoutBuilder(builder: (context, constraints) {
        final media = MediaQuery.of(context);
        final safeVertical = media.padding.top + media.padding.bottom;
        final availableHeight = (constraints.maxHeight - safeVertical).clamp(0.0, double.infinity);
        // Calculate a responsive pyramid size so the visual fits on small screens
        final pyramidSize = math.min(160.0, availableHeight * 0.22);
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 20.0),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: availableHeight),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  RotatingPyramid(rotation: _rotation, size: pyramidSize),
                  const SizedBox(height: 20),
                  FadeTransition(
                    opacity: _fade,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Cure App', style: Theme.of(context).textTheme.displaySmall?.copyWith(color: AppColors.textPrimary, fontSize: 32, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        // Use GradientPillButton as Enter button
                        GradientPillButton(title: 'Enter', icon: Icons.arrow_forward, onTap: _enter),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}
