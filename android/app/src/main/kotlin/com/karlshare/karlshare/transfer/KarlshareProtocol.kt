package com.karlshare.karlshare.transfer

import java.io.DataInputStream
import java.io.DataOutputStream
import java.nio.ByteBuffer
import java.nio.charset.StandardCharsets
import java.util.UUID

/**
 * Karlshare binary wire protocol (spec Section 7.2).
 *
 * All multi-byte integers are big-endian (network byte order).
 *
 * Message types (one-byte tag):
 *   0x01 HANDSHAKE      [VERSION:2][DEVICE_ID:16][PUBLIC_KEY:32][CAPABILITIES:1]
 *   0x02 FILE_HEADER    [FILE_ID:16][NAME_LEN:2][NAME:variable]
 *                       [SIZE:8][MIME_LEN:1][MIME:variable][CHECKSUM:32]
 *   0x03 CHUNK          [FILE_ID:16][CHUNK_INDEX:4][CHUNK_SIZE:4][DATA:variable]
 *   0x04 ACK            [FILE_ID:16][CHUNK_INDEX:4][STATUS:1]
 *   0x05 CANCEL         [FILE_ID:16]
 *
 * The HANDSHAKE tag is omitted from the on-wire bytes for the handshake itself
 * — both peers know the first frame on a fresh socket is the handshake.
 */
object KarlshareProtocol {

    /**
     * Bumped to 2 in the TLS rollout. v1 spoke plaintext TCP; v2 mandates
     * TLS 1.3 + cert-fingerprint binding on the handshake's PUBLIC_KEY
     * field. v2 peers will never connect to v1 peers (TLS handshake would
     * fail before the Karlshare handshake), which is the intended behavior.
     */
    const val PROTOCOL_VERSION: Short = 2
    const val TRANSFER_PORT: Int = 8988
    const val DEFAULT_CHUNK_SIZE: Int = 256 * 1024
    const val PARALLEL_CHUNKS: Int = 4

    const val TYPE_HANDSHAKE: Byte = 0x01
    const val TYPE_FILE_HEADER: Byte = 0x02
    const val TYPE_CHUNK: Byte = 0x03
    const val TYPE_ACK: Byte = 0x04
    const val TYPE_CANCEL: Byte = 0x05

    const val ACK_OK: Byte = 0x00
    const val ACK_RETRY: Byte = 0x01
    const val ACK_FAIL: Byte = 0x02

    /** Capability bits packed into the 1-byte CAPABILITIES field. */
    object Capabilities {
        const val SUPPORTS_RESUME: Int = 1 shl 0
        const val SUPPORTS_PARALLEL_CHUNKS: Int = 1 shl 1
        const val SUPPORTS_TLS: Int = 1 shl 2 // on by default since v2
    }

    data class Handshake(
        val version: Short,
        val deviceId: UUID,
        /**
         * Since v2 this is the SHA-256 of the peer's TLS cert
         * SubjectPublicKeyInfo (32 bytes). After the TLS handshake completes
         * we cross-check the negotiated cert against this value — that's the
         * binding that makes our self-signed-cert TOFU model MITM-resistant.
         */
        val publicKey: ByteArray,
        val capabilities: Int,
    ) {
        init {
            require(publicKey.size == 32) { "publicKey must be 32 bytes" }
        }

        override fun equals(other: Any?): Boolean {
            if (this === other) return true
            if (other !is Handshake) return false
            return version == other.version &&
                deviceId == other.deviceId &&
                publicKey.contentEquals(other.publicKey) &&
                capabilities == other.capabilities
        }

        override fun hashCode(): Int {
            var result = version.toInt()
            result = 31 * result + deviceId.hashCode()
            result = 31 * result + publicKey.contentHashCode()
            result = 31 * result + capabilities
            return result
        }
    }

    data class FileHeader(
        val fileId: UUID,
        val name: String,
        val size: Long,
        val mime: String,
        val checksum: ByteArray, // SHA-256
    ) {
        init {
            require(checksum.size == 32) { "checksum must be 32 bytes (SHA-256)" }
            require(name.toByteArray(StandardCharsets.UTF_8).size <= 0xFFFF) {
                "file name too long"
            }
            require(mime.toByteArray(StandardCharsets.UTF_8).size <= 0xFF) {
                "mime type too long"
            }
        }

        override fun equals(other: Any?): Boolean {
            if (this === other) return true
            if (other !is FileHeader) return false
            return fileId == other.fileId &&
                name == other.name &&
                size == other.size &&
                mime == other.mime &&
                checksum.contentEquals(other.checksum)
        }

        override fun hashCode(): Int {
            var result = fileId.hashCode()
            result = 31 * result + name.hashCode()
            result = 31 * result + size.hashCode()
            result = 31 * result + mime.hashCode()
            result = 31 * result + checksum.contentHashCode()
            return result
        }
    }

    data class Chunk(
        val fileId: UUID,
        val index: Int,
        val data: ByteArray,
    ) {
        override fun equals(other: Any?): Boolean {
            if (this === other) return true
            if (other !is Chunk) return false
            return fileId == other.fileId &&
                index == other.index &&
                data.contentEquals(other.data)
        }

        override fun hashCode(): Int {
            var result = fileId.hashCode()
            result = 31 * result + index
            result = 31 * result + data.contentHashCode()
            return result
        }
    }

