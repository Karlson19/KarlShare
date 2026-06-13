import 'dart:async';
import 'dart:convert' show ByteConversionSink;
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show Digest, sha256;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../transfer_service.dart';
import 'desktop_identity.dart';
import 'karlshare_wire.dart';

/// Pure-Dart TLS transfer engine. Runs on desktop (Windows/Linux/macOS) AND on
/// Android — both ends of a transfer execute this same code, which is what the
/// loopback test verifies. Produces [TransferEvent]s the UI consumes unchanged.
class DartTransferEngine {
  final _controller = StreamController<TransferEvent>.broadcast();
  final _rand = Random.secure();
  final Set<String> _cancelled = {};

  SecureServerSocket? _server;
  Directory? _saveDir;

  /// This device's friendly name, sent in the handshake so the peer can show
  /// "Karlson's phone" instead of a bare IP. Set by the app from the user
  /// profile (mobile) or hostname (desktop).
  String localName = '';

  /// Platform hook: moves a fully-received, checksum-verified file from the
  /// app-private save dir to wherever the user can see it (Android hands it to
  /// MediaStore so it appears in Gallery/Files). Returns the user-facing
  /// location, or null to keep the original path. Errors here must not fail
  /// the transfer — the file is already intact.
  Future<String?> Function(String path, String name, String mime)?
      publishReceivedFile;

  Stream<TransferEvent> events() => _controller.stream;

  void _emit({
    required TransferEventType type,
    required String transferId,
    String? fileId,
    String? fileName,
    String? fileMime,
    int fileSize = 0,
    String? savePath,
    int fileCount = 0,
    int fileBytes = 0,
    int fileTotal = 0,
    int totalBytes = 0,
    int grandTotal = 0,
    String? direction,
    String? message,
    String? peerIp,
    String? peerName,
  }) {
    _controller.add(TransferEvent(
      type: type,
      transferId: transferId,
      fileId: fileId,
      fileName: fileName,
      fileMime: fileMime,
      fileSize: fileSize,
      savePath: savePath,
      fileCount: fileCount,
      fileBytes: fileBytes,
      fileTotal: fileTotal,
      totalBytes: totalBytes,
      grandTotal: grandTotal,
      direction: direction,
      peerName: peerName,
      message: message,
      peerIp: peerIp,
    ));
  }

  // ---- receiver -----------------------------------------------------------

  Future<void> startServer() async {
    if (_server != null) return;
    final id = await DesktopIdentity.load();
    await _ensureSaveDir();
    _server = await SecureServerSocket.bind(
      InternetAddress.anyIPv4,
      Wire.transferPort,
      id.securityContext,
      // Don't request a client cert: dart:io would reject the sender's
      // self-signed cert at the TLS layer. The sender still verifies us
      // (one-way auth), and the channel stays TLS-encrypted.
      requestClientCertificate: false,
    );
    _server!.listen(
      (socket) => unawaited(_handleIncoming(socket, id)),
      onError: (Object e) => _emit(type: TransferEventType.error, transferId: '', message: 'server: $e'),
    );
  }

  Future<void> stopServer() async {
    await _server?.close();
    _server = null;
  }

  Future<void> _handleIncoming(SecureSocket socket, DesktopIdentity id) async {
    final transferId = _uuid();
    final reader = StreamByteReader(socket);
    final open = <String, _RecvFile>{};
    var grand = 0;
    var recvTotal = 0;
    String? peerIp;
    try {
      peerIp = socket.remoteAddress.address;
    } catch (_) {
      // Socket may already be torn down; peerIp stays null (no send-back).
    }
    String? peerName;
    try {
      socket.setOption(SocketOption.tcpNoDelay, true);
      final remote = await Wire.readHandshake(reader.read);
      peerName = remote.name.isNotEmpty ? remote.name : null;
      socket.add(Wire.handshake(
          deviceId: id.deviceId,
          publicKey: id.fingerprint,
          capabilities: Wire.capTls,
          name: localName));
      await socket.flush();
      await _verifyPeer(socket, remote);

      while (!_cancelled.contains(transferId)) {
        final frame = await Wire.readFrame(reader.read);
        if (frame == null) break;
        switch (frame.type) {
          case FrameType.header:
            final h = frame.header!;
            final fid = _hex(h.fileId);
            final target = await _uniqueFile(h.name);
            final raf = await target.open(mode: FileMode.write);
            open[fid] = _RecvFile(h, target, raf);
            grand += h.size;
            _emit(
              type: TransferEventType.header,
              transferId: transferId,
              fileId: fid,
              fileName: h.name,
              fileSize: h.size,
              fileMime: h.mime,
              savePath: target.path,
              direction: 'received',
              peerIp: peerIp,
              peerName: peerName,
            );
            if (h.size == 0) {
              await raf.close();
              final rf = open.remove(fid)!;
              await _finish(rf, transferId, fid);
            }
            break;
          case FrameType.chunk:
            final c = frame.chunk!;
            final fid = _hex(c.fileId);
            final rf = open[fid];
            if (rf == null) break;
            await rf.raf.writeFrom(c.data);
            rf.updateDigest(c.data);
            rf.received += c.data.length;
            recvTotal += c.data.length;
            _emit(
              type: TransferEventType.progress,
              transferId: transferId,
              fileId: fid,
              fileBytes: rf.received,
              fileTotal: rf.header.size,
              totalBytes: recvTotal,
              grandTotal: grand,
            );
            if (rf.received >= rf.header.size) {
              await rf.raf.close();
              open.remove(fid);
              await _finish(rf, transferId, fid);
            }
            break;
          case FrameType.ack:
            break;
          case FrameType.cancel:
            _cancelled.add(transferId);
            break;
        }
      }
      _emit(type: TransferEventType.transferComplete, transferId: transferId);
    } catch (e) {
      _emit(type: TransferEventType.error, transferId: transferId, message: '$e');
    } finally {
      // Anything still open here never completed — close and remove the
      // partial file so cancels/disconnects don't litter half-written junk.
      for (final rf in open.values) {
        try {
          await rf.raf.close();
        } catch (_) {}
        try {
          await rf.target.delete();
        } catch (_) {}
      }
      _cancelled.remove(transferId);
      socket.destroy();
    }
  }

