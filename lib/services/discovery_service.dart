import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Native discovery event types emitted on `karlshare/discovery/events`.
enum DiscoveryEventType { peerFound, peerLost, groupReady, error }

@immutable
class DiscoveredPeer {
  const DiscoveredPeer({
    required this.address,
    required this.name,
    required this.signalStrength,
    required this.isAvailable,
  });

  /// MAC address of the peer (used as `deviceAddress` for connect calls).
  final String address;

  /// Human-facing name advertised by the peer.
  final String name;

  /// 0–100; rough proximity heuristic from WifiP2pDevice status.
  final int signalStrength;

  final bool isAvailable;

  DiscoveredPeer copyWith({
    String? name,
    int? signalStrength,
    bool? isAvailable,
  }) =>
      DiscoveredPeer(
        address: address,
        name: name ?? this.name,
        signalStrength: signalStrength ?? this.signalStrength,
        isAvailable: isAvailable ?? this.isAvailable,
      );

  @override
  bool operator ==(Object other) =>
      other is DiscoveredPeer &&
      other.address == address &&
      other.name == name &&
      other.signalStrength == signalStrength &&
      other.isAvailable == isAvailable;

  @override
  int get hashCode => Object.hash(address, name, signalStrength, isAvailable);
}

@immutable
class DiscoveryEvent {
  const DiscoveryEvent.peerFound(this.peer)
      : type = DiscoveryEventType.peerFound,
        lostAddress = null,
        ownerIp = null,
        isGroupOwner = false,
        errorStage = null,
        errorReason = null;

  const DiscoveryEvent.peerLost(this.lostAddress)
      : type = DiscoveryEventType.peerLost,
        peer = null,
        ownerIp = null,
        isGroupOwner = false,
        errorStage = null,
        errorReason = null;

  const DiscoveryEvent.groupReady({
    required this.ownerIp,
    required this.isGroupOwner,
  })  : type = DiscoveryEventType.groupReady,
        peer = null,
        lostAddress = null,
        errorStage = null,
        errorReason = null;

  const DiscoveryEvent.error({required this.errorStage, required this.errorReason})
      : type = DiscoveryEventType.error,
        peer = null,
        lostAddress = null,
        ownerIp = null,
        isGroupOwner = false;

  final DiscoveryEventType type;
  final DiscoveredPeer? peer;
  final String? lostAddress;
  final String? ownerIp;
  final bool isGroupOwner;
  final String? errorStage;
  final int? errorReason;
}

/// Typed wrapper around the `karlshare/discovery` platform channels.
/// Android-only for now; other platforms report `isSupported == false`.
class DiscoveryService {
  DiscoveryService({
    MethodChannel? method,
    EventChannel? events,
  })  : _method = method ?? const MethodChannel('karlshare/discovery'),
        _events = events ?? const EventChannel('karlshare/discovery/events');

  final MethodChannel _method;
  final EventChannel _events;
  Stream<DiscoveryEvent>? _cached;

  /// True when the running platform implements the native bridge.
  bool get isPlatformSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<bool> isSupported() async {
    if (!isPlatformSupported) return false;
    return (await _method.invokeMethod<bool>('isSupported')) ?? false;
  }

  Future<void> start() async {
    if (!isPlatformSupported) return;
    await _method.invokeMethod<void>('start');
  }

  Future<void> stop() async {
    if (!isPlatformSupported) return;
    await _method.invokeMethod<void>('stop');
  }

  Future<void> createGroup() async {
    if (!isPlatformSupported) return;
    await _method.invokeMethod<void>('createGroup');
  }

  Future<void> connect(String deviceAddress) async {
    if (!isPlatformSupported) return;
    await _method.invokeMethod<void>('connect', {'deviceAddress': deviceAddress});
  }

  Future<void> disconnect() async {
    if (!isPlatformSupported) return;
    await _method.invokeMethod<void>('disconnect');
  }

  /// Hot stream of native events. Cached so multiple subscribers share one
  /// platform-side EventChannel — the channel itself broadcasts via the
  /// native sink, but Dart still needs a broadcast wrapper for fan-out.
  Stream<DiscoveryEvent> events() {
    if (!isPlatformSupported) return const Stream.empty();
    return _cached ??= _events
        .receiveBroadcastStream()
        .map(_parse)
        .where((e) => e != null)
        .cast<DiscoveryEvent>()
        .asBroadcastStream();
  }

  DiscoveryEvent? _parse(dynamic raw) {
    if (raw is! Map) return null;
    final type = raw['type'] as String?;
    switch (type) {
      case 'peerFound':
        return DiscoveryEvent.peerFound(DiscoveredPeer(
          address: raw['address'] as String? ?? '',
          name: raw['name'] as String? ?? 'Unknown',
          signalStrength: (raw['signalStrength'] as num?)?.toInt() ?? 50,
          isAvailable: raw['isAvailable'] as bool? ?? true,
        ));
      case 'peerLost':
        return DiscoveryEvent.peerLost(raw['address'] as String? ?? '');
      case 'groupReady':
        return DiscoveryEvent.groupReady(
          ownerIp: raw['ownerIp'] as String? ?? '',
          isGroupOwner: raw['isGroupOwner'] as bool? ?? false,
        );
      case 'error':
        return DiscoveryEvent.error(
          errorStage: raw['stage'] as String? ?? 'unknown',
          errorReason: (raw['reason'] as num?)?.toInt() ?? -1,
        );
      default:
        return null;
    }
  }
}
