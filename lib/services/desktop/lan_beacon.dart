import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../discovery_service.dart';

/// LAN auto-discovery over UDP broadcast. Every Karlshare device on the same
/// WiFi network periodically announces itself { id, name, platform, port }, and
/// listens for others. Peers appear and disappear on the radar with zero setup,
/// no cables and no typed addresses. Used by the desktop build today; the same
/// wire format will let phones join once Android grows a matching beacon.
class LanBeacon {
  static const int beaconPort = 8987; // discovery; transfers use 8988
  static const int transferPort = 8988;
  static const Duration _announceEvery = Duration(seconds: 2);
  static const Duration _peerTimeout = Duration(seconds: 6);

  final _controller = StreamController<DiscoveryEvent>.broadcast();
  final Map<String, _SeenPeer> _peers = {}; // peerId -> last sighting

  RawDatagramSocket? _socket;
  Timer? _announceTimer;
  Timer? _reapTimer;

  String _localId = '';
  String _localName = 'This device';
  String _localPlatform = Platform.operatingSystem;

  Stream<DiscoveryEvent> get events => _controller.stream;

  Future<void> start() async {
    if (_socket != null) return;

    final prefs = await SharedPreferences.getInstance();
    _localId = prefs.getString('lan_device_id') ??
        (() {
          final id = const Uuid().v4();
          prefs.setString('lan_device_id', id);
          return id;
        })();
    _localName = Platform.localHostname;
    _localPlatform = Platform.operatingSystem;

    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        beaconPort,
        reuseAddress: true,
      );
      socket.broadcastEnabled = true;
      _socket = socket;
      socket.listen(_onEvent);
    } catch (e) {
      _controller.add(
        const DiscoveryEvent.error(errorStage: 'lanBind', errorReason: -1),
      );
      return;
    }

    _announce();
    _announceTimer = Timer.periodic(_announceEvery, (_) => _announce());
    _reapTimer = Timer.periodic(_announceEvery, (_) => _reap());
  }

  /// Desktop "connect": we already know the peer's IP from its beacon, so we
  /// surface it as a group-ready event to mirror the mobile flow.
  void connect(String address) {
    _controller.add(
      DiscoveryEvent.groupReady(ownerIp: address, isGroupOwner: false),
    );
  }

  Future<void> stop() async {
    _announceTimer?.cancel();
    _reapTimer?.cancel();
    _announceTimer = null;
    _reapTimer = null;
    _socket?.close();
    _socket = null;
    _peers.clear();
  }

  void dispose() {
    stop();
    _controller.close();
  }

  // ---- internals ----------------------------------------------------------

  void _announce() {
    final socket = _socket;
    if (socket == null) return;
    final payload = utf8.encode(jsonEncode({
      'v': 1,
      'id': _localId,
      'name': _localName,
      'platform': _localPlatform,
      'port': transferPort,
    }));
    try {
      socket.send(payload, InternetAddress('255.255.255.255'), beaconPort);
    } catch (_) {
      // Some networks block limited broadcast; peer-found still works for
      // anyone whose beacon reaches us.
    }
  }

  void _onEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final datagram = _socket?.receive();
    if (datagram == null) return;
    try {
      final map = jsonDecode(utf8.decode(datagram.data)) as Map<String, dynamic>;
      final id = map['id'] as String?;
      if (id == null || id == _localId) return; // ignore our own beacon

      final peer = DiscoveredPeer(
        address: datagram.address.address, // the sender's IP
        name: (map['name'] as String?) ?? 'Device',
        signalStrength: 100,
        isAvailable: true,
        platform: (map['platform'] as String?) ?? 'unknown',
      );
      final isNew = !_peers.containsKey(id);
      _peers[id] = _SeenPeer(peer, DateTime.now());
      if (isNew) _controller.add(DiscoveryEvent.peerFound(peer));
    } catch (_) {
      // Not a Karlshare beacon; ignore.
    }
  }

  void _reap() {
    final now = DateTime.now();
    final gone = _peers.entries
        .where((e) => now.difference(e.value.seenAt) > _peerTimeout)
        .toList();
    for (final entry in gone) {
      _peers.remove(entry.key);
      _controller.add(DiscoveryEvent.peerLost(entry.value.peer.address));
    }
  }
}

class _SeenPeer {
  _SeenPeer(this.peer, this.seenAt);
  final DiscoveredPeer peer;
  final DateTime seenAt;
}
