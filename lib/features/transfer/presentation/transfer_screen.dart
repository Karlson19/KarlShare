import 'dart:io' show Platform, Process;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/file_utils.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/widgets/karlshare_button.dart';
import '../../../models/enums.dart';
import '../../../models/transfer.dart';
import '../../../models/transfer_file.dart';
import '../../../providers/user_provider.dart';
import '../../home/providers/discovery_provider.dart';
import '../providers/transfer_provider.dart';
import '../widgets/transfer_animation.dart';

/// The session view: every transfer in the exchange, both directions at once,
/// impossible to misread. "Receiving" (forest green) and "Sending" (gold) are
/// separate, labeled sections; per-file cards show queued / transferring /
/// done / failed states; the session header keeps aggregate stats sticky.
///
/// Leaving this screen never kills transfers — the session state outlives
/// navigation (Phase 0). Cancelling is an explicit per-transfer action.
class TransferScreen extends ConsumerStatefulWidget {
  const TransferScreen({super.key});

  @override
  ConsumerState<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends ConsumerState<TransferScreen> {
  bool _navigatedDone = false;
  String? _startError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startIfNeeded());
  }

  Future<void> _startIfNeeded() async {
    if (!mounted) return;
    final focused = ref.read(focusedTransferProvider);
    if (focused != null && focused.status != TransferStatus.completed) return;

    final files = ref.read(selectedFilesProvider);
    final device = ref.read(selectedDeviceProvider);
    if (files.isEmpty || device == null) {
      // Arriving with nothing picked is fine when the session is already
      // alive (e.g. navigated back during an incoming transfer).
      if (ref.read(transferSessionProvider).transfers.isEmpty) {
        setState(() {
          _startError = files.isEmpty
              ? 'Pick at least one file before sending.'
              : "Tap a device on the radar first — we don't know who to send to yet.";
        });
      }
      return;
    }

    final started = await ref
        .read(transferSessionProvider.notifier)
        .start(device: device, files: files);
    if (!started && mounted) {
      setState(() {
        _startError = device.ipAddress == null
            ? "Still connecting to ${device.name}. Wait for the peer to accept, then try again."
            : "Couldn't start the transfer. Make sure Karlshare is open on the other device.";
      });
    }
  }

  void _leave() {
    // Transfers keep running; this only leaves the screen.
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(RoutePaths.home);
    }
  }

  Future<void> _retry(Transfer t) async {
    await ref.read(transferSessionProvider.notifier).cancelById(t.id);
    if (!mounted) return;
    final ok = await ref
        .read(transferSessionProvider.notifier)
        .start(device: t.device, files: t.files);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Couldn't reconnect. Check that both devices are still "
            'on the same network.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    // When group formation completes, merge the peer IP onto the selected
    // device and retry the transfer if we were waiting on it.
    ref.listen<GroupReadyInfo?>(groupReadyProvider, (_, next) {
      if (next == null) return;
      final device = ref.read(selectedDeviceProvider);
      if (device == null || device.ipAddress != null) return;
      ref.read(selectedDeviceProvider.notifier).state =
          device.copyWith(ipAddress: next.ownerIp);
      if (ref.read(focusedTransferProvider) == null) {
        setState(() => _startError = null);
        _startIfNeeded();
      }
    });

    // Haptics on the moments that matter: connection established (a new
    // transfer appears), transfer complete, transfer failed. No-ops on
    // desktop.
    ref.listen<TransferSession>(transferSessionProvider, (prev, next) {
      final before = prev?.transfers ?? const <String, Transfer>{};
      for (final t in next.transfers.values) {
        final old = before[t.id]?.status;
        if (old == t.status) continue;
        if (old == null && t.status == TransferStatus.transferring) {
          HapticFeedback.lightImpact();
        } else if (t.status == TransferStatus.completed) {
          HapticFeedback.mediumImpact();
        } else if (t.status == TransferStatus.failed) {
          HapticFeedback.heavyImpact();
        }
      }
    });

    final session = ref.watch(transferSessionProvider);
    final notifier = ref.read(transferSessionProvider.notifier);
    final profile = ref.watch(userProfileProvider);
    final avatarIndex = profile?.avatarIndex ?? 0;

    // The whole session wrapped up with at least one success: celebrate.
    final transfers = session.all;
    if (transfers.isNotEmpty &&
        !session.hasActive &&
        transfers.any((t) => t.status == TransferStatus.completed) &&
        !_navigatedDone) {
      _navigatedDone = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.pushReplacement(RoutePaths.transferComplete);
      });
    }

    final focusedActive = _focusedActive(session);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: _leave,
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back (transfers continue)',
        ),
        title: Text(
          focusedActive != null
              ? (focusedActive.direction == TransferDirection.sent
                  ? 'Sending to ${focusedActive.device.name}'
                  : 'Receiving from ${focusedActive.device.name}')
              : 'Transfers',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        // Wide desktop windows get a centered column, not a stretched phone.
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: transfers.isEmpty
                ? _Pending(error: _startError, onBack: _leave)
                : Column(
                children: [
                  if (notifier.lastError != null &&
                      transfers.any((t) => t.status == TransferStatus.failed))
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppConstants.space24,
                        vertical: AppConstants.space8,
                      ),
                      child: Text(
                        notifier.lastError!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error),
                      ),
                    ),
                  if (focusedActive != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppConstants.space16,
                      ),
                      child: RepaintBoundary(
                        child: TransferAnimation(
                          transfer: focusedActive,
                          meAvatarIndex: avatarIndex,
                          etaSeconds: _sessionEta(session),
                        ),
                      ),
                    ),
                  _SessionStats(session: session),
                  Expanded(
                    child: _SessionList(
                      session: session,
                      onCancel: (t) => notifier.cancelById(t.id),
                      onRetry: _retry,
                    ),
                  ),
                ],
              ),
          ),
        ),
      ),
    );
  }

  Transfer? _focusedActive(TransferSession session) {
    final focused = session.focused;
    if (focused != null &&
        (focused.status == TransferStatus.transferring ||
            focused.status == TransferStatus.paused)) {
      return focused;
    }
    for (final t in session.all) {
      if (t.status == TransferStatus.transferring ||
          t.status == TransferStatus.paused) {
        return t;
      }
    }
    return null;
  }

  double _sessionEta(TransferSession session) {
    var remaining = 0;
    var speed = 0.0;
    for (final t in session.all) {
      if (t.status == TransferStatus.transferring) {
        remaining += t.totalBytes - t.transferredBytes;
        speed += t.speedBytesPerSec;
      }
    }
    if (speed <= 0 || remaining <= 0) return 0;
    return remaining / speed;
  }
}

