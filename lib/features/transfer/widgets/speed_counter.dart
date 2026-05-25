import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_gradients.dart';
import '../../../core/utils/format_utils.dart';

/// Big JetBrains-Mono speed readout shown in the transfer hero (Section 6.5).
class SpeedCounter extends StatelessWidget {
  const SpeedCounter({
    super.key,
    required this.bytesPerSec,
    required this.etaSeconds,
  });

  final double bytesPerSec;
  final double etaSeconds;

  @override
  Widget build(BuildContext context) {
    final speedText = FormatUtils.speed(bytesPerSec);
    return Column(
      children: [
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (b) => AppGradients.horizontal.createShader(b),
          child: Text(
            speedText,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 36,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'ETA ${FormatUtils.eta(etaSeconds)}',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).textTheme.bodyMedium?.color,
          ),
        ),
      ],
    );
  }
}
