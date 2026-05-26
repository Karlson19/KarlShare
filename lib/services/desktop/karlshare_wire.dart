import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

/// Dart implementation of the Karlshare binary wire protocol (spec §7.2),
/// matching the Kotlin and Swift codecs byte for byte. Big-endian throughout.
/// Used by the desktop transfer engine.
class Wire {
  Wire._();

  static const int version = 2;
  static const int transferPort = 8988;
  static const int defaultChunkSize = 256 * 1024;

  static const int tagFileHeader = 0x02;
  static const int tagChunk = 0x03;
  static const int tagAck = 0x04;
  static const int tagCancel = 0x05;

  static const int capParallelChunks = 1 << 1;
  static const int capTls = 1 << 2;

  // ---- encode --------------------------------------------------------------

  static Uint8List handshake({
    required Uint8List deviceId, // 16 bytes
    required Uint8List publicKey, // 32 bytes (sha-256 fingerprint)
    required int capabilities,
  }) {
    assert(deviceId.length == 16 && publicKey.length == 32);
    final b = BytesBuilder();
    b.add(_u16(version));
    b.add(deviceId);
    b.add(publicKey);
    b.addByte(capabilities & 0xFF);
    return b.toBytes();
  }

  static Uint8List fileHeader({
    required Uint8List fileId,
    required String name,
    required int size,
    required String mime,
    required Uint8List checksum, // 32 bytes
  }) {
    final nameBytes = utf8.encode(name);
    final mimeBytes = utf8.encode(mime);
    final b = BytesBuilder();
    b.addByte(tagFileHeader);
    b.add(fileId);
    b.add(_u16(nameBytes.length));
    b.add(nameBytes);
    b.add(_u64(size));
    b.addByte(mimeBytes.length & 0xFF);
    b.add(mimeBytes);
    b.add(checksum);
    return b.toBytes();
  }

  static Uint8List chunk({
    required Uint8List fileId,
    required int index,
    required Uint8List data,
  }) {
    final b = BytesBuilder();
    b.addByte(tagChunk);
    b.add(fileId);
    b.add(_u32(index));
    b.add(_u32(data.length));
    b.add(data);
    return b.toBytes();
  }

  static Uint8List cancel(Uint8List fileId) {
    final b = BytesBuilder();
    b.addByte(tagCancel);
    b.add(fileId);
    return b.toBytes();
  }

  // ---- decode --------------------------------------------------------------

  static Future<Handshake> readHandshake(ByteReader read) async {
    final version = _readU16(await read(2));
    final deviceId = await read(16);
    final publicKey = await read(32);
    final cap = (await read(1))[0];
    return Handshake(version, deviceId, publicKey, cap);
  }

  /// Reads one tag-prefixed frame, or null on clean EOF.
  static Future<Frame?> readFrame(ByteReader read) async {
    final Uint8List tagBytes;
    try {
      tagBytes = await read(1);
    } on WireEof {
      return null;
    }
    switch (tagBytes[0]) {
      case tagFileHeader:
        final fileId = await read(16);
        final nameLen = _readU16(await read(2));
        final name = utf8.decode(await read(nameLen));
        final size = _readU64(await read(8));
        final mimeLen = (await read(1))[0];
        final mime = utf8.decode(await read(mimeLen));
        final checksum = await read(32);
        return Frame.header(FileHeaderMsg(fileId, name, size, mime, checksum));
      case tagChunk:
        final fileId = await read(16);
        final index = _readU32(await read(4));
        final len = _readU32(await read(4));
        if (len < 0 || len > 8 * 1024 * 1024) {
          throw const WireError('implausible chunk size');
        }
        final data = await read(len);
        return Frame.chunk(ChunkMsg(fileId, index, data));
      case tagAck:
        await read(16);
        await read(4);
        await read(1);
        return const Frame.ack();
      case tagCancel:
        await read(16);
        return const Frame.cancel();
      default:
        throw WireError('unknown frame tag 0x${tagBytes[0].toRadixString(16)}');
    }
  }