    data class Ack(val fileId: UUID, val index: Int, val status: Byte)

    /** Tag-prefixed frame parsed off the stream after the handshake. */
    sealed interface Frame {
        data class Header(val header: FileHeader) : Frame
        data class ChunkFrame(val chunk: Chunk) : Frame
        data class AckFrame(val ack: Ack) : Frame
        data class CancelFrame(val fileId: UUID) : Frame
    }

    // ---- Handshake ---------------------------------------------------------

    /** Reads the handshake — first frame on a fresh socket, no type tag. */
    fun readHandshake(input: DataInputStream): Handshake {
        val version = input.readShort()
        val deviceId = readUuid(input)
        val publicKey = ByteArray(32).also { input.readFully(it) }
        val capabilities = input.readUnsignedByte()
        return Handshake(version, deviceId, publicKey, capabilities)
    }

    fun writeHandshake(output: DataOutputStream, handshake: Handshake) {
        output.writeShort(handshake.version.toInt())
        writeUuid(output, handshake.deviceId)
        output.write(handshake.publicKey)
        output.writeByte(handshake.capabilities and 0xFF)
        output.flush()
    }

    // ---- Frames (post-handshake) -------------------------------------------

    /** Reads one tag-prefixed frame. Returns null on EOF. */
    fun readFrame(input: DataInputStream): Frame? {
        val tag = try {
            input.readByte()
        } catch (_: java.io.EOFException) {
            return null
        }
        return when (tag) {
            TYPE_FILE_HEADER -> Frame.Header(readFileHeaderBody(input))
            TYPE_CHUNK -> Frame.ChunkFrame(readChunkBody(input))
            TYPE_ACK -> Frame.AckFrame(readAckBody(input))
            TYPE_CANCEL -> Frame.CancelFrame(readUuid(input))
            else -> throw IllegalStateException("Unknown frame tag 0x${"%02x".format(tag)}")
        }
    }

    fun writeFileHeader(output: DataOutputStream, header: FileHeader) {
        output.writeByte(TYPE_FILE_HEADER.toInt())
        writeUuid(output, header.fileId)
        val nameBytes = header.name.toByteArray(StandardCharsets.UTF_8)
        output.writeShort(nameBytes.size)
        output.write(nameBytes)
        output.writeLong(header.size)
        val mimeBytes = header.mime.toByteArray(StandardCharsets.UTF_8)
        output.writeByte(mimeBytes.size)
        output.write(mimeBytes)
        output.write(header.checksum)
        output.flush()
    }

    fun writeChunk(output: DataOutputStream, chunk: Chunk) {
        output.writeByte(TYPE_CHUNK.toInt())
        writeUuid(output, chunk.fileId)
        output.writeInt(chunk.index)
        output.writeInt(chunk.data.size)
        output.write(chunk.data)
        // Caller flushes after a batch — flush per chunk would kill throughput.
    }

    fun writeAck(output: DataOutputStream, ack: Ack) {
        output.writeByte(TYPE_ACK.toInt())
        writeUuid(output, ack.fileId)
        output.writeInt(ack.index)
        output.writeByte(ack.status.toInt())
        output.flush()
    }

    fun writeCancel(output: DataOutputStream, fileId: UUID) {
        output.writeByte(TYPE_CANCEL.toInt())
        writeUuid(output, fileId)
        output.flush()
    }

    // ---- Internals ---------------------------------------------------------

    private fun readFileHeaderBody(input: DataInputStream): FileHeader {
        val fileId = readUuid(input)
        val nameLen = input.readUnsignedShort()
        val name = ByteArray(nameLen).also { input.readFully(it) }
            .toString(StandardCharsets.UTF_8)
        val size = input.readLong()
        val mimeLen = input.readUnsignedByte()
        val mime = ByteArray(mimeLen).also { input.readFully(it) }
            .toString(StandardCharsets.UTF_8)
        val checksum = ByteArray(32).also { input.readFully(it) }
        return FileHeader(fileId, name, size, mime, checksum)
    }

    private fun readChunkBody(input: DataInputStream): Chunk {
        val fileId = readUuid(input)
        val index = input.readInt()
        val size = input.readInt()
        require(size in 0..(8 * 1024 * 1024)) { "implausible chunk size: $size" }
        val data = ByteArray(size).also { input.readFully(it) }
        return Chunk(fileId, index, data)
    }

    private fun readAckBody(input: DataInputStream): Ack {
        val fileId = readUuid(input)
        val index = input.readInt()
        val status = input.readByte()
        return Ack(fileId, index, status)
    }

    private fun readUuid(input: DataInputStream): UUID {
        val msb = input.readLong()
        val lsb = input.readLong()
        return UUID(msb, lsb)
    }

    private fun writeUuid(output: DataOutputStream, uuid: UUID) {
        output.writeLong(uuid.mostSignificantBits)
        output.writeLong(uuid.leastSignificantBits)
    }

    /** Convenience: pack a 16-byte UUID into a ByteBuffer-shaped ByteArray. */
    fun uuidToBytes(uuid: UUID): ByteArray {
        val buf = ByteBuffer.allocate(16)
        buf.putLong(uuid.mostSignificantBits)
        buf.putLong(uuid.leastSignificantBits)
        return buf.array()
    }
}
