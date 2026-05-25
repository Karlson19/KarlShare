import Foundation

/// Karlshare binary wire protocol (spec Section 7.2) — Swift mirror of the
/// Android `KarlshareProtocol.kt`. All multi-byte integers are big-endian
/// (network byte order) so the two platforms interop on the byte level.
///
/// Message types (one-byte tag):
///   0x01 HANDSHAKE   [VERSION:2][DEVICE_ID:16][PUBLIC_KEY:32][CAPABILITIES:1]
///   0x02 FILE_HEADER [FILE_ID:16][NAME_LEN:2][NAME][SIZE:8][MIME_LEN:1][MIME][CHECKSUM:32]
///   0x03 CHUNK       [FILE_ID:16][CHUNK_INDEX:4][CHUNK_SIZE:4][DATA]
///   0x04 ACK         [FILE_ID:16][CHUNK_INDEX:4][STATUS:1]
///   0x05 CANCEL      [FILE_ID:16]
///
/// As on Android, the HANDSHAKE tag is omitted on the wire — both peers know
/// the first frame on a fresh socket is the handshake.
enum KarlshareProtocol {

    static let version: UInt16 = 2
    static let transferPort: UInt16 = 8988
    static let defaultChunkSize: Int = 256 * 1024
    static let parallelChunks: Int = 4

    enum Tag {
        static let handshake: UInt8 = 0x01
        static let fileHeader: UInt8 = 0x02
        static let chunk: UInt8 = 0x03
        static let ack: UInt8 = 0x04
        static let cancel: UInt8 = 0x05
    }

    enum AckStatus {
        static let ok: UInt8 = 0x00
        static let retry: UInt8 = 0x01
        static let fail: UInt8 = 0x02
    }

    /// Capability bits packed into the 1-byte CAPABILITIES field.
    enum Capabilities {
        static let supportsResume = 1 << 0
        static let supportsParallelChunks = 1 << 1
        static let supportsTLS = 1 << 2
    }

    enum ProtocolError: Error {
        case eof
        case malformed(String)
    }

    // MARK: - Models

    struct Handshake {
        let version: UInt16
        let deviceId: UUID
        /// SHA-256 of the peer's TLS cert SubjectPublicKeyInfo (32 bytes).
        let publicKey: Data
        let capabilities: Int
    }

    struct FileHeader {
        let fileId: UUID
        let name: String
        let size: UInt64
        let mime: String
        let checksum: Data // SHA-256, 32 bytes
    }

    struct Chunk {
        let fileId: UUID
        let index: UInt32
        let data: Data
    }

    struct Ack {
        let fileId: UUID
        let index: UInt32
        let status: UInt8
    }

    enum Frame {
        case header(FileHeader)
        case chunk(Chunk)
        case ack(Ack)
        case cancel(UUID)
    }

    /// Reads exactly `n` bytes, or throws `.eof` if the stream closed first.
    typealias Reader = (_ n: Int) async throws -> Data

    // MARK: - Encoding

    static func encodeHandshake(_ h: Handshake) -> Data {
        var out = Data()
        out.appendBE(h.version)
        out.append(uuidBytes(h.deviceId))
        precondition(h.publicKey.count == 32, "publicKey must be 32 bytes")
        out.append(h.publicKey)
        out.append(UInt8(h.capabilities & 0xFF))
        return out
    }

    static func encodeFileHeader(_ h: FileHeader) -> Data {
        var out = Data()
        out.append(Tag.fileHeader)
        out.append(uuidBytes(h.fileId))
        let nameBytes = Data(h.name.utf8)
        precondition(nameBytes.count <= 0xFFFF, "file name too long")
        out.appendBE(UInt16(nameBytes.count))
        out.append(nameBytes)
        out.appendBE(h.size)
        let mimeBytes = Data(h.mime.utf8)
        precondition(mimeBytes.count <= 0xFF, "mime too long")
        out.append(UInt8(mimeBytes.count))
        out.append(mimeBytes)
        precondition(h.checksum.count == 32, "checksum must be 32 bytes")
        out.append(h.checksum)
        return out
    }

    static func encodeChunk(_ c: Chunk) -> Data {
        var out = Data()
        out.append(Tag.chunk)
        out.append(uuidBytes(c.fileId))
        out.appendBE(c.index)
        out.appendBE(UInt32(c.data.count))
        out.append(c.data)
        return out
    }

