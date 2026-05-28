import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/connect_code.dart';
import '../../../services/desktop/desktop_identity.dart';
import '../../../services/desktop/desktop_net.dart';

bool get _isDesktop =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

/// The PC's own connection code (IP + port + name + cert fingerprint), built so
/// the desktop home screen can render it as a QR for a phone to scan. Returns
/// null on mobile (phones present their code from the receive flow instead).
///
/// Building the code also ensures the Windows Firewall inbound rule exists, so
/// a phone can actually reach this PC's transfer port.
final desktopConnectCodeProvider = FutureProvider<ConnectCode?>((ref) async {
  if (!_isDesktop) return null;
  const port = ConnectCode.defaultPort;
  await DesktopNet.ensureFirewallRule(port);
  final ip = await DesktopNet.localIPv4();
  final id = await DesktopIdentity.load();
  return ConnectCode(
    hostIp: ip,
    port: port,
    name: Platform.localHostname,
    fingerprint: _hex(id.fingerprint),
  );
});

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
