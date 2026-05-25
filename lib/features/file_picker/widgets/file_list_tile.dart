import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/file_utils.dart';
import '../../../core/utils/format_utils.dart';
import '../../../models/transfer_file.dart';

/// List row for documents, music and apps (Section 6.4). Single-color accent
/// for selection state — the previous gradient check competed with the
/// gradient summary card.
class FileListTile extends StatelessWidget {
  const FileListTile({
    super.key,
    required this.file,
    required this.selected,
    required this.onToggle,
  });

  final TransferFile file;
  final bool selected;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final accent = FileUtils.color(file.type);
    final colors = Theme.of(context).extension<KarlshareColors>()!;

    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(AppConstants.radiusSmall),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.space16,
          vertical: AppConstants.space12,
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppConstants.radiusSmall),
              ),
              child: Icon(FileUtils.icon(file.type), color: accent, size: 22),
            ),
            const SizedBox(width: AppConstants.space16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    FormatUtils.fileSize(file.sizeBytes),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppConstants.space12),
            _SelectCircle(
              selected: selected,
              accent: colors.accent,
              borderColor: colors.borderStrong,
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectCircle extends StatelessWidget {
  const _SelectCircle({
    required this.selected,
    required this.accent,
    required this.borderColor,
  });

  final bool selected;
  final Color accent;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppConstants.microInteraction,
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: selected ? accent : null,
        shape: BoxShape.circle,
        border: selected ? null : Border.all(color: borderColor, width: 1.5),
      ),
      child: selected
          ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
          : null,
    );
  }
}
