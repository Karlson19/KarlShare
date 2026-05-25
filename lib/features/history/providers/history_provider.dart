import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../models/device.dart';
import '../../../models/enums.dart';
import '../../../models/transfer.dart';
import '../../../models/transfer_file.dart';
import '../../../providers/storage_provider.dart';

/// Persistent transfer history backed by a Hive box. Each [Transfer] is
/// JSON-encoded under its UUID — keeps things schema-flexible without
/// build_runner type adapters. (If we move to typed Hive later, the upgrade
/// is a one-shot migration in [_decode].)
class HistoryNotifier extends StateNotifier<List<Transfer>> {
  HistoryNotifier(this._box) : super(const []) {
    _load();
  }

  final Box<Map<dynamic, dynamic>> _box;

  void _load() {
    final transfers = _box.values
        .map(_decode)
        .whereType<Transfer>()
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    state = transfers;
  }

  Future<void> add(Transfer transfer) async {
    await _box.put(transfer.id, _encode(transfer));
    state = [transfer, ...state];
  }

  Future<void> remove(String id) async {
    await _box.delete(id);
    state = state.where((t) => t.id != id).toList();
  }

  Future<void> clear() async {
    await _box.clear();
    state = const [];
  }

  // ---- Serialization -----------------------------------------------------

  Map<String, dynamic> _encode(Transfer t) => {
        'id': t.id,
        'device': {
          'id': t.device.id,
          'name': t.device.name,
          'status': t.device.status.name,
          'signalStrength': t.device.signalStrength,
          'angle': t.device.angle,
          'distance': t.device.distance,
          'address': t.device.address,
          'ipAddress': t.device.ipAddress,
        },
        'direction': t.direction.name,
        'timestamp': t.timestamp.toIso8601String(),
        'status': t.status.name,
        'files': t.files
            .map((f) => {
                  'id': f.id,
                  'name': f.name,
                  'sizeBytes': f.sizeBytes,
                  'type': f.type.name,
                  'progress': f.progress,
                  'path': f.path,
                })
            .toList(),
      };

  Transfer? _decode(Map<dynamic, dynamic> raw) {
    try {
      final deviceMap = raw['device'] as Map<dynamic, dynamic>;
      final filesRaw = (raw['files'] as List?) ?? const [];
      return Transfer(
        id: raw['id'] as String,
        device: Device(
          id: deviceMap['id'] as String,
          name: deviceMap['name'] as String,
          status: _enumByName(DeviceStatus.values, deviceMap['status'] as String?) ??
              DeviceStatus.ready,
          signalStrength: (deviceMap['signalStrength'] as num?)?.toDouble() ?? 1.0,
          angle: (deviceMap['angle'] as num?)?.toDouble() ?? 0.0,
          distance: (deviceMap['distance'] as num?)?.toDouble() ?? 0.5,
          address: deviceMap['address'] as String?,
          ipAddress: deviceMap['ipAddress'] as String?,
        ),
        direction:
            _enumByName(TransferDirection.values, raw['direction'] as String?) ??
                TransferDirection.sent,
        timestamp: DateTime.parse(raw['timestamp'] as String),
        status: _enumByName(TransferStatus.values, raw['status'] as String?) ??
            TransferStatus.completed,
        files: filesRaw.cast<Map<dynamic, dynamic>>().map((f) {
          return TransferFile(
            id: f['id'] as String,
            name: f['name'] as String,
            sizeBytes: (f['sizeBytes'] as num).toInt(),
            type: _enumByName(KFileType.values, f['type'] as String?) ??
                KFileType.other,
            progress: (f['progress'] as num?)?.toDouble() ?? 0.0,
            path: f['path'] as String?,
          );
        }).toList(),
      );
    } catch (_) {
      return null;
    }
  }

  static T? _enumByName<T extends Enum>(List<T> values, String? name) {
    if (name == null) return null;
    for (final v in values) {
      if (v.name == name) return v;
    }
    return null;
  }
}

final historyProvider =
    StateNotifierProvider<HistoryNotifier, List<Transfer>>((ref) {
  return HistoryNotifier(ref.watch(transfersBoxProvider));
});

/// History filtered by direction, for the Sent / Received tabs.
final historyByDirectionProvider =
    Provider.family<List<Transfer>, TransferDirection>((ref, direction) {
  return ref
      .watch(historyProvider)
      .where((t) => t.direction == direction)
      .toList();
});
