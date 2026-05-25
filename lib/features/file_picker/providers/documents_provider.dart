import 'dart:io';

import 'package:file_picker/file_picker.dart' as picker;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/file_utils.dart';
import '../../../models/transfer_file.dart';

/// Documents that the user explicitly browsed for via the system file picker
/// (the in-app tab UX for "Files" — different from Photos / Videos which
/// enumerate the gallery). Survives navigation within the picker so they
/// re-appear when the user switches tabs and back.
class DocumentBrowserNotifier extends StateNotifier<List<TransferFile>> {
  DocumentBrowserNotifier() : super(const []);

  /// Opens the system file picker. Returns the new picks (also appended to
  /// state) so the caller can immediately add them to the transfer selection.
  Future<List<TransferFile>> pickFiles() async {
    final result = await picker.FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: picker.FileType.any,
      withData: false,
    );
    if (result == null) return const [];
    final picked = <TransferFile>[];
    for (final f in result.files) {
      final path = f.path;
      if (path == null) continue;
      final stat = await File(path).stat();
      picked.add(TransferFile(
        id: path,
        name: f.name,
        sizeBytes: stat.size,
        type: FileUtils.typeFromExtension(f.name),
        path: path,
      ));
    }
    if (picked.isNotEmpty) {
      // De-dupe by path so re-picking the same file doesn't double-add.
      final seen = state.map((e) => e.id).toSet();
      final fresh = picked.where((p) => !seen.contains(p.id));
      state = [...state, ...fresh];
    }
    return picked;
  }

  void clear() => state = const [];
}

final documentBrowserProvider = StateNotifierProvider.autoDispose<
    DocumentBrowserNotifier, List<TransferFile>>((ref) {
  return DocumentBrowserNotifier();
});
