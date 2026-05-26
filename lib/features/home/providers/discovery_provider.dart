import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/device.dart';
import '../../../models/enums.dart';
import '../../../services/discovery_service.dart';

/// Shared [DiscoveryService] instance. Overridden in tests with a fake.
final discoveryServiceProvider = Provider<DiscoveryService>((ref) {
  final service = DiscoveryService();
  ref.onDispose(() => service.stop());
  return service;
});

/// Raw native event stream — single subscription. Both
/// [discoveredDevicesProvider] and [groupReadyProvider] derive from this.
final _discoveryEventsProvider =
    StreamProvider.autoDispose<DiscoveryEvent>((ref) {
  final service = ref.watch(discoveryServiceProvider);
  if (!service.isPlatformSupported) return const Stream<DiscoveryEvent>.empty();
  return service.events();
});

/// Whether the radar is actively scanning.
final isScanningProvider = StateProvider<bool>((ref) => true);

/// Streams discovered devices from the native WiFi Direct bridge. Returns an
/// empty list on platforms without the native bridge (iOS lands in Phase 4,
/// desktop/web aren't targets). The radar's empty state handles that case.
final discoveredDevicesProvider =
    StreamProvider.autoDispose<List<Device>>((ref) async* {
  final scanning = ref.watch(isScanningProvider);
  if (!scanning) {
    yield <Device>[];
    return;
  }

  final service = ref.watch(discoveryServiceProvider);
  if (!service.isPlatformSupported) {
    yield const <Device>[];
    return;
  }

  await service.start();
  ref.onDispose(() => service.stop());
  yield* _nativeDeviceStream(ref);
});

/// Most recent group-formation result. Populated when the receiver has
/// created a group / sender has joined one. Holds the owner's IP so the
/// transfer engine knows where to dial.
final groupReadyProvider = StateProvider<GroupReadyInfo?>((ref) {
  ref.listen<AsyncValue<DiscoveryEvent>>(_discoveryEventsProvider, (_, next) {
    next.whenData((event) {
      if (event.type == DiscoveryEventType.groupReady &&
          event.ownerIp != null) {
        ref.controller.state = GroupReadyInfo(
          ownerIp: event.ownerIp!,
          isGroupOwner: event.isGroupOwner,
        );
      }
    });
  });
  return null;
});

class GroupReadyInfo {
  const GroupReadyInfo({required this.ownerIp, required this.isGroupOwner});
  final String ownerIp;
  final bool isGroupOwner;
}

// ---- Internal stream ------------------------------------------------------

Stream<List<Device>> _nativeDeviceStream(Ref ref) async* {
  final byAddress = <String, Device>{};
  yield const <Device>[];

  final controller = StreamController<List<Device>>();
  final sub = ref.read(discoveryServiceProvider).events().listen((event) {
    switch (event.type) {
      case DiscoveryEventType.peerFound:
        final peer = event.peer!;
        // Stable-but-pseudo-random radar position derived from address so
        // the same device sits in the same place across re-renders.
        final r = math.Random(peer.address.hashCode);
        byAddress[peer.address] = Device(
          id: peer.address,
          name: peer.name,
          status: peer.isAvailable ? DeviceStatus.ready : DeviceStatus.busy,
          signalStrength: peer.signalStrength / 100.0,
          angle: r.nextDouble() * 2 * math.pi,
          distance: 0.45 + r.nextDouble() * 0.5,
          address: peer.address,
          // On the LAN path the address IS the peer's IP, so the transfer
          // engine can dial it immediately with no group-owner negotiation.
          ipAddress: peer.address,
        );
        controller.add(List<Device>.unmodifiable(byAddress.values));
        break;
      case DiscoveryEventType.peerLost:
        final addr = event.lostAddress;
        if (addr != null && byAddress.remove(addr) != null) {
          controller.add(List<Device>.unmodifiable(byAddress.values));
        }
        break;
      case DiscoveryEventType.groupReady:
      case DiscoveryEventType.error:
        // Routed elsewhere (groupReadyProvider / error overlay).
        break;
    }
  });
  ref.onDispose(() {
    sub.cancel();
    controller.close();
  });
  yield* controller.stream;
}
