import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/file_utils.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/widgets/karlshare_avatar.dart';
import '../../../models/enums.dart';
import '../../../models/transfer.dart';

/// One transfer session in the History list. Tapping expands the row to
/// reveal individual files (Section 6.6).
class HistoryTile extends StatefulWidget {
  const HistoryTile({super.key, required this.transfer});

  final Transfer transfer;

  @override
  State<HistoryTile> createState() => _HistoryTileState();
}

class _HistoryTileState extends State<HistoryTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.transfer;
    final colors = Theme.of(context).extension<KarlshareColors>()!;
    final isSent = t.direction == TransferDirection.sent;

    return AnimatedContainer(
      duration: AppConstants.microInteraction,
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
        border: Border.all(color: colors.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
            child: Padding(
              padding: const EdgeInsets.all(AppConstants.space12),
              child: Row(
                children: [
                  KarlshareAvatar(name: t.device.name, size: 44),
                  const SizedBox(width: AppConstants.space12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.device.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(
                              isSent
                                  ? Icons.north_east_rounded
                                  : Icons.south_west_rounded,
                              size: 14,
                              color: colors.textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                '${t.fileCount} ${t.fileCount == 1 ? "file" : "files"} · ${FormatUtils.fileSize(t.totalBytes)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style:
                                    Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppConstants.space8),
                  Text(
                    FormatUtils.clockTime(t.timestamp),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(width: AppConstants.space4),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: AppConstants.microInteraction,
                    child: const Icon(Icons.expand_more_rounded, size: 20),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: AppConstants.microInteraction,
            curve: AppConstants.easeOutKarlshare,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppConstants.space12,
                      0,
                      AppConstants.space12,
                      AppConstants.space12,
                    ),
                    child: Column(
                      children: [
                        Divider(color: colors.border, height: 1),
                        const SizedBox(height: AppConstants.space8),
                        for (final f in t.files)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Icon(
                                  FileUtils.icon(f.type),
                                  size: 16,
                                  color: FileUtils.color(f.type),
                                ),
                                const SizedBox(width: AppConstants.space8),
                                Expanded(
                                  child: Text(
                                    f.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                  ),
                                ),
                                Text(
                                  FormatUtils.fileSize(f.sizeBytes),
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(color: colors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
