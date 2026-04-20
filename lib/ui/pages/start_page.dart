import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../widgets/gradient_pill_button.dart';
import '../widgets/gradient_background.dart';
import '../theme/app_colors.dart';
import 'package:hbcure/ui/main_shell.dart';
import 'package:hbcure/services/program_language_controller.dart';
import 'package:hbcure/ui/pages/first_steps_page.dart';

class StartPage extends StatefulWidget {
  const StartPage({super.key});

  @override
  State<StartPage> createState() => _StartPageState();
}

class _StartPageState extends State<StartPage> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeIn;
  late final Animation<double> _slideUp;
  late final VoidCallback _langListener;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..forward();
    _fadeIn = CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.6, curve: Curves.easeOut));
    _slideUp = CurvedAnimation(parent: _controller, curve: const Interval(0.3, 1.0, curve: Curves.easeOut));
    _langListener = () { if (mounted) setState(() {}); };
    ProgramLangController.instance.addListener(_langListener);
  }

  @override
  void dispose() {
    ProgramLangController.instance.removeListener(_langListener);
    _controller.dispose();
    super.dispose();
  }

  void _enter() {
    debugPrint('[StartPage] _enter() tapped!');
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const MainShell()));
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isDe = ProgramLangController.instance.lang == ProgramLang.de;
    return GradientBackground(
      child: Stack(
        children: [
          // Main content
          LayoutBuilder(builder: (context, constraints) {
            final safeVertical = media.padding.top + media.padding.bottom;
            final availableHeight = (constraints.maxHeight - safeVertical).clamp(0.0, double.infinity);
            final iconSize = math.min(180.0, availableHeight * 0.28);
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
                      // Shift content upward
                      SizedBox(height: math.max(0, availableHeight * 0.02 - 20)),
                      // App icon
                      FadeTransition(
                        opacity: _fadeIn,
                        child: Container(
                          width: iconSize,
                          height: iconSize,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(iconSize * 0.22),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.35),
                                blurRadius: 32,
                                offset: const Offset(0, 12),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(iconSize * 0.22),
                            child: Image.asset('assets/icon.png', fit: BoxFit.contain),
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      // Title + subtitle + buttons
                      AnimatedBuilder(
                        animation: _slideUp,
                        builder: (context, child) => Transform.translate(
                          offset: Offset(0, 30 * (1 - _slideUp.value)),
                          child: Opacity(opacity: _slideUp.value, child: child),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'HB Healing & Balance',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                                color: AppColors.textPrimary,
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              isDe ? 'Frequenztherapie' : 'Frequency Therapy',
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: AppColors.textPrimary.withValues(alpha: 0.6),
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 36),
                            GradientPillButton(title: isDe ? 'App starten' : 'Start App', icon: Icons.arrow_forward, onTap: _enter),
                            const SizedBox(height: 14),
                            TextButton(
                              onPressed: () {
                                debugPrint('[StartPage] Erste Schritte tapped');
                                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FirstStepsPage()));
                              },
                              child: Text(
                                isDe ? 'Erste Schritte' : 'Getting Started',
                                style: TextStyle(
                                  color: AppColors.textPrimary.withValues(alpha: 0.55),
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Bottom spacer to push content upward visually
                      SizedBox(height: availableHeight * 0.08),
                    ],
                  ),
                ),
              ),
            );
          }),
          // Language toggle top-right (must be AFTER LayoutBuilder to be on top)
          Positioned(
            top: media.padding.top + 12,
            right: 16,
            child: FadeTransition(
              opacity: _fadeIn,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _langButton('DE'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text('|', style: TextStyle(color: AppColors.textPrimary.withValues(alpha: 0.4), fontSize: 14, decoration: TextDecoration.none)),
                  ),
                  _langButton('EN'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _langButton(String code) {
    final currentCode = ProgramLangController.instance.lang == ProgramLang.de ? 'DE' : 'EN';
    final isActive = currentCode == code;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        debugPrint('[StartPage] lang toggle tapped: $code');
        ProgramLangController.instance.setLang(code == 'DE' ? ProgramLang.de : ProgramLang.en);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Text(
          code,
          style: TextStyle(
            color: isActive ? AppColors.textPrimary : AppColors.textPrimary.withValues(alpha: 0.4),
            fontSize: 14,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}
