import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../models/enums.dart';
import '../../../models/transfer_file.dart';

/// Status of the photo / video / audio permission check.
enum MediaPermissionState { unknown, authorized, limited, denied, unsupported }

/// One real on-device asset (photo/video/audio) backed by a [photo_manager]
/// [AssetEntity]. The [TransferFile] view is used everywhere else in the app,
/// while [entity] is kept around so the grid can render thumbnails.
@immutable
class MediaAsset {
  const MediaAsset({required this.file, required this.entity});

  final TransferFile file;
  final AssetEntity entity;
}

/// Maps a [photo_manager] asset to Karlshare's [TransferFile] domain model.
Future<MediaAsset?> _toMediaAsset(AssetEntity entity) async {
  final file = await entity.file;
  if (file == null) return null;
  final size = await file.length();
  return MediaAsset(
    file: TransferFile(
      id: entity.id,
      name: entity.title ?? '${entity.id}.${_extFor(entity.type)}',
      sizeBytes: size,
      type: _kFileTypeFor(entity.type),
      path: file.path,
    ),
    entity: entity,
  );
}

KFileType _kFileTypeFor(AssetType type) => switch (type) {
      AssetType.image => KFileType.image,
      AssetType.video => KFileType.video,
      AssetType.audio => KFileType.audio,
      _ => KFileType.other,
    };

String _extFor(AssetType type) => switch (type) {
      AssetType.image => 'jpg',
      AssetType.video => 'mp4',
      AssetType.audio => 'm4a',
      _ => 'bin',
    };

RequestType _photoManagerType(KFileType type) => switch (type) {
      KFileType.image => RequestType.image,
      KFileType.video => RequestType.video,
      KFileType.audio => RequestType.audio,
      _ => RequestType.common,
    };

/// Permission state for gallery access. Updates after [requestMediaPermission].
final mediaPermissionProvider =
    StateProvider<MediaPermissionState>((ref) => MediaPermissionState.unknown);

/// Triggers the photo_manager permission flow, then writes the result to
/// [mediaPermissionProvider]. Safe to call multiple times.
Future<MediaPermissionState> requestMediaPermission(WidgetRef ref) async {
  // photo_manager doesn't run on every platform — guard so desktop tests
  // don't explode trying to call into a missing channel.
  try {
    final result = await PhotoManager.requestPermissionExtend();
    final state = switch (result) {
      PermissionState.authorized => MediaPermissionState.authorized,
      PermissionState.limited => MediaPermissionState.limited,
      PermissionState.denied => MediaPermissionState.denied,
      PermissionState.notDetermined => MediaPermissionState.unknown,
      PermissionState.restricted => MediaPermissionState.denied,
    };
    ref.read(mediaPermissionProvider.notifier).state = state;
    return state;
  } catch (_) {
    ref.read(mediaPermissionProvider.notifier).state =
        MediaPermissionState.unsupported;
    return MediaPermissionState.unsupported;
  }
}

/// Loads up to [limit] of the most recent assets of [type] from the device.
final mediaAssetsProvider = FutureProvider.autoDispose
    .family<List<MediaAsset>, KFileType>((ref, type) async {
  final permission = ref.watch(mediaPermissionProvider);
  if (permission != MediaPermissionState.authorized &&
      permission != MediaPermissionState.limited) {
    return const <MediaAsset>[];
  }
  try {
    final albums = await PhotoManager.getAssetPathList(
      type: _photoManagerType(type),
      onlyAll: true,
      filterOption: FilterOptionGroup(
        orders: const [OrderOption(type: OrderOptionType.createDate, asc: false)],
      ),
    );
    if (albums.isEmpty) return const <MediaAsset>[];
    final entities = await albums.first.getAssetListPaged(page: 0, size: 120);
    final results = await Future.wait(entities.map(_toMediaAsset));
    return results.whereType<MediaAsset>().toList(growable: false);
  } catch (_) {
    return const <MediaAsset>[];
  }
});
