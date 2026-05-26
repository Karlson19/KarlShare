import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'desktop/lan_beacon.dart';

/// Native discovery event types emitted on `karlshare/discovery/events`.
enum DiscoveryEventType { peerFound, peerLost, groupReady, error }

@immutable
class DiscoveredPeer {
  const DiscoveredPeer({
    required this.address,
    required this.name,
    required this.signalStrength,
    required this.isAvailable,
    this.platform = 'unknown',
  });

  /// Routing key for the peer. On WiFi Direct this is the MAC; on the LAN
  /// beacon path it is the peer's IP address.
  final String address;

  /// Human-facing name advertised by the peer.
  final String name;

  /// 0–100; rough proximity heuristic.
  final int signalStrength;

  final bool isAvailable;

  /// Operating system advertised by the peer: 'android', 'ios', 'windows',
  /// 'linux', 'macos', or 'unknown'. Drives the OS badge on the radar.
  final String platform;

  DiscoveredPeer copyWith({
    String? name,
    int? signalStrength,
    bool? isAvailable,
    String? platform,
  }) =>
      DiscoveredPeer(
        address: address,
        name: name ?? this.name,
        signalStrength: signalStrength ?? this.signalStrength,
        isAvailable: isAvailable ?? this.isAvailable,
        platform: platform ?? this.platform,
      );

  @override
  bool operator ==(Object other) =>
      other is DiscoveredPeer &&
      other.address == address &&
      other.name == name &&
      other.signalStrength == signalStrength &&
      other.isAvailable == isAvailable &&
      other.platform == platform;

  @override
  int get hashCode =>
      Object.hash(address, name, signalStrength, isAvailable, platform);
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
  LanBeacon? _beacon;

  /// Mobile uses the native WiFi Direct / Multipeer bridge.
  bool get _channelSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Desktop uses the pure-Dart LAN beacon (Windows / Linux / macOS).
  bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  LanBeacon _ensureBeacon() => _beacon ??= LanBeacon();

  /// True when discovery works on this platform at all.
  bool get isPlatformSupported => _channelSupported || _isDesktop;

  Future<bool> isSupported() async {
    if (_isDesktop) return true;
    if (!_channelSupported) return false;
    return (await _method.invokeMethod<bool>('isSupported')) ?? false;
  }

  Future<void> start() async {
    if (_isDesktop) {
      await _ensureBeacon().start();
      return;
    }
    if (!_channelSupported) return;
    await _method.invokeMethod<void>('start');
  }

  Future<void> stop() async {
    if (_isDesktop) {
      await _beacon?.stop();
      return;
    }
    if (!_channelSupported) return;
    await _method.invokeMethod<void>('stop');
  }

  Future<void> createGroup() async {
    if (_isDesktop) return; // no group-owner concept on the LAN path
    if (!_channelSupported) return;
    await _method.invokeMethod<void>('createGroup');
  }

  Future<void> connect(String deviceAddress) async {
    if (_isDesktop) {
      _ensureBeacon().connect(deviceAddress);
      return;
    }
    if (!_channelSupported) return;
    await _method.invokeMethod<void>('connect', {'deviceAddress': deviceAddress});
  }

  Future<void> disconnect() async {
    if (_isDesktop) return;
    if (!_channelSupported) return;
    await _method.invokeMethod<void>('disconnect');
  }

  /// Hot stream of discovery events. On desktop this is the LAN beacon; on
  /// mobile it is the native EventChannel (cached so subscribers fan out).
  Stream<DiscoveryEvent> events() {
    if (_isDesktop) return _ensureBeacon().events;
    if (!_channelSupported) return const Stream.empty();
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
          platform: raw['platform'] as String? ?? 'android',
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
