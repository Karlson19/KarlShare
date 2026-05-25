import Foundation
import Flutter
import Network
import CryptoKit

/// iOS TLS transfer engine — the counterpart to Android's `TransferEngine.kt`.
/// Serves incoming TLS 1.3 connections on `KarlshareProtocol.transferPort` and
/// dials out to a peer to send files, speaking the same binary wire protocol so
/// Android ↔ iOS interop works at the byte level (spec §7.2 / §7.3).
///
/// Security model matches Android: TLS 1.3 + mutual auth, accept-any at the TLS
/// layer, then bind the peer's cert-SPKI fingerprint to the value declared in
/// the Karlshare handshake, with TOFU pinning via `PeerTrustStore`.
final class TransferEngine: NSObject, FlutterStreamHandler {

    static let methodChannelName = "karlshare/transfer"
    static let eventChannelName = "karlshare/transfer/events"

    private let identity: KarlshareIdentity
    private let trustStore = PeerTrustStore()
    private let localDeviceId: UUID

    private let methodChannel: FlutterMethodChannel
    private let eventChannel: FlutterEventChannel
    private var eventSink: FlutterEventSink?

    private var listener: NWListener?
    private let netQueue = DispatchQueue(label: "karlshare.transfer.net")
    private var saveDir: URL

    private let lock = NSLock()
    private var cancelled = Set<String>()

    /// Set by AppDelegate to route `mc:`-addressed sends to MultipeerManager.
    var onMultipeerSend: ((String, [[String: Any]], String) -> Void)?

    enum EngineError: Error { case security(String) }

