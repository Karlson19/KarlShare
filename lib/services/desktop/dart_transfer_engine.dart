import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../transfer_service.dart';
import 'desktop_identity.dart';
import 'karlshare_wire.dart';

/// Pure-Dart TLS transfer engine for desktop (Windows/Linux/macOS). Speaks the
/// same Karlshare wire protocol and fingerprint-bound handshake as the Android
/// engine, so a PC and a phone interoperate. Produces [TransferEvent]s that the
/// existing UI consumes unchanged.
class DartTransferEngine {
  final _controller = StreamController<TransferEvent>.broadcast();
  final _rand = Random.secure();
  final Set<String> _cancelled = {};

  SecureServerSocket? _server;
  Directory? _saveDir;

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
      message: message,
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
      requestClientCertificate: true,
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
    try {
      socket.setOption(SocketOption.tcpNoDelay, true);
      final remote = await Wire.readHandshake(reader.read);
      socket.add(Wire.handshake(
          deviceId: id.deviceId, publicKey: id.fingerprint, capabilities: Wire.capTls));
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
            );
            if (h.size == 0) {
              await raf.close();
              open.remove(fid);
              await _finish(target, h, transferId, fid);
            }
            break;
          case FrameType.chunk:
            final c = frame.chunk!;
            final fid = _hex(c.fileId);
            final rf = open[fid];
            if (rf == null) break;
            await rf.raf.writeFrom(c.data);
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
              await _finish(rf.target, rf.header, transferId, fid);
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
      for (final rf in open.values) {
        try {
          await rf.raf.close();
        } catch (_) {}
      }
      _cancelled.remove(transferId);
      socket.destroy();
    }
  }

  Future<void> _finish(File target, FileHeaderMsg h, String transferId, String fid) async {
    final ok = await _checksumMatches(target, h.checksum);
    _emit(
      type: ok ? TransferEventType.fileComplete : TransferEventType.error,
      transferId: transferId,
      fileId: fid,
      savePath: ok ? target.path : null,
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
            deviceId: id.deviceId, publicKey: id.fingerprint, capabilities: Wire.capTls));
        await socket.flush();
        final remote = await Wire.readHandshake(reader.read);
        await _verifyPeer(socket, remote);

        var sentTotal = 0;
        for (final f in files) {
          if (_cancelled.contains(transferId)) break;
          sentTotal = await _sendOne(socket, f, transferId, sentTotal, grand);
        }
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
    final fid = _hex(fileId);
    socket.add(Wire.fileHeader(
      fileId: fileId,
      name: f.name,
      size: f.size,
      mime: f.mime,
      checksum: checksum,
    ));
    await socket.flush();
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
    try {
      while (!_cancelled.contains(transferId)) {
        final data = await raf.read(Wire.defaultChunkSize);
        if (data.isEmpty) break;
        socket.add(Wire.chunk(fileId: fileId, index: index, data: Uint8List.fromList(data)));
        await socket.flush();
        index++;
        fileSent += data.length;
        running += data.length;
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
    if (cert == null) throw const TransferSecurityError('peer presented no certificate');
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

  Future<Uint8List> _sha256File(File file) async {
    final bytes = await file.readAsBytes();
    return Uint8List.fromList(sha256.convert(bytes).bytes);
  }

  Future<bool> _checksumMatches(File file, Uint8List expected) async {
    final actual = await _sha256File(file);
    return _bytesEqual(actual, expected);
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
}