/// Sticky aggregate band: big mono speed numeral, files done / total, overall
/// session progress. The numbers are the jewelry — give them the stat scale.
class _SessionStats extends StatelessWidget {
  const _SessionStats({required this.session});

  final TransferSession session;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KarlshareColors>()!;
    var totalBytes = 0;
    var doneBytes = 0;
    var filesDone = 0;
    var filesTotal = 0;
    var speed = 0.0;
    for (final t in session.all) {
      totalBytes += t.totalBytes;
      doneBytes += t.transferredBytes;
      filesTotal += t.files.length;
      filesDone += t.files.where((f) => f.progress >= 1.0).length;
      if (t.status == TransferStatus.transferring) speed += t.speedBytesPerSec;
    }
    final progress = totalBytes == 0 ? 0.0 : doneBytes / totalBytes;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.space24,
        AppConstants.space8,
        AppConstants.space24,
        AppConstants.space16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                speed > 0 ? FormatUtils.fileSize(speed.round()) : '—',
                style: AppTypography.statLarge.copyWith(color: colors.accent),
              ),
              const SizedBox(width: AppConstants.space4),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  speed > 0 ? '/s' : '',
                  style:
                      AppTypography.statSmall.copyWith(color: colors.accent),
                ),
              ),
              const Spacer(),
              Text(
                '$filesDone/$filesTotal files',
                style: AppTypography.statSmall
                    .copyWith(color: colors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.space12),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppConstants.radiusPill),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: colors.border,
            ),
          ),
        ],
      ),
    );
  }
}

/// The two-direction list: Receiving first, then Sending — labeled, color
/// coded (forest = receive, gold = send), grouped by transfer.
class _SessionList extends StatelessWidget {
  const _SessionList({
    required this.session,
    required this.onCancel,
    required this.onRetry,
  });

  final TransferSession session;
  final void Function(Transfer) onCancel;
  final void Function(Transfer) onRetry;

  @override
  Widget build(BuildContext context) {
    final received = session.received;
    final sent = session.sent;

    // Flatten into builder items so a 100-file session scrolls lazily.
    final items = <Widget>[
      if (received.isNotEmpty)
        const _SectionHeader(
          label: 'Receiving',
          icon: Icons.south_west_rounded,
          color: AppColors.forest,
        ),
      for (final t in received) ...[
        _TransferHeader(transfer: t, onCancel: onCancel, onRetry: onRetry),
        for (final f in t.files)
          _FileRow(file: f, transfer: t, key: ValueKey('${t.id}/${f.id}')),
      ],
      if (sent.isNotEmpty)
        const _SectionHeader(
          label: 'Sending',
          icon: Icons.north_east_rounded,
          color: AppColors.gold,
        ),
      for (final t in sent) ...[
        _TransferHeader(transfer: t, onCancel: onCancel, onRetry: onRetry),
        for (final f in t.files)
          _FileRow(file: f, transfer: t, key: ValueKey('${t.id}/${f.id}')),
      ],
    ];

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.space16,
        0,
        AppConstants.space16,
        AppConstants.space24,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) => items[i],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.space8,
        AppConstants.space16,
        AppConstants.space8,
        AppConstants.space8,
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: AppConstants.space8),
          Text(
            label.toUpperCase(),
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: color, letterSpacing: 1.4),
          ),
        ],
      ),
    );
  }
}

