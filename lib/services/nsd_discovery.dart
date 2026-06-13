import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:nsd/nsd.dart' as nsd;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'discovery_service.dart';

/// Standard mDNS / DNS-SD discovery (the tech behind AirDrop, Chromecast,
/// network printers). Each device advertises a `_karlshare._tcp` service and
/// browses for others, so peers appear on the radar with zero setup — the same
/// idea as the hand-rolled UDP beacon, but using the OS's battle-tested
/// responder (Android NSD, Windows' native mDNS). Runs ALONGSIDE the beacon:
/// whichever sees a peer first surfaces it; the provider de-dups by IP.
///
/// The dial address is carried in the service's TXT record (`ip`), so we never
/// depend on resolving a `.local` hostname — the transfer engine dials a raw IP.
class NsdDiscovery {
  static const String serviceType = '_karlshare._tcp';
  static const int _transferPort = 8988;

  final _controller = StreamController<DiscoveryEvent>.broadcast();

  nsd.Registration? _registration;
  nsd.Discovery? _discovery;
  String _localId = '';
  // service-instance key -> the peer IP we surfaced, so a 'lost' (whose TXT may
  // be empty) still maps back to the address the radar knows.
  final Map<String, String> _addrByKey = {};

  /// The friendly name to advertise (profile name, else hostname). Set before
  /// [start].
  String advertisedName = '';

  Stream<DiscoveryEvent> get events => _controller.stream;

  Future<void> start() async {
    if (_discovery != null) return;

    final prefs = await SharedPreferences.getInstance();
    _localId = prefs.getString('lan_device_id') ??
        (() {
          final id = const Uuid().v4();
          prefs.setString('lan_device_id', id);
          return id;
        })();

    final name = advertisedName.trim().isNotEmpty ? advertisedName.trim() : _hostname();
    final ip = await _localIpv4();

    // Advertise ourselves (best-effort — discovery still works if this fails).
    try {
      _registration = await nsd.register(nsd.Service(
        name: name,
        type: serviceType,
        port: _transferPort,
        txt: {
          'id': _bytes(_localId),
          'name': _bytes(name),
          'platform': _bytes(Platform.operatingSystem),
          if (ip != null) 'ip': _bytes(ip),
        },
      ));
    } catch (_) {
      // ignore — we can still browse for others
    }

    try {
      _discovery = await nsd.startDiscovery(
        serviceType,
        ipLookupType: nsd.IpLookupType.v4,
      );
      _discovery!.addServiceListener(_onService);
    } catch (_) {
      _controller.add(
        const DiscoveryEvent.error(errorStage: 'mdns', errorReason: -1),
      );
    }
  }

  void _onService(nsd.Service service, nsd.ServiceStatus status) {
    final txt = service.txt;
    final id = _txt(txt, 'id');
    if (id != null && id == _localId) return; // never list ourselves

    final key = service.name ?? id ?? service.host ?? '';

    if (status == nsd.ServiceStatus.lost) {
      final addr = _addrByKey.remove(key);
      if (addr != null) _controller.add(DiscoveryEvent.peerLost(addr));
      return;
    }

    // found: prefer the resolved IPv4, fall back to the TXT ip.
    final ip = _firstV4(service.addresses) ?? _txt(txt, 'ip');
    if (ip == null || ip.isEmpty) return; // nothing dialable yet
    _addrByKey[key] = ip;
    _controller.add(DiscoveryEvent.peerFound(DiscoveredPeer(
      address: ip,
      name: _txt(txt, 'name') ?? service.name ?? 'Device',
      signalStrength: 100,
      isAvailable: true,
      platform: _txt(txt, 'platform') ?? 'unknown',
    )));
  }

  Future<void> stop() async {
    final d = _discovery;
    final r = _registration;
    _discovery = null;
    _registration = null;
    _addrByKey.clear();
    if (d != null) {
      try {
        await nsd.stopDiscovery(d);
      } catch (_) {}
    }
    if (r != null) {
      try {
        await nsd.unregister(r);
      } catch (_) {}
    }
  }

  void dispose() {
    unawaited(stop());
    _controller.close();
  }

  // ---- helpers -------------------------------------------------------------

  static Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

  static String? _txt(Map<String, Uint8List?>? txt, String key) {
    final v = txt?[key];
    if (v == null || v.isEmpty) return null;
    try {
      return utf8.decode(v);
    } catch (_) {
      return null;
    }
  }

  static String? _firstV4(List<InternetAddress>? addrs) {
    if (addrs == null) return null;
    for (final a in addrs) {
      if (a.type == InternetAddressType.IPv4 && !a.isLoopback) return a.address;
    }
    return null;
  }

  static String _hostname() {
    try {
      return Platform.localHostname;
    } catch (_) {
      return 'Karlshare device';
    }
  }

  Future<String?> _localIpv4() async {
    try {
      final ifaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final i in ifaces) {
        for (final a in i.addresses) {
          final ip = a.address;
          if (ip.startsWith('192.168.') ||
              ip.startsWith('10.') ||
              ip.startsWith('172.')) {
            return ip;
          }
        }
      }
      for (final i in ifaces) {
        for (final a in i.addresses) {
          if (!a.isLoopback) return a.address;
        }
      }
    } catch (_) {}
    return null;
  }
}
