import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/widgets/karlshare_avatar.dart';
import '../../../models/device.dart';
import '../../../models/enums.dart';

/// A discovered device floating on the radar. Scales in with a spring and
/// shows a short name label (Section 6.3).
///
/// The name pill uses a translucent black background regardless of theme so
/// it stays legible against either the dark radar or a light scaffold.
class DeviceAvatar extends StatelessWidget {
  const DeviceAvatar({super.key, required this.device, required this.onTap});

  final Device device;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final busy = device.status == DeviceStatus.busy;
    final shortName = device.name.split(RegExp(r'[ ·]')).first;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Opacity(
            opacity: busy ? 0.5 : 1,
            child: KarlshareAvatar(name: device.name, size: 52),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(AppConstants.radiusPill),
            ),
            child: Text(
              shortName,
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyMedium?.color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    )
        .animate()
        .scaleXY(
          begin: 0,
          end: 1,
          duration: AppConstants.microInteraction,
          curve: Curves.easeOutBack,
        )
        .fadeIn(duration: 150.ms);
  }
}
