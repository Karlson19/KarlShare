import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/route_paths.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/widgets/karlshare_avatar.dart';
import '../../../core/widgets/karlshare_button.dart';
import '../../../models/device.dart';
import '../../../models/enums.dart';
import '../../history/providers/history_provider.dart';
import '../../transfer/providers/transfer_provider.dart';
import '../providers/discovery_provider.dart';

/// Quick-action sheet shown when tapping a device on the radar (Section 6.9).
class DeviceDetailSheet extends ConsumerWidget {
  const DeviceDetailSheet({super.key, required this.device});

  final Device device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = device.status == DeviceStatus.busy;
    final recent = ref
        .watch(historyProvider)
        .where((t) => t.device.id == device.id)
        .take(3)
        .toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        KarlshareAvatar(name: device.name, size: 72),
        const SizedBox(height: AppConstants.space16),
        Text(device.name, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: AppConstants.space4),
        Text(
          busy ? 'Currently busy' : 'Ready to receive',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: AppConstants.space24),
        KarlshareButton(
          label: 'Send Files',
          onPressed: busy
              ? null
              : () async {
                  ref.read(selectedDeviceProvider.notifier).state = device;
                  // Kick off the WiFi Direct connect now so by the time the
                  // user has picked files, group formation has (hopefully)
                  // completed and the peer IP is on the device.
                  final address = device.address;
                  if (address != null && address.isNotEmpty) {
                    await ref
                        .read(discoveryServiceProvider)
                        .connect(address);
                  }
                  if (!context.mounted) return;
                  context.pop();
                  context.push(RoutePaths.filePicker);
                },
        ),
        if (recent.isNotEmpty) ...[
          const SizedBox(height: AppConstants.space24),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Recent', style: Theme.of(context).textTheme.labelSmall),
          ),
          const SizedBox(height: AppConstants.space8),
          for (final t in recent)
            Padding(
              padding: const EdgeInsets.only(bottom: AppConstants.space8),
              child: Row(
                children: [
                  Icon(
                    t.direction == TransferDirection.sent
                        ? Icons.north_east_rounded
                        : Icons.south_west_rounded,
                    size: 18,
                    color: Theme.of(context).textTheme.bodyMedium?.color,
                  ),
                  const SizedBox(width: AppConstants.space8),
                  Expanded(
                    child: Text(
                      '${t.fileCount} ${t.fileCount == 1 ? "file" : "files"} · ${FormatUtils.fileSize(t.totalBytes)}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  Text(
                    FormatUtils.clockTime(t.timestamp),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
