import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/transfer_file.dart';

/// Tracks files selected across the picker tabs, keyed by id.
class FileSelectionNotifier extends StateNotifier<Map<String, TransferFile>> {
  FileSelectionNotifier() : super(const {});

  void toggle(TransferFile file) {
    final next = Map<String, TransferFile>.from(state);
    if (next.containsKey(file.id)) {
      next.remove(file.id);
    } else {
      next[file.id] = file;
    }
    state = next;
  }

  bool isSelected(String id) => state.containsKey(id);

  void clear() => state = const {};

  int get totalBytes =>
      state.values.fold(0, (sum, f) => sum + f.sizeBytes);

  List<TransferFile> get files => state.values.toList();
}

final fileSelectionProvider = StateNotifierProvider.autoDispose<
    FileSelectionNotifier, Map<String, TransferFile>>((ref) {
  return FileSelectionNotifier();
});