  // ---- int helpers (big-endian) -------------------------------------------

  static Uint8List _u16(int v) =>
      (ByteData(2)..setUint16(0, v, Endian.big)).buffer.asUint8List();
  static Uint8List _u32(int v) =>
      (ByteData(4)..setUint32(0, v, Endian.big)).buffer.asUint8List();
  static Uint8List _u64(int v) =>
      (ByteData(8)..setUint64(0, v, Endian.big)).buffer.asUint8List();

  static int _readU16(Uint8List b) => ByteData.sublistView(b).getUint16(0, Endian.big);
  static int _readU32(Uint8List b) => ByteData.sublistView(b).getUint32(0, Endian.big);
  static int _readU64(Uint8List b) => ByteData.sublistView(b).getUint64(0, Endian.big);
}

/// Reads exactly [n] bytes; throws [WireEof] if the stream ends first.
typedef ByteReader = Future<Uint8List> Function(int n);

class WireEof implements Exception {
  const WireEof();
}

class WireError implements Exception {
  const WireError(this.message);
  final String message;
  @override
  String toString() => 'WireError: $message';
}

class Handshake {
  Handshake(this.version, this.deviceId, this.publicKey, this.capabilities);
  final int version;
  final Uint8List deviceId;
  final Uint8List publicKey;
  final int capabilities;
}

class FileHeaderMsg {
  FileHeaderMsg(this.fileId, this.name, this.size, this.mime, this.checksum);
  final Uint8List fileId;
  final String name;
  final int size;
  final String mime;
  final Uint8List checksum;
}

class ChunkMsg {
  ChunkMsg(this.fileId, this.index, this.data);
  final Uint8List fileId;
  final int index;
  final Uint8List data;
}

enum FrameType { header, chunk, ack, cancel }

class Frame {
  const Frame.header(this.header)
      : type = FrameType.header,
        chunk = null;
  const Frame.chunk(this.chunk)
      : type = FrameType.chunk,
        header = null;
  const Frame.ack()
      : type = FrameType.ack,
        header = null,
        chunk = null;
  const Frame.cancel()
      : type = FrameType.cancel,
        header = null,
        chunk = null;

  final FrameType type;
  final FileHeaderMsg? header;
  final ChunkMsg? chunk;
}

/// Buffers a byte [Stream] (a socket) and hands out exact-length reads.
class StreamByteReader {
  StreamByteReader(Stream<Uint8List> stream) {
    _sub = stream.listen(
      _onData,
      onError: (Object e) => _fail(e),
      onDone: _onDone,
      cancelOnError: true,
    );
  }

  late final StreamSubscription<Uint8List> _sub;
  final List<Uint8List> _chunks = [];
  int _available = 0;
  Completer<void>? _waiter;
  bool _done = false;
  Object? _error;

  Future<Uint8List> read(int n) async {
    while (_available < n) {
      if (_error != null) throw _error!;
      if (_done) throw const WireEof();
      _waiter = Completer<void>();
      await _waiter!.future;
    }
    return _take(n);
  }

  Uint8List _take(int n) {
    final out = Uint8List(n);
    var written = 0;
    while (written < n) {
      final head = _chunks.first;
      final need = n - written;
      if (head.length <= need) {
        out.setRange(written, written + head.length, head);
        written += head.length;
        _chunks.removeAt(0);
      } else {
        out.setRange(written, written + need, head);
        _chunks[0] = Uint8List.sublistView(head, need);
        written += need;
      }
    }
    _available -= n;
    return out;
  }

  void _onData(Uint8List data) {
    if (data.isEmpty) return;
    _chunks.add(data);
    _available += data.length;
    _wake();
  }

  void _onDone() {
    _done = true;
    _wake();
  }

  void _fail(Object e) {
    _error = e;
    _wake();
  }

  void _wake() {
    final w = _waiter;
    if (w != null && !w.isCompleted) {
      _waiter = null;
      w.complete();
    }
  }

  Future<void> cancel() => _sub.cancel();
}
