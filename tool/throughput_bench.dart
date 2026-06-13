// Measures the sender-side throughput win from pipelining, runnable with
//   dart run tool/throughput_bench.dart
//
// It pushes a large payload over a real loopback TLS socket two ways and
// reports MB/s for each:
//   OLD  — 256 KB chunks, flush after every chunk (the pre-turbo engine)
//   NEW  — 1 MB chunks, flush every 4 MB (the pipelined engine)
//
// Loopback has effectively unlimited bandwidth, so what this isolates is the
// per-flush overhead the old path paid on every chunk. On a real Wi-Fi link
// the absolute numbers differ, but removing that serialization is what lets the
// link stay saturated.

// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:karlshare/services/desktop/karlshare_wire.dart';

SecurityContext _serverCtx() {
  final pair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
  final priv = pair.privateKey as RSAPrivateKey;
  final pub = pair.publicKey as RSAPublicKey;
  final csr = X509Utils.generateRsaCsrPem({'CN': 'Bench', 'O': 'Karlshare'}, priv, pub);
  final certPem = X509Utils.generateSelfSignedCertificate(priv, csr, 3650);
  final keyPem = CryptoUtils.encodeRSAPrivateKeyToPem(priv);
  return SecurityContext(withTrustedRoots: false)
    ..useCertificateChainBytes(utf8.encode(certPem))
    ..usePrivateKeyBytes(utf8.encode(keyPem));
}

Future<double> _run({
  required SecurityContext serverCtx,
  required int chunkSize,
  required int flushEvery,
  required int totalBytes,
}) async {
  var received = 0;
  final done = Completer<void>();
  final ss = await SecureServerSocket.bind(
    InternetAddress.loopbackIPv4, 8990, serverCtx,
    requestClientCertificate: false,
  );
  ss.listen((sock) {
    sock.listen((d) => received += d.length,
        onDone: () => done.isCompleted ? null : done.complete());
  });

  final sock = await SecureSocket.connect(
    InternetAddress.loopbackIPv4, 8990,
    context: SecurityContext(withTrustedRoots: false),
    onBadCertificate: (_) => true,
  );
  sock.setOption(SocketOption.tcpNoDelay, true);

  final fileId = Uint8List(16);
  final buf = Uint8List(chunkSize); // content is irrelevant for throughput
  final chunks = (totalBytes / chunkSize).ceil();
  var sinceFlush = 0;

  final sw = Stopwatch()..start();
  for (var i = 0; i < chunks; i++) {
    sock.add(Wire.chunk(fileId: fileId, index: i, data: buf));
    sinceFlush += chunkSize;
    if (sinceFlush >= flushEvery) {
      await sock.flush();
      sinceFlush = 0;
    }
  }
  await sock.flush();
  await sock.close();
  await done.future.timeout(const Duration(seconds: 180));
  sw.stop();
  await ss.close();

  final payloadMb = (chunks * chunkSize) / (1024 * 1024);
  final secs = sw.elapsedMilliseconds / 1000.0;
  return payloadMb / secs;
}

Future<void> main() async {
  const totalBytes = 512 * 1024 * 1024; // 512 MB
  final ctx = _serverCtx();
  print('Pushing ${totalBytes ~/ (1024 * 1024)} MB over loopback TLS...\n');

  final oldRate = await _run(
    serverCtx: ctx,
    chunkSize: 256 * 1024,
    flushEvery: 256 * 1024, // flush every chunk = the old engine
    totalBytes: totalBytes,
  );
  print('OLD  (256 KB chunks, flush/chunk):  ${oldRate.toStringAsFixed(1)} MB/s');

  final newRate = await _run(
    serverCtx: ctx,
    chunkSize: Wire.defaultChunkSize,
    flushEvery: Wire.flushEvery,
    totalBytes: totalBytes,
  );
  print('NEW  (1 MB chunks, flush/4 MB):     ${newRate.toStringAsFixed(1)} MB/s');

  final speedup = oldRate > 0 ? newRate / oldRate : 0;
  print('\n==== ${speedup.toStringAsFixed(1)}x faster on this machine ====');
  exit(0);
}
