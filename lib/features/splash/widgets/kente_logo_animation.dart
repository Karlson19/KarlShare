import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/sankofa_mark.dart';

/// Splash hero: geometric Kente strands weave in, then the Sankofa mark
/// materializes on top (Section 6.1).
class KenteLogoAnimation extends StatelessWidget {
  const KenteLogoAnimation({super.key, this.size = 132});

  final double size;

  static const _grid = 5;
  static const _palette = [
    AppColors.karlshareOrange,
    AppColors.royalMagenta,
    AppColors.electricPurple,
    AppColors.ashantiGold,
  ];

  @override
  Widget build(BuildContext context) {
    const gap = 6.0;
    final cell = (size - gap * (_grid - 1)) / _grid;

    final tiles = <Widget>[];
    for (var r = 0; r < _grid; r++) {
      for (var c = 0; c < _grid; c++) {
        final color = _palette[(r + c) % _palette.length];
        // Diagonal stagger -> a weaving wave across the grid.
        final delayMs = (r + c) * 55;
        tiles.add(
          Positioned(
            left: c * (cell + gap),
            top: r * (cell + gap),
            child: Container(
              width: cell,
              height: cell,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
              ),
            )
                .animate()
                .scaleXY(
                  begin: 0,
                  end: 1,
                  duration: 360.ms,
                  delay: delayMs.ms,
                  curve: Curves.easeOutBack,
                )
                .fadeIn(duration: 240.ms, delay: delayMs.ms),
          ),
        );
      }
    }

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Woven strands fade back once the mark takes over.
          ...tiles,
          Opacity(opacity: 0, child: SizedBox(width: size, height: size)),
          Positioned.fill(
            child: Center(
              child: SankofaMark(size: size * 0.62)
                  .animate()
                  .scaleXY(
                    begin: 0.6,
                    end: 1,
                    duration: AppConstants.heroMoment,
                    delay: 700.ms,
                    curve: AppConstants.easeOutKarlshare,
                  )
                  .fadeIn(duration: 500.ms, delay: 700.ms),
            ),
          ),
        ],
      ),
    );
  }
}