  Future<void> _finish(_RecvFile rf, String transferId, String fid) async {
    final ok = _bytesEqual(rf.finishDigest(), rf.header.checksum);
    if (!ok) {
      // Never leave a corrupt file where the user will find it.
      try {
        await rf.target.delete();
      } catch (_) {}
    }
    var savePath = rf.target.path;
    if (ok && publishReceivedFile != null) {
      try {
        final published = await publishReceivedFile!(
            rf.target.path, rf.header.name, rf.header.mime);
        if (published != null && published.isNotEmpty) savePath = published;
      } catch (_) {
        // Publishing is best-effort; the verified file stays at savePath.
      }
    }
    _emit(
      type: ok ? TransferEventType.fileComplete : TransferEventType.error,
      transferId: transferId,
      fileId: fid,
      savePath: ok ? savePath : null,
      message: ok ? null : 'checksum mismatch',
    );
  }

  // ---- sender -------------------------------------------------------------

  Future<String?> sendFiles(String peerIp, List<OutgoingFile> files) async {
    final id = await DesktopIdentity.load();
    final transferId = _uuid();
    final grand = files.fold<int>(0, (s, f) => s + f.size);
    _emit(
      type: TransferEventType.started,
      transferId: transferId,
      fileCount: files.length,
      totalBytes: grand,
      direction: 'sent',
    );

    unawaited(() async {
      SecureSocket? socket;
      try {
        socket = await SecureSocket.connect(
          peerIp,
          Wire.transferPort,
          context: id.securityContext,
          onBadCertificate: (_) => true,
          timeout: const Duration(seconds: 15),
        );
        socket.setOption(SocketOption.tcpNoDelay, true);
        final reader = StreamByteReader(socket);
        socket.add(Wire.handshake(
            deviceId: id.deviceId,
            publicKey: id.fingerprint,
            capabilities: Wire.capTls,
            name: localName));
        await socket.flush();
        final remote = await Wire.readHandshake(reader.read);
        await _verifyPeer(socket, remote);

        var sentTotal = 0;
        for (final f in files) {
          if (_cancelled.contains(transferId)) break;
          sentTotal = await _sendOne(socket, f, transferId, sentTotal, grand);
        }
        // Graceful close so every queued chunk is delivered before the FIN —
        // a hard destroy() here can truncate the last chunk and fail the
        // receiver's checksum.
        await socket.flush();
        await socket.close();
        _emit(
          type: _cancelled.contains(transferId)
              ? TransferEventType.cancelled
              : TransferEventType.transferComplete,
          transferId: transferId,
        );
      } catch (e) {
        _emit(type: TransferEventType.error, transferId: transferId, message: '$e');
      } finally {
        _cancelled.remove(transferId);
        socket?.destroy();
      }
    }());

    return transferId;
  }

