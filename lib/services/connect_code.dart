import 'dart:convert';

/// The Karlshare connection QR payload — the single source of truth for what a
/// connect code contains and how it is encoded/decoded.
///
/// A code carries everything a sender needs to dial a receiver directly,
/// bypassing radar discovery entirely (which matters on networks with
/// AP-isolation that silently block the UDP beacon):
///   * [hostIp] / [port] — where to connect.
///   * [name]            — the receiver's friendly name, shown to the sender.
///   * [fingerprint]     — SHA-256 of the receiver's TLS cert DER, for
///                         out-of-band identity pinning (forward-looking).
///
/// Phone-hosted-hotspot codes additionally carry [ssid]/[password] so the
/// sender joins the Wi-Fi first, then connects to [hostIp].
class ConnectCode {
  const ConnectCode({
    this.hostIp,
    this.port = defaultPort,
    this.name,
    this.fingerprint,
    this.ssid,
    this.password,
  });

  /// The transfer port (TLS). Matches Wire.transferPort / the native engines.
  static const int defaultPort = 8988;

  final String? hostIp;
  final int port;
  final String? name;

  /// Hex SHA-256 of the receiver's certificate DER.
  final String? fingerprint;

  final String? ssid;
  final String? password;

  bool get hasAddress => hostIp != null && hostIp!.isNotEmpty;

  bool get hasHotspot =>
      ssid != null && ssid!.isNotEmpty && password != null && password!.isNotEmpty;

  String encode() => jsonEncode({
        'k': 'karlshare',
        if (hasAddress) 'h': hostIp,
        'port': port,
        if (name != null && name!.isNotEmpty) 'n': name,
        if (fingerprint != null && fingerprint!.isNotEmpty) 'fp': fingerprint,
        if (hasHotspot) 's': ssid,
        if (hasHotspot) 'p': password,
      });

  /// Parses a scanned QR string, or null if it is not a Karlshare code.
  static ConnectCode? tryParse(String raw) {
    Map<String, dynamic> map;
    try {
      map = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
    if (map['k'] != 'karlshare') return null;
    return ConnectCode(
      hostIp: map['h'] as String?,
      port: (map['port'] as num?)?.toInt() ?? defaultPort,
      name: map['n'] as String?,
      fingerprint: map['fp'] as String?,
      ssid: map['s'] as String?,
      password: map['p'] as String?,
    );
  }
}