/// One transfer inside a section: peer + status + the action that fits the
/// state (cancel while running, retry when a SENT transfer failed).
class _TransferHeader extends StatelessWidget {
  const _TransferHeader({
    required this.transfer,
    required this.onCancel,
    required this.onRetry,
  });

  final Transfer transfer;
  final void Function(Transfer) onCancel;
  final void Function(Transfer) onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KarlshareColors>()!;
    final active = transfer.status == TransferStatus.transferring ||
        transfer.status == TransferStatus.paused;
    final failed = transfer.status == TransferStatus.failed;

    final statusText = switch (transfer.status) {
      TransferStatus.transferring => transfer.device.name,
      TransferStatus.paused => '${transfer.device.name} · reconnecting…',
      TransferStatus.completed => '${transfer.device.name} · done',
      TransferStatus.failed => '${transfer.device.name} · failed',
      TransferStatus.pending => '${transfer.device.name} · connecting…',
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.space8,
        AppConstants.space8,
        0,
        AppConstants.space4,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              statusText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: failed ? AppColors.error : colors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          if (failed && transfer.direction == TransferDirection.sent)
            TextButton.icon(
              onPressed: () => onRetry(transfer),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Retry'),
            ),
          if (active)
            IconButton(
              onPressed: () => onCancel(transfer),
              icon: const Icon(Icons.close_rounded, size: 18),
              tooltip: 'Cancel this transfer',
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}

/// Per-file card: type chip, name, size, live progress, state. Done files on
/// desktop reveal in the file manager when tapped.
class _FileRow extends StatelessWidget {
  const _FileRow({required this.file, required this.transfer, super.key});

  final TransferFile file;
  final Transfer transfer;

  static final bool _isDesktop =
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  void _reveal() {
    final path = file.path;
    if (path == null) return;
    try {
      if (Platform.isWindows) {
        Process.run('explorer', ['/select,$path']);
      } else if (Platform.isMacOS) {
        Process.run('open', ['-R', path]);
      } else if (Platform.isLinux) {
        final dir = path.substring(0, path.lastIndexOf('/'));
        Process.run('xdg-open', [dir]);
      }
    } catch (_) {
      // Best effort; the saved path is already shown elsewhere.
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KarlshareColors>()!;
    final accent = FileUtils.color(file.type);
    final done = file.progress >= 1.0;
    final failed = transfer.status == TransferStatus.failed && !done;
    final queued =
        file.progress <= 0 && transfer.status == TransferStatus.transferring;

    final trailing = done
        ? const Icon(Icons.check_circle_rounded,
            size: 18, color: AppColors.forest)
        : failed
            ? const Icon(Icons.error_rounded, size: 18, color: AppColors.error)
            : queued
                ? Icon(Icons.schedule_rounded,
                    size: 18, color: colors.textTertiary)
                : Text(
                    '${(file.progress * 100).round()}%',
                    style: AppTypography.statSmall
                        .copyWith(fontSize: 12, color: colors.textSecondary),
                  );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppConstants.space4),
      child: InkWell(
        onTap: done && _isDesktop && file.path != null ? _reveal : null,
        borderRadius: BorderRadius.circular(AppConstants.radiusSmall),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(AppConstants.radiusSmall),
              ),
              child: Icon(FileUtils.icon(file.type), color: accent, size: 18),
            ),
            const SizedBox(width: AppConstants.space12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          file.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: colors.textPrimary,
                                  ),
                        ),
                      ),
                      const SizedBox(width: AppConstants.space8),
                      Text(
                        FormatUtils.fileSize(file.sizeBytes),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusPill),
                    child: LinearProgressIndicator(
                      value: failed ? 0 : file.progress,
                      minHeight: 4,
                      backgroundColor: colors.border,
                      valueColor: AlwaysStoppedAnimation(
                        done ? AppColors.forest : accent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppConstants.space12),
            SizedBox(width: 36, child: Center(child: trailing)),
          ],
        ),
      ),
    );
  }
}

class _Pending extends StatelessWidget {
  const _Pending({required this.error, required this.onBack});

  final String? error;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    if (error == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final colors = Theme.of(context).extension<KarlshareColors>()!;
    return Padding(
      padding: const EdgeInsets.all(AppConstants.space24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_tethering_off_rounded,
              size: 56, color: colors.textTertiary),
          const SizedBox(height: AppConstants.space16),
          Text(
            error!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: AppConstants.space24),
          SizedBox(
            width: 220,
            child: KarlshareButton(
              label: 'Back to radar',
              icon: Icons.arrow_back_rounded,
              variant: KarlshareButtonVariant.secondary,
              onPressed: onBack,
            ),
          ),
        ],
      ),
    );
  }
}