    static func encodeAck(_ a: Ack) -> Data {
        var out = Data()
        out.append(Tag.ack)
        out.append(uuidBytes(a.fileId))
        out.appendBE(a.index)
        out.append(a.status)
        return out
    }

    static func encodeCancel(_ fileId: UUID) -> Data {
        var out = Data()
        out.append(Tag.cancel)
        out.append(uuidBytes(fileId))
        return out
    }

    // MARK: - Decoding

    static func decodeHandshake(_ read: Reader) async throws -> Handshake {
        let version = try await readBE(UInt16.self, read)
        let deviceId = try await readUUID(read)
        let publicKey = try await read(32)
        let cap = try await read(1)
        return Handshake(
            version: version,
            deviceId: deviceId,
            publicKey: publicKey,
            capabilities: Int(cap[cap.startIndex])
        )
    }

    /// Reads one tag-prefixed frame. Returns nil on a clean EOF.
    static func decodeFrame(_ read: Reader) async throws -> Frame? {
        let tagData: Data
        do {
            tagData = try await read(1)
        } catch ProtocolError.eof {
            return nil
        }
        let tag = tagData[tagData.startIndex]
        switch tag {
        case Tag.fileHeader:
            return .header(try await decodeFileHeaderBody(read))
        case Tag.chunk:
            return .chunk(try await decodeChunkBody(read))
        case Tag.ack:
            return .ack(try await decodeAckBody(read))
        case Tag.cancel:
            return .cancel(try await readUUID(read))
        default:
            throw ProtocolError.malformed(String(format: "unknown frame tag 0x%02x", tag))
        }
    }

    private static func decodeFileHeaderBody(_ read: Reader) async throws -> FileHeader {
        let fileId = try await readUUID(read)
        let nameLen = Int(try await readBE(UInt16.self, read))
        let name = String(decoding: try await read(nameLen), as: UTF8.self)
        let size = try await readBE(UInt64.self, read)
        let mimeLen = Int(try await read(1)[0])
        let mime = String(decoding: try await read(mimeLen), as: UTF8.self)
        let checksum = try await read(32)
        return FileHeader(fileId: fileId, name: name, size: size, mime: mime, checksum: checksum)
    }

    private static func decodeChunkBody(_ read: Reader) async throws -> Chunk {
        let fileId = try await readUUID(read)
        let index = try await readBE(UInt32.self, read)
        let size = Int(try await readBE(UInt32.self, read))
        guard size >= 0, size <= 8 * 1024 * 1024 else {
            throw ProtocolError.malformed("implausible chunk size: \(size)")
        }
        let data = try await read(size)
        return Chunk(fileId: fileId, index: index, data: data)
    }

    private static func decodeAckBody(_ read: Reader) async throws -> Ack {
        let fileId = try await readUUID(read)
        let index = try await readBE(UInt32.self, read)
        let status = try await read(1)[0]
        return Ack(fileId: fileId, index: index, status: status)
    }

    private static func readUUID(_ read: Reader) async throws -> UUID {
        let bytes = try await read(16)
        guard let uuid = uuidFromBytes(bytes) else {
            throw ProtocolError.malformed("bad UUID bytes")
        }
        return uuid
    }

    private static func readBE<T: FixedWidthInteger>(_ type: T.Type, _ read: Reader) async throws -> T {
        let bytes = try await read(MemoryLayout<T>.size)
        var value: T = 0
        for b in bytes { value = (value << 8) | T(b) }
        return value
    }

    // MARK: - UUID <-> bytes (big-endian, matches Java UUID MSB/LSB layout)

    static func uuidBytes(_ uuid: UUID) -> Data {
        var u = uuid.uuid
        return withUnsafeBytes(of: &u) { Data($0) }
    }

    static func uuidFromBytes(_ data: Data) -> UUID? {
        guard data.count == 16 else { return nil }
        let b = [UInt8](data)
        let t: uuid_t = (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                         b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15])
        return UUID(uuid: t)
    }
}

// MARK: - Big-endian append helpers

private extension Data {
    mutating func appendBE<T: FixedWidthInteger>(_ value: T) {
        let big = value.bigEndian
        withUnsafeBytes(of: big) { append(contentsOf: $0) }
    }
}
