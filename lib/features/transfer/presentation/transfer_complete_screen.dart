import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/widgets/karlshare_button.dart';
import '../../../core/widgets/sankofa_mark.dart';
import '../../../models/device.dart';
import '../../../models/enums.dart';
import '../../../models/transfer.dart';
import '../providers/transfer_provider.dart';

class TransferCompleteScreen extends ConsumerStatefulWidget {
  const TransferCompleteScreen({super.key});

  @override
  ConsumerState<TransferCompleteScreen> createState() =>
      _TransferCompleteScreenState();
}

class _TransferCompleteScreenState
    extends ConsumerState<TransferCompleteScreen> {
  late final Transfer? _snapshot;
  late final double _elapsedSeconds;

  @override
  void initState() {
    super.initState();
    _snapshot = ref.read(activeTransferProvider);
    _elapsedSeconds =
        ref.read(activeTransferProvider.notifier).elapsedSeconds;
    // Celebratory thud as the success burst plays (Section 6.5 hero moment).
    HapticFeedback.heavyImpact();
  }

  /// Clears the finished transfer. [keepDevice] preserves the connected peer
  /// so "Send More" goes straight to picking files for the same device — the
  /// session persists instead of forcing a re-scan for every send.
  void _reset({bool keepDevice = false}) {
    ref.read(activeTransferProvider.notifier).cancel();
    ref.read(selectedFilesProvider.notifier).state = [];
    if (!keepDevice) {
      ref.read(selectedDeviceProvider.notifier).state = null;
    }
  }

  /// The folder a received transfer was saved into, derived from the first
  /// file's saved path (handles both / and \ separators).
  String? _savedDir(Transfer? transfer) {
    if (transfer == null) return null;
    for (final f in transfer.files) {
      final p = f.path;
      if (p != null && p.isNotEmpty) {
        final i = p.lastIndexOf(RegExp(r'[\\/]'));
        if (i > 0) return p.substring(0, i);
      }
    }
    return null;
  }

  void _openFolder(String dir) {
    try {
      if (Platform.isWindows) {
        Process.run('explorer', [dir]);
      } else if (Platform.isMacOS) {
        Process.run('open', [dir]);
      } else if (Platform.isLinux) {
        Process.run('xdg-open', [dir]);
      }
    } catch (_) {
      // Best effort; the path is shown on screen as a fallback.
    }
  }

  /// Send files back to whoever we just received from, keeping that device
  /// selected so the file picker goes straight to the transfer.
  void _sendBack(Device device) {
    ref.read(activeTransferProvider.notifier).cancel();
    ref.read(selectedFilesProvider.notifier).state = [];
    ref.read(selectedDeviceProvider.notifier).state = device;
    context.go(RoutePaths.filePicker);
  }

  Widget _actions({
    required Transfer? transfer,
    required bool isReceived,
    required String? savedDir,
  }) {
    final isDesktop =
        !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
    final back = transfer?.device;
    final backIp = back?.ipAddress;
    final canSendBack = backIp != null && backIp.isNotEmpty;

    // Sent transfer: offer another send or go home.
    if (!isReceived) {
      return Row(
        children: [
          Expanded(
            child: KarlshareButton(
              label: 'Send More',
              variant: KarlshareButtonVariant.secondary,
              onPressed: () {
                _reset(keepDevice: true);
                context.go(RoutePaths.filePicker);
              },
            ),
          ),
          const SizedBox(width: AppConstants.space16),
          Expanded(
            child: KarlshareButton(
              label: 'Done',
              onPressed: () {
                _reset();
                context.go(RoutePaths.home);
              },
            ),
          ),
        ],
      );
    }

    // Received transfer: open the folder (desktop) and optionally send back.
    return Column(
      children: [
        Row(
          children: [
            if (isDesktop && savedDir != null) ...[
              Expanded(
                child: KarlshareButton(
                  label: 'Open folder',
                  icon: Icons.folder_open_rounded,
                  variant: KarlshareButtonVariant.secondary,
                  onPressed: () => _openFolder(savedDir),
                ),
              ),
              const SizedBox(width: AppConstants.space16),
            ],
            Expanded(
              child: KarlshareButton(
                label: 'Done',
                onPressed: () {
                  _reset();
                  context.go(RoutePaths.home);
                },
              ),
            ),
          ],
        ),
        if (canSendBack) ...[
          const SizedBox(height: AppConstants.space8),
          TextButton.icon(
            onPressed: () => _sendBack(back!),
            icon: const Icon(Icons.reply_rounded),
            label: const Text('Send a file back'),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final transfer = _snapshot;
    final fileCount = transfer?.fileCount ?? 0;
    final direction = transfer?.direction ?? TransferDirection.sent;
    final action = direction == TransferDirection.sent ? 'sent' : 'received';
    final summary = transfer == null
        ? "All done."
        : '$fileCount ${fileCount == 1 ? "file" : "files"} $action in ${FormatUtils.eta(_elapsedSeconds)}';
    final total = transfer?.totalBytes ?? 0;
    final isReceived = direction == TransferDirection.received;
    final savedDir = _savedDir(transfer);

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            const Positioned.fill(
              child: IgnorePointer(child: _ConfettiBurst()),
            ),
            Padding(
              padding: const EdgeInsets.all(AppConstants.space24),
              child: Column(
                children: [
                  const Spacer(),
                  const SankofaMark(size: 120)
                      .animate()
                      .scaleXY(
                        begin: 0.4,
                        end: 1,
                        duration: AppConstants.heroMoment,
                        curve: Curves.elasticOut,
                      )
                      .fadeIn(duration: 300.ms),
                  const SizedBox(height: AppConstants.space24),
                  Text(
                    direction == TransferDirection.sent
                        ? 'Sent!'
                        : 'Received!',
                    style: Theme.of(context).textTheme.displayMedium,
                  )
                      .animate(delay: 200.ms)
                      .fadeIn()
                      .slideY(begin: 0.2, end: 0),
                  const SizedBox(height: AppConstants.space8),
                  Text(
                    summary,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ).animate(delay: 350.ms).fadeIn(),
                  if (total > 0) ...[
                    const SizedBox(height: AppConstants.space4),
                    Text(
                      FormatUtils.fileSize(total),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ).animate(delay: 450.ms).fadeIn(),
                  ],
                  if (isReceived && savedDir != null) ...[
                    const SizedBox(height: AppConstants.space8),
                    Text(
                      'Saved to $savedDir',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ).animate(delay: 500.ms).fadeIn(),
                  ],
                  const Spacer(),
                  _actions(
                    transfer: transfer,
                    isReceived: isReceived,
                    savedDir: savedDir,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lightweight confetti — small rectangles in the brand palette falling from
/// the top with rotation. Capped per Section 16 low-end perf guardrail.
class _ConfettiBurst extends StatefulWidget {
  const _ConfettiBurst();

  @override
  State<_ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<_ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..forward();

  late final List<_Confetto> _pieces = _generate();

  static const int _count = 28;

  List<_Confetto> _generate() {
    final rnd = math.Random(11);
    const palette = [
      AppColors.karlshareOrange,
      AppColors.royalMagenta,
      AppColors.electricPurple,
      AppColors.ashantiGold,
    ];
    return List.generate(_count, (i) {
      return _Confetto(
        x: rnd.nextDouble(),
        delay: rnd.nextDouble() * 0.3,
        speed: 0.7 + rnd.nextDouble() * 0.5,
        drift: (rnd.nextDouble() - 0.5) * 0.25,
        color: palette[i % palette.length],
        spin: rnd.nextDouble() * math.pi * 4,
        size: 6 + rnd.nextDouble() * 6,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            size: Size.infinite,
            painter: _ConfettiPainter(t: _controller.value, pieces: _pieces),
          );
        },
      ),
    );
  }
}

class _Confetto {
  const _Confetto({
    required this.x,
    required this.delay,
    required this.speed,
    required this.drift,
    required this.color,
    required this.spin,
    required this.size,
  });

  final double x;
  final double delay;
  final double speed;
  final double drift;
  final Color color;
  final double spin;
  final double size;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.t, required this.pieces});

  final double t;
  final List<_Confetto> pieces;

  @override
  void paint(Canvas canvas, Size size) {
    for (final piece in pieces) {
      final local = ((t - piece.delay) / (1 - piece.delay)).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final y = size.height * local * piece.speed;
      final x = (piece.x + piece.drift * local) * size.width;
      final paint = Paint()
        ..color = piece.color.withValues(alpha: 1 - local * 0.6)
        ..style = PaintingStyle.fill;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(piece.spin * local);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: piece.size,
            height: piece.size * 0.5,
          ),
          const Radius.circular(1.5),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}
