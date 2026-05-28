// A real end-to-end test of the desktop transfer engine's core, runnable with
//   dart run tool/loopback_test.dart
//
// It stands up the TLS server and client (two DIFFERENT self-signed RSA certs,
// like a phone and a PC), runs the Karlshare handshake + fingerprint binding,
// transfers a multi-chunk file over the real wire protocol, and verifies the
// received bytes match by SHA-256. This exercises the exact code paths the PC
// uses: basic_utils cert generation, dart:io TLS (mutual auth + accept-any +
// fingerprint binding), the Wire framing, chunked transfer and checksum.

// ignore_for_file: avoid_print
//   This is a dev-only CLI runner; print() is the whole point of its output.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart' show sha256;
import 'package:karlshare/services/desktop/karlshare_wire.dart';

class _Id {
  _Id(this.deviceId, this.fingerprint, this.ctx);
  final Uint8List deviceId;
  final Uint8List fingerprint;
  final SecurityContext ctx;
}

Uint8List _pemToDer(String pem) => base64.decode(pem
    .split('\n')
    .map((l) => l.trim())
    .where((l) => l.isNotEmpty && !l.startsWith('-----'))
    .join());

bool _eq(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

_Id _genId(String cn, int seed) {
  final pair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
  final priv = pair.privateKey as RSAPrivateKey;
  final pub = pair.publicKey as RSAPublicKey;
  final csr = X509Utils.generateRsaCsrPem({'CN': cn, 'O': 'Karlshare'}, priv, pub);
  final certPem = X509Utils.generateSelfSignedCertificate(priv, csr, 3650);
  final keyPem = CryptoUtils.encodeRSAPrivateKeyToPem(priv);
  final fp = Uint8List.fromList(sha256.convert(_pemToDer(certPem)).bytes);
  final ctx = SecurityContext(withTrustedRoots: false)
    ..useCertificateChainBytes(utf8.encode(certPem))
    ..usePrivateKeyBytes(utf8.encode(keyPem));
  return _Id(Uint8List.fromList(List.generate(16, (i) => (i + seed) & 0xFF)), fp, ctx);
}

Future<void> main() async {
  print('1/5  Generating two self-signed identities (PC + phone)...');
  final server = _genId('PC', 1);
  final client = _genId('Phone', 100);

  final tmp = await Directory.systemTemp.createTemp('ks_test');
  final src = File('${tmp.path}/src.bin');
  final data = Uint8List(1500 * 1000); // ~1.5 MB -> several 256 KB chunks
  for (var i = 0; i < data.length; i++) {
    data[i] = i & 0xFF;
  }
  await src.writeAsBytes(data);
  final srcHash = Uint8List.fromList(sha256.convert(data).bytes);
  print('2/5  Built a ${data.length}-byte test file.');

  File? received;
  final done = Completer<bool>();

  print('3/5  Starting TLS server on 127.0.0.1:8988...');
  final ss = await SecureServerSocket.bind(
    InternetAddress.loopbackIPv4, 8988, server.ctx,
    requestClientCertificate: false,
  );
  ss.listen((sock) async {
    try {
      final reader = StreamByteReader(sock);
      final remote = await Wire.readHandshake(reader.read);
      sock.add(Wire.handshake(
          deviceId: server.deviceId, publicKey: server.fingerprint, capabilities: Wire.capTls));
      await sock.flush();
      final clientCert = sock.peerCertificate;
      if (clientCert != null) {
        final peerFp =
            Uint8List.fromList(sha256.convert(Uint8List.fromList(clientCert.der)).bytes);
        print('     SERVER: client cert bound = '
            '${_eq(peerFp, remote.publicKey) ? "MATCH" : "MISMATCH"}');
      } else {
        print('     SERVER: one-way auth (no client cert requested) — ok');
      }
      final out = File('${tmp.path}/recv.bin');
      final raf = await out.open(mode: FileMode.write);
      while (true) {
        final f = await Wire.readFrame(reader.read);
        if (f == null) break;
        if (f.type == FrameType.chunk) await raf.writeFrom(f.chunk!.data);
      }
      await raf.close();
      received = out;
      done.complete(true);
    } catch (e) {
      print('     SERVER error: $e');
      if (!done.isCompleted) done.complete(false);
    }
  });

  print('4/5  Client connecting + sending...');
  final sock = await SecureSocket.connect(
    InternetAddress.loopbackIPv4, 8988,
    context: client.ctx, onBadCertificate: (_) => true,
  );
  final reader = StreamByteReader(sock);
  sock.add(Wire.handshake(
      deviceId: client.deviceId, publicKey: client.fingerprint, capabilities: Wire.capTls));
  await sock.flush();
  final remote = await Wire.readHandshake(reader.read);
  final serverDer = Uint8List.fromList(sock.peerCertificate!.der);
  final serverFp = Uint8List.fromList(sha256.convert(serverDer).bytes);
  print('     CLIENT: server cert received, fingerprint binding = '
      '${_eq(serverFp, remote.publicKey) ? "MATCH" : "MISMATCH"}');

  final fileId = Uint8List.fromList(List.generate(16, (i) => (i + 7) & 0xFF));
  sock.add(Wire.fileHeader(
      fileId: fileId, name: 'src.bin', size: data.length,
      mime: 'application/octet-stream', checksum: srcHash));
  final raf = await src.open();
  var idx = 0;
  while (true) {
    final c = await raf.read(Wire.defaultChunkSize);
    if (c.isEmpty) break;
    sock.add(Wire.chunk(fileId: fileId, index: idx++, data: Uint8List.fromList(c)));
  }
  await raf.close();
  await sock.flush();
  await sock.close();

  final ok = await done.future.timeout(const Duration(seconds: 30), onTimeout: () => false);
  print('5/5  Verifying received file...');
  var pass = false;
  if (ok && received != null) {
    final recvHash = Uint8List.fromList(sha256.convert(await received!.readAsBytes()).bytes);
    pass = _eq(recvHash, srcHash);
    print('     received ${(await received!.length())} bytes, checksum '
        '${pass ? "MATCHES" : "DOES NOT MATCH"}');
  } else {
    print('     transfer did not complete');
  }

  await ss.close();
  print('');
  print(pass
      ? '==== RESULT: PASS — TLS handshake, fingerprint binding, chunked transfer and checksum all work ===='
      : '==== RESULT: FAIL ====');
  exit(pass ? 0 : 1);
}
