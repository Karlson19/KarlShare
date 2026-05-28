import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart' show sha256;
import 'package:path_provider/path_provider.dart';

/// The desktop's TLS identity: a self-signed RSA cert generated once and
/// reused. The binding fingerprint is SHA-256 of the whole certificate DER, the
/// same scheme Android uses, so the cross-platform handshake matches.
class DesktopIdentity {
  DesktopIdentity._({
    required this.deviceId,
    required this.fingerprint,
    required this.securityContext,
  });

  /// 16-byte stable device id sent in the handshake.
  final Uint8List deviceId;

  /// SHA-256 of our cert DER (32 bytes) — the handshake binding token.
  final Uint8List fingerprint;

  final SecurityContext securityContext;

  static DesktopIdentity? _cached;

  static Future<DesktopIdentity> load() async {
    if (_cached != null) return _cached!;

    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    final certFile = File('${dir.path}/karlshare_cert.pem');
    final keyFile = File('${dir.path}/karlshare_key.pem');
    final idFile = File('${dir.path}/karlshare_id.txt');

    String certPem;
    String keyPem;
    Uint8List deviceId;

    if (certFile.existsSync() && keyFile.existsSync() && idFile.existsSync()) {
      certPem = certFile.readAsStringSync();
      keyPem = keyFile.readAsStringSync();
      deviceId = _hexToBytes(idFile.readAsStringSync().trim());
    } else {
      final pair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
      final priv = pair.privateKey as RSAPrivateKey;
      final pub = pair.publicKey as RSAPublicKey;
      final csr = X509Utils.generateRsaCsrPem(
        {'CN': Platform.localHostname, 'O': 'Karlshare'},
        priv,
        pub,
      );
      certPem = X509Utils.generateSelfSignedCertificate(priv, csr, 3650);
      keyPem = CryptoUtils.encodeRSAPrivateKeyToPem(priv);
      deviceId = _randomBytes(16);
      certFile.writeAsStringSync(certPem);
      keyFile.writeAsStringSync(keyPem);
      idFile.writeAsStringSync(_bytesToHex(deviceId));
    }

    final der = pemToDer(certPem);
    final fingerprint = Uint8List.fromList(sha256.convert(der).bytes);

    final ctx = SecurityContext(withTrustedRoots: false)
      ..useCertificateChainBytes(utf8.encode(certPem))
      ..usePrivateKeyBytes(utf8.encode(keyPem));

    return _cached = DesktopIdentity._(
      deviceId: deviceId,
      fingerprint: fingerprint,
      securityContext: ctx,
    );
  }

  /// SHA-256 of a peer certificate's DER — matches [fingerprint] semantics.
  static Uint8List fingerprintOfDer(Uint8List der) =>
      Uint8List.fromList(sha256.convert(der).bytes);

  static Uint8List pemToDer(String pem) {
    final body = pem
        .split('\n')
        .map((l) => l.trim()) // strip CR / whitespace (Windows PEMs use \r\n)
        .where((l) => l.isNotEmpty && !l.startsWith('-----'))
        .join();
    return base64.decode(body);
  }

  static Uint8List _randomBytes(int n) {
    final r = Random.secure();
    return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
  }

  static String _bytesToHex(Uint8List b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

  static Uint8List _hexToBytes(String h) {
    final out = Uint8List(h.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(h.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }
}
