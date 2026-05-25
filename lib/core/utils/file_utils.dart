import 'package:flutter/material.dart';
import '../../models/enums.dart';
import '../theme/app_colors.dart';

/// Maps file types to icons, accent colors and extensions.
class FileUtils {
  FileUtils._();

  static KFileType typeFromExtension(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    const images = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'bmp'};
    const videos = {'mp4', 'mov', 'mkv', 'avi', 'webm', '3gp'};
    const audio = {'mp3', 'wav', 'aac', 'flac', 'm4a', 'ogg'};
    const docs = {'pdf', 'doc', 'docx', 'txt', 'ppt', 'pptx', 'xls', 'xlsx'};
    if (images.contains(ext)) return KFileType.image;
    if (videos.contains(ext)) return KFileType.video;
    if (audio.contains(ext)) return KFileType.audio;
    if (docs.contains(ext)) return KFileType.document;
    if (ext == 'apk') return KFileType.app;
    return KFileType.other;
  }

  static IconData icon(KFileType type) => switch (type) {
        KFileType.image => Icons.image_rounded,
        KFileType.video => Icons.videocam_rounded,
        KFileType.audio => Icons.music_note_rounded,
        KFileType.document => Icons.description_rounded,
        KFileType.app => Icons.android_rounded,
        KFileType.other => Icons.insert_drive_file_rounded,
      };

  static Color color(KFileType type) => switch (type) {
        KFileType.image => AppColors.karlshareOrange,
        KFileType.video => AppColors.royalMagenta,
        KFileType.audio => AppColors.electricPurple,
        KFileType.document => AppColors.info,
        KFileType.app => AppColors.success,
        KFileType.other => AppColors.ashantiGold,
      };

  static String label(KFileType type) => switch (type) {
        KFileType.image => 'Photos',
        KFileType.video => 'Videos',
        KFileType.audio => 'Music',
        KFileType.document => 'Files',
        KFileType.app => 'Apps',
        KFileType.other => 'Other',
      };
}
