import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

/// Desktop networking helpers: find this PC's address on the local network and
/// make sure Windows Firewall lets a phone connect in.
class DesktopNet {
  /// The PC's IPv4 on the current network (the hotspot or shared Wi-Fi),
  /// preferring private ranges. This is what we put in the PC's QR so a phone
  /// can connect straight to it.
  static Future<String?> localIPv4() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    // Prefer a private/site-local address (the hotspot/LAN one).
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        if (_isPrivate(addr.address)) return addr.address;
      }
    }
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        if (!addr.isLoopback) return addr.address;
      }
    }
    return null;
  }

  static bool _isPrivate(String ip) {
    if (ip.startsWith('192.168.') || ip.startsWith('10.')) return true;
    if (ip.startsWith('172.')) {
      final parts = ip.split('.');
      final second = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
      return second >= 16 && second <= 31;
    }
    return false;
  }

  /// Best-effort: add a Windows Firewall inbound rule for the transfer port so
  /// a phone can reach this PC. Prompts UAC once; if declined, the OS's own
  /// "allow access" popup on first bind is the fallback. No-op off Windows.
  static Future<void> ensureFirewallRule(int port) async {
    if (!Platform.isWindows) return;
    final prefs = await SharedPreferences.getInstance();
    final key = 'fw_rule_$port';
    if (prefs.getBool(key) == true) return;
    try {
      final args =
          "advfirewall firewall add rule name=\"Karlshare\" dir=in action=allow protocol=TCP localport=$port";
      await Process.run('powershell', [
        '-NoProfile',
        '-WindowStyle',
        'Hidden',
        '-Command',
        "Start-Process netsh -Verb RunAs -WindowStyle Hidden -ArgumentList '$args'",
      ]);
      await prefs.setBool(key, true);
    } catch (_) {
      // Elevation declined or unavailable; the OS bind-time prompt covers it.
    }
  }
}
