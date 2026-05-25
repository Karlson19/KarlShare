import 'package:flutter/material.dart';
import '../../../core/constants/avatar_presets.dart';
import '../../../core/utils/file_utils.dart';
import '../../../core/widgets/karlshare_avatar.dart';
import '../../../models/enums.dart';
import '../../../models/transfer.dart';
import 'particle_painter.dart';
import 'speed_counter.dart';

/// The hero transfer visual: two avatars with a stream of file packets
/// flowing between them, plus the central speed/ETA counter (Section 6.5).
class TransferAnimation extends StatefulWidget {
  const TransferAnimation({
    super.key,
    required this.transfer,
    required this.meAvatarIndex,
    required this.etaSeconds,
  });

  final Transfer transfer;
  final int meAvatarIndex;
  final double etaSeconds;

  @override
  State<TransferAnimation> createState() => _TransferAnimationState();
}

class _TransferAnimationState extends State<TransferAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  late List<FileParticle> _particles = _buildParticles();

  @override
  void didUpdateWidget(covariant TransferAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.transfer.id != widget.transfer.id ||
        oldWidget.transfer.files.length != widget.transfer.files.length) {
      _particles = _buildParticles();
    }
  }

  List<FileParticle> _buildParticles() {
    final icons = widget.transfer.files
        .map((f) => FileUtils.icon(f.type))
        .toList(growable: false);
    if (icons.isEmpty) {
      return FileParticle.generate(count: 1, icons: const [Icons.insert_drive_file_rounded]);
    }
    final count = icons.length.clamp(3, 12);
    return FileParticle.generate(count: count, icons: icons);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reversed = widget.transfer.direction == TransferDirection.received;
    final running = widget.transfer.status == TransferStatus.transferring;

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: RepaintBoundary(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) => CustomPaint(
                      painter: FileParticlePainter(
                        t: running ? _controller.value : 0,
                        particles: _particles,
                        reversed: reversed,
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: KarlshareAvatar(
                      icon: AvatarPresets.byIndex(widget.meAvatarIndex),
                      size: 64,
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: KarlshareAvatar(
                      name: widget.transfer.device.name,
                      size: 64,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: SpeedCounter(
                    bytesPerSec: widget.transfer.speedBytesPerSec,
                    etaSeconds: widget.etaSeconds,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
