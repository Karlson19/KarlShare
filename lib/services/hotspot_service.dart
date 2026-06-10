import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Events from the native hotspot bridge.
enum HotspotEventType { status, hotspotReady, joined, hotspotError, joinError }

@immutable
class HotspotEvent {
  const HotspotEvent({
    required this.type,
    this.ssid,
    this.password,
    this.gatewayIp,
    this.hostIp,
    this.message,
    this.reason,
  });

  final HotspotEventType type;
  final String? ssid;
  final String? password;
  final String? gatewayIp;

  /// The host's own IP on the hotspot (put in the QR so the sender connects
  /// straight to it, no gateway guessing).
  final String? hostIp;
  final String? message;

  /// Machine-readable error cause (e.g. 'location' when Location services are
  /// off) so the UI can offer the right fix button, not just a message.
  final String? reason;
}

/// Wraps the `karlshare/hotspot` channel: the receiver creates a Wi-Fi hotspot,
/// the sender joins it. Lets two phones share with no router and no internet.
class HotspotService {
  HotspotService({MethodChannel? method, EventChannel? events})
      : _method = method ?? const MethodChannel('karlshare/hotspot'),
        _events = events ?? const EventChannel('karlshare/hotspot/events');

  final MethodChannel _method;
  final EventChannel _events;
  Stream<HotspotEvent>? _cached;

  bool get isPlatformSupported => !kIsWeb && Platform.isAndroid;

  Future<bool> isSupported() async {
    if (!isPlatformSupported) return false;
    return (await _method.invokeMethod<bool>('isSupported')) ?? false;
  }

  Future<void> startHotspot() async {
    if (!isPlatformSupported) return;
    await _method.invokeMethod<void>('startHotspot');
  }

  Future<void> stopHotspot() async {
    if (!isPlatformSupported) return;
    await _method.invokeMethod<void>('stopHotspot');
  }

  Future<void> joinHotspot({required String ssid, required String password}) async {
    if (!isPlatformSupported) return;
    await _method.invokeMethod<void>('joinHotspot', {
      'ssid': ssid,
      'password': password,
    });
  }

  Future<void> leaveHotspot() async {
    if (!isPlatformSupported) return;
    await _method.invokeMethod<void>('leaveHotspot');
  }

  /// Whether Android's Location services toggle is on — LocalOnlyHotspot
  /// refuses to start without it.
  Future<bool> isLocationEnabled() async {
    if (!isPlatformSupported) return true;
    return (await _method.invokeMethod<bool>('isLocationEnabled')) ?? true;
  }

  /// Jumps straight to the system Location settings page.
  Future<void> openLocationSettings() async {
    if (!isPlatformSupported) return;
    await _method.invokeMethod<void>('openLocationSettings');
  }

  Stream<HotspotEvent> events() {
    if (!isPlatformSupported) return const Stream.empty();
    return _cached ??= _events
        .receiveBroadcastStream()
        .map(_parse)
        .where((e) => e != null)
        .cast<HotspotEvent>()
        .asBroadcastStream();
  }

  HotspotEvent? _parse(dynamic raw) {
    if (raw is! Map) return null;
    final type = switch (raw['type'] as String?) {
      'status' => HotspotEventType.status,
      'hotspotReady' => HotspotEventType.hotspotReady,
      'joined' => HotspotEventType.joined,
      'hotspotError' => HotspotEventType.hotspotError,
      'joinError' => HotspotEventType.joinError,
      _ => null,
    };
    if (type == null) return null;
    return HotspotEvent(
      type: type,
      ssid: raw['ssid'] as String?,
      password: raw['password'] as String?,
      gatewayIp: raw['gatewayIp'] as String?,
      hostIp: raw['hostIp'] as String?,
      message: raw['message'] as String?,
      reason: raw['reason'] as String?,
    );
  }
}

final hotspotServiceProvider = Provider<HotspotService>((ref) => HotspotService());
