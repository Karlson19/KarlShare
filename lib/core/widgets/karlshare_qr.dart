import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../constants/app_constants.dart';
import '../theme/app_colors.dart';
import '../theme/app_gradients.dart';

/// The branded QR card: a gradient frame around a white tile holding the code,
/// using Karlshare's purple eyes and dark modules. Shared by every screen that
/// presents a connect code so they stay visually identical.
class KarlshareQr extends StatelessWidget {
  const KarlshareQr({super.key, required this.data, this.size = 232});

  final String data;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        gradient: AppGradients.signature,
        borderRadius: BorderRadius.circular(AppConstants.radiusLarge),
      ),
      child: Container(
        padding: const EdgeInsets.all(AppConstants.space16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppConstants.radiusLarge - 4),
        ),
        child: QrImageView(
          data: data,
          size: size,
          eyeStyle: const QrEyeStyle(
            eyeShape: QrEyeShape.square,
            color: AppColors.electricPurple,
          ),
          dataModuleStyle: const QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.square,
            color: Color(0xFF15131F),
          ),
        ),
      ),
    );
  }
}
