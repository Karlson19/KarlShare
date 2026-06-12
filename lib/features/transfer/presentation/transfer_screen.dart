import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/route_paths.dart';
import '../../../core/theme/app_theme.dart';
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
    final active = ref.read(focusedTransferProvider);
    if (active != null && active.status != TransferStatus.completed) return;

    final files = ref.read(selectedFilesProvider);
    final device = ref.read(selectedDeviceProvider);
    if (files.isEmpty || device == null) {
      setState(() {
        _startError = files.isEmpty
            ? 'Pick at least one file before sending.'
            : "Tap a device on the radar first — we don't know who to send to yet.";
      });
      return;
    }

    final started = await ref
        .read(transferSessionProvider.notifier)
        .start(device: device, files: files);
    if (!started && mounted) {
      setState(() {
        _startError = device.ipAddress == null
            ? "Still connecting to ${device.name}. Wait for the peer to accept on their phone, then try again."
            : "Couldn't start the transfer. Make sure both devices are running Karlshare on Android.";
      });
    }
  }

  void _cancel() {
    ref.read(transferSessionProvider.notifier).cancel();
    ref.read(selectedFilesProvider.notifier).state = [];
    ref.read(selectedDeviceProvider.notifier).state = null;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(RoutePaths.home);
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

    final transfer = ref.watch(focusedTransferProvider);
    final notifier = ref.read(transferSessionProvider.notifier);
    final profile = ref.watch(userProfileProvider);
    final avatarIndex = profile?.avatarIndex ?? 0;

    if (transfer != null &&
        transfer.status == TransferStatus.completed &&
        !_navigatedDone) {
      _navigatedDone = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.pushReplacement(RoutePaths.transferComplete);
      });
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Scaffold(
        body: SafeArea(
          child: transfer == null
              ? _Pending(error: _startError, onBack: _cancel)
              : Column(
                  children: [
                    _Header(transfer: transfer, onCancel: _cancel),
                    if (transfer.status == TransferStatus.failed &&
                        notifier.lastError != null)
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
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppConstants.space16,
                        vertical: AppConstants.space8,
                      ),
                      child: TransferAnimation(
                        transfer: transfer,
                        meAvatarIndex: avatarIndex,
                        etaSeconds: notifier.etaSeconds,
                      ),
                    ),
                    Expanded(child: _FileList(transfer: transfer)),
                  ],
                ),
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

class _Header extends StatelessWidget {
  const _Header({required this.transfer, required this.onCancel});

  final Transfer transfer;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final status = switch (transfer.status) {
      TransferStatus.transferring =>
        '${transfer.direction == TransferDirection.sent ? "Sending to" : "Receiving from"} ${transfer.device.name}',
      // The retry flow re-uses TransferStatus.paused — it's the only thing
      // that ever sets paused now (real pause/resume is v1.1).
      TransferStatus.paused => 'Reconnecting to ${transfer.device.name}…',
      TransferStatus.completed => 'Done',
      TransferStatus.pending => 'Connecting…',
      TransferStatus.failed => 'Failed',
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.space8,
        AppConstants.space8,
        AppConstants.space8,
        0,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onCancel,
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Cancel',
          ),
          Expanded(
            child: Text(
              status,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          const SizedBox(width: 48), // balance the leading IconButton
        ],
      ),
    );
  }
}

class _FileList extends StatelessWidget {
  const _FileList({required this.transfer});

  final Transfer transfer;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KarlshareColors>()!;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.space16,
        AppConstants.space8,
        AppConstants.space16,
        AppConstants.space24,
      ),
      itemCount: transfer.files.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppConstants.space8),
      itemBuilder: (context, i) {
        final file = transfer.files[i];
        return _FileRow(file: file, borderColor: colors.border);
      },
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.file, required this.borderColor});

  final TransferFile file;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    final accent = FileUtils.color(file.type);
    final done = file.progress >= 1.0;
    return Row(
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
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
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
                borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                child: LinearProgressIndicator(
                  value: file.progress,
                  minHeight: 4,
                  backgroundColor: borderColor,
                  valueColor: AlwaysStoppedAnimation(accent),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppConstants.space12),
        SizedBox(
          width: 18,
          height: 18,
          child: done
              ? const Icon(Icons.check_circle_rounded, size: 18)
              : null,
        ),
      ],
    );
  }
}
