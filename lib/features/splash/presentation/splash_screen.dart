import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/gradient_text.dart';
import '../../../providers/user_provider.dart';
import '../widgets/kente_logo_animation.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Hold long enough to actually watch the Kente strands weave into the
    // Sankofa mark, then the wordmark and tagline settle.
    _timer = Timer(const Duration(milliseconds: 2800), _goNext);
  }

  void _goNext() {
    if (!mounted) return;
    final onboarded = ref.read(hasOnboardedProvider);
    context.go(onboarded ? RoutePaths.home : RoutePaths.onboarding);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const KenteLogoAnimation(),
            const SizedBox(height: AppConstants.space32),
            GradientText(
              AppConstants.appName,
              style: Theme.of(context)
                  .textTheme
                  .displayMedium
                  ?.copyWith(color: Colors.white),
            ).animate().fadeIn(duration: 500.ms, delay: 1200.ms).slideY(
                  begin: 0.3,
                  end: 0,
                  duration: 500.ms,
                  delay: 1200.ms,
                  curve: AppConstants.easeOutKarlshare,
                ),
            const SizedBox(height: AppConstants.space12),
            Text(
              AppConstants.tagline,
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(color: AppColors.darkTextSecondary),
            ).animate().fadeIn(duration: 500.ms, delay: 1500.ms),
          ],
        ),
      ),
    );
  }
}
