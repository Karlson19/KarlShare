import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_gradients.dart';

/// Welcome-screen illustration: two phones joined by a gradient beam with
/// particles flowing between them (Section 6.2 screen 1).
class ConnectionHero extends StatelessWidget {
  const ConnectionHero({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Beam
          Container(
            height: 4,
            margin: const EdgeInsets.symmetric(horizontal: 70),
            decoration: BoxDecoration(
              gradient: AppGradients.horizontal,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Flowing particles
          for (var i = 0; i < 4; i++)
            _Particle(delayMs: i * 450),
          // Phones
          const Align(alignment: Alignment.centerLeft, child: _Phone()),
          const Align(alignment: Alignment.centerRight, child: _Phone()),
        ],
      ),
    );
  }
}

class _Phone extends StatelessWidget {
  const _Phone();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 124,
      decoration: BoxDecoration(
        gradient: AppGradients.signature,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(2.5),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(13.5),
        ),
        alignment: Alignment.center,
        child: ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (b) => AppGradients.signature.createShader(b),
          child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 26),
        ),
      ),
    );
  }
}

class _Particle extends StatelessWidget {
  const _Particle({required this.delayMs});

  final int delayMs;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 9,
      height: 9,
      decoration: const BoxDecoration(
        color: AppColors.ashantiGold,
        shape: BoxShape.circle,
      ),
    )
        .animate(onPlay: (c) => c.repeat())
        .moveX(
          begin: -70,
          end: 70,
          duration: 1800.ms,
          delay: delayMs.ms,
          curve: Curves.easeInOut,
        )
        .fadeIn(duration: 300.ms, delay: delayMs.ms)
        .fadeOut(begin: 1, delay: (delayMs + 1500).ms, duration: 300.ms);
  }
}