    init(messenger: FlutterBinaryMessenger, localDeviceId: UUID) {
        self.localDeviceId = localDeviceId
        self.identity = KarlshareIdentity(deviceId: localDeviceId)
        self.methodChannel = FlutterMethodChannel(
            name: TransferEngine.methodChannelName, binaryMessenger: messenger)
        self.eventChannel = FlutterEventChannel(
            name: TransferEngine.eventChannelName, binaryMessenger: messenger)

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.saveDir = docs.appendingPathComponent("Karlshare", isDirectory: true)

        super.init()
        try? FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)
        eventChannel.setStreamHandler(self)
        methodChannel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result)
        }
    }

    func dispose() {
        stopServer()
        methodChannel.setMethodCallHandler(nil)
        eventChannel.setStreamHandler(nil)
        eventSink = nil
    }

    // MARK: - FlutterStreamHandler

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }

    // MARK: - MethodChannel

    private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        switch call.method {
        case "startServer":
            startServer(); result(nil)
        case "stopServer":
            stopServer(); result(nil)
        case "setSaveDir":
            if let path = (call.arguments as? [String: Any])?["path"] as? String, !path.isEmpty {
                saveDir = URL(fileURLWithPath: path)
                try? FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)
            }
            result(nil)
        case "sendFiles":
            handleSendFiles(call, result)
        case "cancel":
            if let id = (call.arguments as? [String: Any])?["transferId"] as? String {
                markCancelled(id)
            }
            result(nil)
        case "forgetPeer":
            if let idStr = (call.arguments as? [String: Any])?["deviceId"] as? String,
               let id = UUID(uuidString: idStr) {
                trustStore.forget(deviceId: id)
            }
            result(nil)
        case "forgetAllPeers":
            trustStore.forgetAll()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func handleSendFiles(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let peerIp = args["peerIp"] as? String, !peerIp.isEmpty,
              let rawFiles = args["files"] as? [[String: Any]], !rawFiles.isEmpty else {
            result(FlutterError(code: "ARG", message: "peerIp + files required", details: nil))
            return
        }
        let transferId = UUID().uuidString
        // mc:-addressed peers transfer over MultipeerConnectivity, not TCP/TLS.
        if peerIp.hasPrefix("mc:") {
            emit("started", ["transferId": transferId, "fileCount": rawFiles.count, "direction": "sent"])
            onMultipeerSend?(peerIp, rawFiles, transferId)
            result(transferId)
            return
        }
        let files: [PendingFile] = rawFiles.compactMap { f in
            guard let path = f["path"] as? String else { return nil }
            let url = URL(fileURLWithPath: path)
            let name = (f["name"] as? String) ?? url.lastPathComponent
            let mime = (f["mime"] as? String) ?? "application/octet-stream"
            let size = (f["size"] as? NSNumber)?.uint64Value
                ?? (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? UInt64) ?? 0
            return PendingFile(url: url, name: name, mime: mime, size: size)
        }
        let grandTotal = files.reduce(UInt64(0)) { $0 + $1.size }

        Task {
            emit("started", [
                "transferId": transferId,
                "fileCount": files.count,
                "totalBytes": Int(grandTotal),
                "direction": "sent",
            ])
            do {
                try await sendWithRetry(peerIp: peerIp, files: files, transferId: transferId, grandTotal: grandTotal)
                if isCancelled(transferId) {
                    emit("cancelled", ["transferId": transferId])
                } else {
                    emit("transferComplete", ["transferId": transferId])
                }
            } catch {
                emit("error", ["transferId": transferId, "message": message(for: error)])
            }
            clearCancelled(transferId)
        }
        result(transferId)
    }

    // MARK: - Sender

    /// Three attempts with 1s/2s/4s backoff on transient I/O errors. Security
    /// errors (fingerprint mismatch / pin change) are never retried.
    private func sendWithRetry(peerIp: String, files: [PendingFile],
                               transferId: String, grandTotal: UInt64) async throws {
        var attempt = 0
        var lastError: Error?
        while attempt < 3 && !isCancelled(transferId) {
            do {
                try await sendOverSocket(peerIp: peerIp, files: files,
                                         transferId: transferId, grandTotal: grandTotal)
                return
            } catch let e as EngineError {
                throw e // security failure — stop, surface to user
            } catch {
                lastError = error
                attempt += 1
                if attempt >= 3 || isCancelled(transferId) { break }
                let backoffMs = 1000 << (attempt - 1) // 1s, 2s, 4s
                emit("retry", [
                    "transferId": transferId, "attempt": attempt,
                    "backoffMs": backoffMs, "message": message(for: error),
                ])
                try? await Task.sleep(nanoseconds: UInt64(backoffMs) * 1_000_000)
            }
        }
        throw lastError ?? KarlshareProtocol.ProtocolError.eof
    }

    private func sendOverSocket(peerIp: String, files: [PendingFile],
                                transferId: String, grandTotal: UInt64) async throws {
        let host = NWEndpoint.Host(peerIp)
        let port = NWEndpoint.Port(rawValue: KarlshareProtocol.transferPort)!
        let conn = TLSConnection(connection: NWConnection(
            host: host, port: port, using: KarlshareTLS.parameters(identity: identity)))
        defer { conn.cancel() }
        try await conn.start()

        try await conn.send(KarlshareProtocol.encodeHandshake(localHandshake()))
        let remote = try await KarlshareProtocol.decodeHandshake { try await conn.readExactly($0) }
        try verifyPeer(conn, remote)

        var sentTotal: UInt64 = 0
        for file in files {
            if isCancelled(transferId) { break }
            sentTotal = try await sendFile(file, over: conn, transferId: transferId,
                                           sentTotal: sentTotal, grandTotal: grandTotal)
        }
    }

    private func sendFile(_ file: PendingFile, over conn: TLSConnection,
                          transferId: String, sentTotal: UInt64,
                          grandTotal: UInt64) async throws -> UInt64 {
        let checksum = try sha256(of: file.url)
        let fileId = UUID()
        let header = KarlshareProtocol.FileHeader(
            fileId: fileId, name: file.name, size: file.size,
            mime: file.mime, checksum: checksum)
        try await conn.send(KarlshareProtocol.encodeFileHeader(header))
        emit("header", [
            "transferId": transferId, "fileId": fileId.uuidString,
            "name": file.name, "size": Int(file.size), "mime": file.mime,
        ])

        var runningTotal = sentTotal
        let handle = try FileHandle(forReadingFrom: file.url)
        defer { try? handle.close() }
        var index: UInt32 = 0
        var fileSent: UInt64 = 0
        while !isCancelled(transferId) {
            let data = try handle.read(upToCount: KarlshareProtocol.defaultChunkSize) ?? Data()
            if data.isEmpty { break }
            try await conn.send(KarlshareProtocol.encodeChunk(
                .init(fileId: fileId, index: index, data: data)))
            index += 1
            fileSent += UInt64(data.count)
            runningTotal += UInt64(data.count)
            emit("progress", [
                "transferId": transferId, "fileId": fileId.uuidString,
                "fileBytes": Int(fileSent), "fileTotal": Int(file.size),
                "totalBytes": Int(runningTotal), "grandTotal": Int(grandTotal),
            ])
        }
        return runningTotal
    }

    // MARK: - Receiver (server)

    private func startServer() {
        guard listener == nil else { return }
        do {
            let l = try NWListener(using: KarlshareTLS.parameters(identity: identity),
                                   on: NWEndpoint.Port(rawValue: KarlshareProtocol.transferPort)!)
            // Advertise over Bonjour so peers' browsers (BonjourManager) find us
            // while we're in receive mode. One listener both advertises and
            // accepts the incoming TLS connection.
            l.service = NWListener.Service(name: nil, type: "_karlshare._tcp")
            l.newConnectionHandler = { [weak self] conn in
                guard let self else { return }
                Task { await self.handleIncoming(conn) }
            }
            l.start(queue: netQueue)
            listener = l
        } catch {
            emit("error", ["message": "server failed: \(message(for: error))"])
        }
    }

    private func stopServer() {
        listener?.cancel()
        listener = nil
    }

    private func handleIncoming(_ nwConn: NWConnection) async {
        let transferId = UUID().uuidString
        let conn = TLSConnection(connection: nwConn)
        defer { conn.cancel() }
        do {
            try await conn.start()
            let remote = try await KarlshareProtocol.decodeHandshake { try await conn.readExactly($0) }
            try await conn.send(KarlshareProtocol.encodeHandshake(localHandshake()))
            try verifyPeer(conn, remote)
            try await receiveFiles(conn, transferId: transferId)
            if isCancelled(transferId) {
                emit("cancelled", ["transferId": transferId])
            } else {
                emit("transferComplete", ["transferId": transferId])
            }
        } catch {
            emit("error", ["transferId": transferId, "message": message(for: error)])
        }
        clearCancelled(transferId)
    }

    private func receiveFiles(_ conn: TLSConnection, transferId: String) async throws {
        var open: [UUID: ReceivingFile] = [:]
        var grandTotal: UInt64 = 0
        var receivedTotal: UInt64 = 0

        while !isCancelled(transferId) {
            guard let frame = try await KarlshareProtocol.decodeFrame({ try await conn.readExactly($0) })
            else { break }

            switch frame {
            case .header(let h):
                let target = uniqueURL(for: h.name)
                FileManager.default.createFile(atPath: target.path, contents: nil)
                let handle = try FileHandle(forWritingTo: target)
                let recv = ReceivingFile(header: h, url: target, handle: handle)
                open[h.fileId] = recv
                grandTotal += h.size
                emit("header", [
                    "transferId": transferId, "fileId": h.fileId.uuidString,
                    "name": h.name, "size": Int(h.size), "mime": h.mime,
                    "savePath": target.path,
                ])
                if h.size == 0 {
                    open.removeValue(forKey: h.fileId)
                    finishFile(recv, transferId: transferId)
                }

            case .chunk(let c):
                guard let recv = open[c.fileId] else { continue }
                // In-order single stream → running count is the write offset.
                try recv.handle.seek(toOffset: recv.received)
                recv.handle.write(c.data)
                recv.received += UInt64(c.data.count)
                receivedTotal += UInt64(c.data.count)
                emit("progress", [
                    "transferId": transferId, "fileId": recv.header.fileId.uuidString,
                    "fileBytes": Int(recv.received), "fileTotal": Int(recv.header.size),
                    "totalBytes": Int(receivedTotal), "grandTotal": Int(grandTotal),
                ])
                if recv.received >= recv.header.size {
                    open.removeValue(forKey: c.fileId)
                    finishFile(recv, transferId: transferId)
                }

            case .ack:
                break // sender never sends acks; ignore defensively
            case .cancel:
                markCancelled(transferId)
            }
        }
        for recv in open.values { try? recv.handle.close() }
    }

    private func finishFile(_ recv: ReceivingFile, transferId: String) {
        try? recv.handle.close()
        let ok = (try? sha256(of: recv.url)) == recv.header.checksum
        if ok {
            emit("fileComplete", [
                "transferId": transferId,
                "fileId": recv.header.fileId.uuidString,
                "savePath": recv.url.path,
            ])
        } else {
            emit("error", [
                "transferId": transferId,
                "fileId": recv.header.fileId.uuidString,
                "message": "checksum mismatch",
            ])
        }
    }

    // MARK: - Handshake / verification

    private func localHandshake() -> KarlshareProtocol.Handshake {
        KarlshareProtocol.Handshake(
            version: KarlshareProtocol.version,
            deviceId: localDeviceId,
            publicKey: identity.publicKeyFingerprint,
            capabilities: KarlshareProtocol.Capabilities.supportsParallelChunks
                | KarlshareProtocol.Capabilities.supportsTLS)
    }

    private func verifyPeer(_ conn: TLSConnection, _ remote: KarlshareProtocol.Handshake) throws {
        guard let actual = conn.peerFingerprint() else {
            throw EngineError.security("peer presented no certificate")
        }
        guard actual == remote.publicKey else {
            throw EngineError.security("peer cert fingerprint does not match handshake (MITM?)")
        }
        switch trustStore.verify(deviceId: remote.deviceId, fingerprint: actual) {
        case .known:
            break
        case .firstSeen:
            trustStore.pin(deviceId: remote.deviceId, fingerprint: actual)
        case .mismatch(let expected, _):
            throw EngineError.security("pinned fingerprint changed for \(remote.deviceId) (was \(expected))")
        }
    }

    // MARK: - Helpers

    private func sha256(of url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 64 * 1024) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return Data(hasher.finalize())
    }

    private func uniqueURL(for name: String) -> URL {
        let base = saveDir.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: base.path) { return base }
        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        var i = 1
        while true {
            let candidate = ext.isEmpty
                ? saveDir.appendingPathComponent("\(stem) (\(i))")
                : saveDir.appendingPathComponent("\(stem) (\(i)).\(ext)")
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            i += 1
        }
    }

    private func message(for error: Error) -> String {
        if let e = error as? EngineError, case let .security(m) = e { return m }
        return (error as NSError).localizedDescription
    }

    private func emit(_ type: String, _ body: [String: Any]) {
        guard let sink = eventSink else { return }
        var payload = body
        payload["type"] = type
        DispatchQueue.main.async { sink(payload) }
    }

    /// Public entry point so the Multipeer path can emit on this same channel.
    func emitTransfer(_ type: String, _ body: [String: Any]) { emit(type, body) }

    // MARK: - Cancellation bookkeeping

    private func markCancelled(_ id: String) { lock.lock(); cancelled.insert(id); lock.unlock() }
    private func clearCancelled(_ id: String) { lock.lock(); cancelled.remove(id); lock.unlock() }
    private func isCancelled(_ id: String) -> Bool { lock.lock(); defer { lock.unlock() }; return cancelled.contains(id) }

    // MARK: - Models

    private struct PendingFile {
        let url: URL
        let name: String
        let mime: String
        let size: UInt64
    }

    private final class ReceivingFile {
        let header: KarlshareProtocol.FileHeader
        let url: URL
        let handle: FileHandle
        var received: UInt64 = 0
        init(header: KarlshareProtocol.FileHeader, url: URL, handle: FileHandle) {
            self.header = header; self.url = url; self.handle = handle
        }
    }
}
