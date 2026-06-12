import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:karlshare/features/transfer/providers/transfer_provider.dart';
import 'package:karlshare/models/device.dart';
import 'package:karlshare/models/enums.dart';
import 'package:karlshare/models/transfer_file.dart';
import 'package:karlshare/providers/storage_provider.dart';
import 'package:karlshare/services/transfer_service.dart';

/// Phase 0 regression suite: the old single-transfer state dropped every event
/// whose transferId differed from the one being tracked, so received files
/// stopped rendering mid-session. These tests simulate the engine event stream
/// for the exact scenarios that broke and assert that NOTHING is dropped.
void main() {
  late _FakeTransferService service;
  late ProviderContainer container;

  setUp(() {
    service = _FakeTransferService();
    container = ProviderContainer(overrides: [
      transferServiceProvider.overrideWithValue(service),
      transfersBoxProvider.overrideWithValue(_MemBox()),
    ]);
    // Instantiate the notifier so it subscribes to the event stream.
    container.read(transferSessionProvider.notifier);
  });

  tearDown(() => container.dispose());

  /// Lets stream microtasks and the 33ms coalescing timer drain.
  Future<void> pump() => Future<void>.delayed(const Duration(milliseconds: 80));

  TransferEvent header(String tid, String fid, {String? peerIp = '10.0.0.9'}) =>
      TransferEvent(
        type: TransferEventType.header,
        transferId: tid,
        fileId: fid,
        fileName: '$fid.jpg',
        fileSize: 1000,
        direction: 'received',
        peerIp: peerIp,
      );

  TransferEvent progress(String tid, String fid, int bytes) => TransferEvent(
        type: TransferEventType.progress,
        transferId: tid,
        fileId: fid,
        fileBytes: bytes,
        fileTotal: 1000,
        totalBytes: bytes,
      );

  TransferEvent fileDone(String tid, String fid) => TransferEvent(
        type: TransferEventType.fileComplete,
        transferId: tid,
        fileId: fid,
        savePath: '/saved/$fid.jpg',
      );

  TransferEvent transferDone(String tid) => TransferEvent(
        type: TransferEventType.transferComplete,
        transferId: tid,
      );

  test('REGRESSION: overlapping incoming transfers are both tracked', () async {
    // Transfer B starts while A is still mid-flight — the exact case the old
    // model dropped wholesale.
    service.emit(header('A', 'a1'));
    service.emit(progress('A', 'a1', 500));
    service.emit(header('B', 'b1')); // overlaps A
    service.emit(progress('B', 'b1', 500));
    service.emit(fileDone('A', 'a1'));
    service.emit(fileDone('B', 'b1'));
    service.emit(transferDone('A'));
    service.emit(transferDone('B'));
    await pump();

    final session = container.read(transferSessionProvider);
    expect(session.transfers.length, 2, reason: 'both transfers must exist');
    expect(session.transfers['B'], isNotNull, reason: 'B must not be dropped');
    expect(session.renderedReceivedFilesDone, 2);
    expect(session.protocolFilesDone, 2, reason: 'integrity counters agree');
    expect(session.transfers['A']!.status, TransferStatus.completed);
    expect(session.transfers['B']!.status, TransferStatus.completed);
  });

  test('150-file session renders every single file', () async {
    for (var i = 0; i < 150; i++) {
      final fid = 'f$i';
      service.emit(header('big', fid));
      service.emit(progress('big', fid, 1000));
      service.emit(fileDone('big', fid));
    }
    service.emit(transferDone('big'));
    await pump();

    final session = container.read(transferSessionProvider);
    expect(session.transfers['big']!.files.length, 150);
    expect(session.renderedReceivedFilesDone, 150,
        reason: 'no dropped entries in a long session');
    expect(session.protocolFilesDone, 150);
    expect(
      session.transfers['big']!.files.every((f) => f.path != null),
      isTrue,
      reason: 'every file keeps its save path',
    );
  });

  test('bidirectional: incoming mid-send is adopted alongside the outgoing',
      () async {
    final notifier = container.read(transferSessionProvider.notifier);
    final ok = await notifier.start(
      device: const Device(
        id: 'peer',
        name: 'KarlsonPC',
        status: DeviceStatus.ready,
        ipAddress: '10.0.0.7',
      ),
      files: const [
        TransferFile(
          id: 'p1',
          name: 'mine.pdf',
          sizeBytes: 2000,
          type: KFileType.document,
          path: '/tmp/mine.pdf',
        ),
      ],
    );
    expect(ok, isTrue);

    // Peer starts sending to us while our send is still running.
    service.emit(header('IN', 'x1'));
    service.emit(fileDone('IN', 'x1'));
    service.emit(transferDone('IN'));
    await pump();

    final session = container.read(transferSessionProvider);
    expect(session.transfers.length, 2);
    final outgoing = session.transfers['out-1']!;
    expect(outgoing.direction, TransferDirection.sent);
    expect(outgoing.files.single.name, 'mine.pdf',
        reason: 'outgoing keeps the picker file metadata');
    final incoming = session.transfers['IN']!;
    expect(incoming.direction, TransferDirection.received);
    expect(incoming.status, TransferStatus.completed);
    // The sender is remembered for one-tap send-back.
    expect(
      container.read(lastReceivedDeviceProvider)?.ipAddress,
      '10.0.0.9',
    );
  });

  test('a stalled transfer never deafens the session', () async {
    // A opens and then goes silent (peer crashed; no terminal event arrives).
    service.emit(header('stalled', 's1'));
    // B must still flow through completely.
    service.emit(header('B', 'b1'));
    service.emit(fileDone('B', 'b1'));
    service.emit(transferDone('B'));
    await pump();

    final session = container.read(transferSessionProvider);
    expect(session.transfers['B']!.status, TransferStatus.completed);
    expect(session.renderedReceivedFilesDone, 1);
    expect(session.protocolFilesDone, 1);
    expect(session.transfers['stalled']!.status, TransferStatus.transferring);
  });

  test('clearFinished removes done transfers but keeps in-flight ones',
      () async {
    service.emit(header('done', 'd1'));
    service.emit(fileDone('done', 'd1'));
    service.emit(transferDone('done'));
    service.emit(header('running', 'r1'));
    await pump();

    container.read(transferSessionProvider.notifier).clearFinished();
    await pump();

    final session = container.read(transferSessionProvider);
    expect(session.transfers.containsKey('done'), isFalse);
    expect(session.transfers.containsKey('running'), isTrue,
        reason: 'an in-flight transfer survives Done');
    expect(session.protocolFilesDone, 0,
        reason: 'integrity baseline shrinks with the session, no false alarms');
  });

  test('progress floods coalesce without losing the final value', () async {
    service.emit(header('flood', 'f1'));
    for (var b = 0; b <= 1000; b += 10) {
      service.emit(progress('flood', 'f1', b));
    }
    await pump();

    final session = container.read(transferSessionProvider);
    expect(session.transfers['flood']!.files.single.progress, 1.0,
        reason: 'last progress value always lands');
  });
}

/// Engine stand-in: a hand-driven event stream.
class _FakeTransferService extends TransferService {
  final _controller = StreamController<TransferEvent>.broadcast(sync: true);

  void emit(TransferEvent e) => _controller.add(e);

  @override
  bool get isPlatformSupported => true;

  @override
  Stream<TransferEvent> events() => _controller.stream;

  @override
  Future<String?> sendFiles({
    required String peerIp,
    required List<OutgoingFile> files,
  }) async =>
      'out-1';

  @override
  Future<void> cancel(String transferId) async {}

  @override
  Future<void> startServer() async {}
}

/// In-memory Box so historyProvider works without Hive in tests.
class _MemBox implements Box<Map<dynamic, dynamic>> {
  final _store = <dynamic, Map<dynamic, dynamic>>{};

  @override
  Iterable<Map<dynamic, dynamic>> get values => _store.values;

  @override
  Future<void> put(dynamic key, Map<dynamic, dynamic> value) async {
    _store[key] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('not used in tests');
}
