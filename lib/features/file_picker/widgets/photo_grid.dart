import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/file_utils.dart';
import '../../../core/utils/format_utils.dart';
import '../../../models/enums.dart';
import '../../../models/transfer_file.dart';
import '../providers/media_library_provider.dart';

/// Grid of real on-device photo / video thumbnails. Backed by photo_manager's
/// [AssetEntityImageProvider] for thumbnail decoding (Section 6.4).
///
/// Videos overlay a play glyph + duration; selection state shows a clean
/// accent border and check badge.
class PhotoGrid extends StatelessWidget {
  const PhotoGrid({
    super.key,
    required this.assets,
    required this.isSelected,
    required this.onToggle,
  });

  final List<MediaAsset> assets;
  final bool Function(String id) isSelected;
  final void Function(TransferFile) onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KarlshareColors>()!;
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.space16,
        AppConstants.space16,
        AppConstants.space16,
        120,
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: AppConstants.space8,
        crossAxisSpacing: AppConstants.space8,
      ),
      itemCount: assets.length,
      itemBuilder: (context, i) {
        final asset = assets[i];
        final file = asset.file;
        final selected = isSelected(file.id);
        final accent = colors.accent;
        return GestureDetector(
          onTap: () => onToggle(file),
          child: AnimatedContainer(
            duration: AppConstants.microInteraction,
            curve: AppConstants.easeOutKarlshare,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppConstants.radiusSmall + 2),
              border: Border.all(
                color: selected ? accent : Colors.transparent,
                width: 2,
              ),
            ),
            padding: const EdgeInsets.all(2),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppConstants.radiusSmall),
                  child: _Thumb(entity: asset.entity, fileType: file.type),
                ),
                Positioned(
                  left: 6,
                  bottom: 6,
                  child: _SizePill(text: FormatUtils.fileSize(file.sizeBytes)),
                ),
                if (file.type == KFileType.video)
                  const Positioned.fill(child: _VideoOverlay()),
                if (selected)
                  Positioned(top: 6, right: 6, child: _CheckBadge(accent: accent)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.entity, required this.fileType});

  final AssetEntity entity;
  final KFileType fileType;

  @override
  Widget build(BuildContext context) {
    final accent = FileUtils.color(fileType);
    return Container(
      color: accent.withValues(alpha: 0.08),
      child: Image(
        image: AssetEntityImageProvider(
          entity,
          isOriginal: false,
          thumbnailSize: const ThumbnailSize.square(280),
          thumbnailFormat: ThumbnailFormat.jpeg,
        ),
        fit: BoxFit.cover,
        errorBuilder: (context, _, _) => Center(
          child: Icon(FileUtils.icon(fileType), color: accent, size: 26),
        ),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Center(
            child: Icon(FileUtils.icon(fileType),
                color: accent.withValues(alpha: 0.4), size: 24),
          );
        },
      ),
    );
  }
}

class _VideoOverlay extends StatelessWidget {
  const _VideoOverlay();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.45),
          ],
        ),
      ),
      child: const Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: EdgeInsets.all(6),
          child: Icon(Icons.play_circle_fill_rounded,
              color: Colors.white, size: 18),
        ),
      ),
    );
  }
}

class _SizePill extends StatelessWidget {
  const _SizePill({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _CheckBadge extends StatelessWidget {
  const _CheckBadge({required this.accent});
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: accent,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.35),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Icon(Icons.check_rounded, color: Colors.white, size: 15),
    );
  }
}