  Future<int> _sendOne(
      SecureSocket socket, OutgoingFile f, String transferId, int sentTotal, int grand) async {
    final file = File(f.path);
    final checksum = await _sha256File(file);
    final fileId = _rand16();
    // Events use the caller's file id (the picker's) so the sender UI can match
    // progress to the rows it already shows; the wire keeps its own 16-byte id.
    final fid = f.id ?? _hex(fileId);
    // The header and chunks ride the same ordered TLS stream, so no flush is
    // needed between them — TCP preserves order.
    socket.add(Wire.fileHeader(
      fileId: fileId,
      name: f.name,
      size: f.size,
      mime: f.mime,
      checksum: checksum,
    ));
    _emit(
      type: TransferEventType.header,
      transferId: transferId,
      fileId: fid,
      fileName: f.name,
      fileSize: f.size,
      fileMime: f.mime,
    );

    final raf = await file.open();
    var index = 0;
    var fileSent = 0;
    var running = sentTotal;
    var sinceFlush = 0;
    try {
      while (!_cancelled.contains(transferId)) {
        // RandomAccessFile.read already returns a Uint8List — pass it straight
        // through, no extra copy.
        final data = await raf.read(Wire.defaultChunkSize);
        if (data.isEmpty) break;
        socket.add(Wire.chunk(fileId: fileId, index: index, data: data));
        index++;
        fileSent += data.length;
        running += data.length;
        sinceFlush += data.length;
        // Pipeline: only drain (and apply backpressure) every few MB, not every
        // chunk. This bounds in-flight memory while keeping the link busy.
        if (sinceFlush >= Wire.flushEvery) {
          await socket.flush();
          sinceFlush = 0;
        }
        _emit(
          type: TransferEventType.progress,
          transferId: transferId,
          fileId: fid,
          fileBytes: fileSent,
          fileTotal: f.size,
          totalBytes: running,
          grandTotal: grand,
        );
      }
    } finally {
      await raf.close();
    }
    return running;
  }

  Future<void> cancel(String transferId) async {
    _cancelled.add(transferId);
  }

  Future<void> forgetAllPeers() async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in prefs.getKeys().where((k) => k.startsWith('ks_peer_'))) {
      await prefs.remove(k);
    }
  }

  // ---- handshake verification (TOFU) --------------------------------------

  Future<void> _verifyPeer(SecureSocket socket, Handshake remote) async {
    final cert = socket.peerCertificate;
    // Receiver side: we didn't request a client cert, so there's nothing to
    // bind here (the sender still verifies us). When we're the sender, the
    // server's cert is always present and gets bound below.
    if (cert == null) return;
    final actual = DesktopIdentity.fingerprintOfDer(Uint8List.fromList(cert.der));
    if (!_bytesEqual(actual, remote.publicKey)) {
      throw const TransferSecurityError('peer fingerprint does not match handshake (MITM?)');
    }
    final prefs = await SharedPreferences.getInstance();
    final key = 'ks_peer_${_hex(remote.deviceId)}';
    final pinned = prefs.getString(key);
    final encoded = _hex(actual);
    if (pinned == null) {
      await prefs.setString(key, encoded);
    } else if (pinned != encoded) {
      throw const TransferSecurityError('this device\'s identity changed — refusing');
    }
  }

  // ---- helpers ------------------------------------------------------------

  Future<Directory> _ensureSaveDir() async {
    if (_saveDir != null) return _saveDir!;
    Directory base;
    try {
      base = (await getDownloadsDirectory()) ?? await getApplicationDocumentsDirectory();
    } catch (_) {
      base = await getApplicationDocumentsDirectory();
    }
    final dir = Directory('${base.path}${Platform.pathSeparator}Karlshare');
    await dir.create(recursive: true);
    return _saveDir = dir;
  }

  Future<File> _uniqueFile(String name) async {
    final dir = await _ensureSaveDir();
    final sep = Platform.pathSeparator;
    var candidate = File('${dir.path}$sep$name');
    if (!candidate.existsSync()) return candidate;
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    var i = 1;
    while (candidate.existsSync()) {
      candidate = File('${dir.path}$sep$stem ($i)$ext');
      i++;
    }
    return candidate;
  }

  /// Streams the file through SHA-256 — constant memory regardless of size,
  /// so hashing a movie doesn't load the whole thing into RAM first.
  Future<Uint8List> _sha256File(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return Uint8List.fromList(digest.bytes);
  }

  Uint8List _rand16() =>
      Uint8List.fromList(List.generate(16, (_) => _rand.nextInt(256)));

  String _uuid() => _hex(_rand16());

  static String _hex(Uint8List b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class TransferSecurityError implements Exception {
  const TransferSecurityError(this.message);
  final String message;
  @override
  String toString() => message;
}

class _RecvFile {
  _RecvFile(this.header, this.target, this.raf);
  final FileHeaderMsg header;
  final File target;
  final RandomAccessFile raf;
  int received = 0;

  // SHA-256 folded in as chunks arrive, so verification at the end is free —
  // no re-reading a (possibly huge) file from disk after the transfer.
  final _digestOut = _DigestSink();
  late final ByteConversionSink _digestIn =
      sha256.startChunkedConversion(_digestOut);

  void updateDigest(List<int> data) => _digestIn.add(data);

  Uint8List finishDigest() {
    _digestIn.close();
    return Uint8List.fromList(_digestOut.value!.bytes);
  }
}

/// Minimal sink to capture the single [Digest] the chunked conversion emits.
class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
