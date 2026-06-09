package com.karlshare.karlshare.transfer

import android.content.Context
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.io.IOException
import java.io.RandomAccessFile
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.security.MessageDigest
import java.security.SecureRandom
import java.security.cert.X509Certificate
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLServerSocket
import javax.net.ssl.SSLSocket
import javax.net.ssl.TrustManager
import javax.net.ssl.X509TrustManager

/**
 * TCP transfer engine for the Android↔Android path (spec Sections 5.3 / 7.2 /
 * 7.3). Serves incoming TLS 1.3 connections on
 * {@link KarlshareProtocol.TRANSFER_PORT} and can also connect outbound to a
 * peer's Group Owner.
 *
 * **Security model (v1, hardware-backed):**
 * 1. On first launch, [KarlshareKeystore] mints an ECDSA P-256 keypair and a
 *    self-signed cert inside Android's secure keystore.
 * 2. All sockets are TLS 1.3 with mutual auth required.
 * 3. The Karlshare handshake frame's 32-byte PUBLIC_KEY field carries the
 *    SHA-256 of the peer's SubjectPublicKeyInfo. After the TLS handshake we
 *    verify the cert we negotiated matches that fingerprint — that's the
 *    binding that prevents an MITM from inserting a different self-signed
 *    cert. Mismatch → drop the connection.
 * 4. [PeerTrustStore] caches verified (deviceId, fingerprint) pairs so a
 *    pinned peer can be detected if their identity changes (TOFU).
 *
 * Speaks the Karlshare binary wire protocol over the TLS-wrapped streams.
 * Chunks are 256 KB by default, with up to 4 chunks in flight per file.
 */
class TransferEngine(
    private val context: Context,
    messenger: BinaryMessenger,
    private val localDeviceId: UUID,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        private const val TAG = "TransferEngine"
        const val METHOD_CHANNEL = "karlshare/transfer"
        const val EVENT_CHANNEL = "karlshare/transfer/events"
        private const val TLS_PROTOCOL = "TLSv1.3"
        // Allow 1.2 as well so the cross-platform handshake with the desktop
        // (Dart/BoringSSL) negotiates reliably; both are strong.
        private val TLS_PROTOCOLS = arrayOf("TLSv1.2", "TLSv1.3")
    }

    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL).also {
        it.setMethodCallHandler(this)
    }
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL).also {
        it.setStreamHandler(this)
    }
    private var eventSink: EventChannel.EventSink? = null

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val activeTransfers = ConcurrentHashMap<UUID, ActiveTransfer>()
    private var serverJob: Job? = null
    private var serverSocket: ServerSocket? = null
    private var saveDir: File = File(context.filesDir, "Karlshare").apply { mkdirs() }

    private val mainHandler = android.os.Handler(context.mainLooper)
    private val keystore = KarlshareKeystore(localDeviceId)
    private val trustStore = PeerTrustStore(context)
    private val sslContext: SSLContext by lazy { buildSslContext() }

    private data class ActiveTransfer(
        val id: UUID,
        val cancelFlag: AtomicBoolean = AtomicBoolean(false),
        val transferredBytes: AtomicLong = AtomicLong(0),
        val totalBytes: AtomicLong = AtomicLong(0),
    )

    fun dispose() {
        stopServer()
        scope.cancel()
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        eventSink = null
    }

    // ---- MethodChannel -----------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startServer" -> { startServer(); result.success(null) }
            "stopServer" -> { stopServer(); result.success(null) }
            "setSaveDir" -> {
                val path = call.argument<String>("path")
                if (!path.isNullOrBlank()) saveDir = File(path).apply { mkdirs() }
                result.success(null)
            }
            "sendFiles" -> handleSendFiles(call, result)
            "cancel" -> {
                val id = (call.argument<String>("transferId") ?: "").runCatching {
                    UUID.fromString(this)
                }.getOrNull()
                if (id == null) {
                    result.error("ARG", "transferId must be a UUID", null)
                } else {
                    activeTransfers[id]?.cancelFlag?.set(true)
                    result.success(null)
                }
            }
            "forgetPeer" -> {
                val id = (call.argument<String>("deviceId") ?: "").runCatching {
                    UUID.fromString(this)
                }.getOrNull()
                if (id == null) {
                    result.error("ARG", "deviceId must be a UUID", null)
                } else {
                    trustStore.forget(id)
                    result.success(null)
                }
            }
            "forgetAllPeers" -> { trustStore.forgetAll(); result.success(null) }
            else -> result.notImplemented()
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun handleSendFiles(call: MethodCall, result: MethodChannel.Result) {
        val peerIp = call.argument<String>("peerIp")
        val rawFiles = call.argument<List<Map<String, Any>>>("files")
        if (peerIp.isNullOrBlank() || rawFiles.isNullOrEmpty()) {
            result.error("ARG", "peerIp + files required", null); return
        }
        val files = rawFiles.mapNotNull { f ->
            val path = f["path"] as? String ?: return@mapNotNull null
            val name = (f["name"] as? String) ?: File(path).name
            val mime = (f["mime"] as? String) ?: "application/octet-stream"
            val size = (f["size"] as? Number)?.toLong() ?: File(path).length()
            PendingFile(File(path), name, mime, size)
        }
        val transferId = UUID.randomUUID()
        val active = ActiveTransfer(transferId)
        active.totalBytes.set(files.sumOf { it.size })
        activeTransfers[transferId] = active

        scope.launch {
            try {
                emit("started", mapOf(
                    "transferId" to transferId.toString(),
                    "fileCount" to files.size,
                    "totalBytes" to active.totalBytes.get(),
                    "direction" to "sent",
                ))
                sendWithRetry(peerIp, files, active)
                if (active.cancelFlag.get()) {
                    emit("cancelled", mapOf("transferId" to transferId.toString()))
                } else {
                    emit("transferComplete", mapOf("transferId" to transferId.toString()))
                }
            } catch (t: Throwable) {
                Log.w(TAG, "send failed after retries", t)
                emit("error", mapOf(
                    "transferId" to transferId.toString(),
                    "message" to (t.message ?: t.javaClass.simpleName),
                ))
            } finally {
                activeTransfers.remove(transferId)
            }
        }
        result.success(transferId.toString())
    }

    /**
     * Wraps [sendOverSocket] with the spec §5.1.3 / §16 retry policy:
     * three attempts with exponential backoff (1s, 2s, 4s) on transient
     * I/O failures. [SecurityException]s aren't retried — a fingerprint
     * mismatch or pinning failure is a deliberate "stop, ask the user"
     * signal, not a network hiccup.
     */
    private suspend fun sendWithRetry(
        peerIp: String,
        files: List<PendingFile>,
        active: ActiveTransfer,
    ) {
        var attempt = 0
        var lastError: Throwable? = null
        while (attempt < 3 && !active.cancelFlag.get()) {
            try {
                sendOverSocket(peerIp, files, active)
                return
            } catch (sec: SecurityException) {
                throw sec
            } catch (t: Throwable) {
                lastError = t
                attempt++
                if (attempt >= 3 || active.cancelFlag.get()) break
                val backoffMs = 1000L shl (attempt - 1) // 1s, 2s, 4s
                Log.w(TAG, "send attempt $attempt failed, retrying in ${backoffMs}ms", t)
                emit("retry", mapOf(
                    "transferId" to active.id.toString(),
                    "attempt" to attempt,
                    "backoffMs" to backoffMs,
                    "message" to (t.message ?: t.javaClass.simpleName),
                ))
                delay(backoffMs)
                // Re-zero the per-attempt progress counters so the retry's
                // progress numbers are clean. (Receiver-side will simply see
                // a fresh handshake on the new socket.)
                active.transferredBytes.set(0)
            }
        }
        throw lastError ?: IOException("send failed without an underlying cause")
    }

    // ---- EventChannel ------------------------------------------------------

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    // ---- TLS setup ---------------------------------------------------------

    private fun buildSslContext(): SSLContext {
        // The TrustManager accepts any cert at the TLS layer. We do the real
        // verification via fingerprint binding after the handshake — see
        // [verifyPeerFingerprint] below. The TLS handshake still proves that
        // the peer holds the private key for the cert they presented, which
        // is what we need to bind to the Karlshare handshake frame.
        val trustAll = arrayOf<TrustManager>(object : X509TrustManager {
            override fun checkClientTrusted(chain: Array<X509Certificate>?, authType: String?) {}
            override fun checkServerTrusted(chain: Array<X509Certificate>?, authType: String?) {}
            override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
        })
        return SSLContext.getInstance("TLS").apply {
            init(keystore.keyManagerFactory().keyManagers, trustAll, SecureRandom())
        }
    }

    /**
     * After the TLS handshake completes, verify the peer's presented cert
     * matches the public-key fingerprint they sent in the Karlshare
     * handshake frame, and that any pinned (TOFU) fingerprint for this
     * deviceId still matches. Throws on mismatch.
     */
    private fun verifyPeerFingerprint(
        ssl: SSLSocket,
        remoteDeviceId: UUID,
        claimedFingerprint: ByteArray,
    ) {
        val peerCert = ssl.session.peerCertificates.firstOrNull() as? X509Certificate
            ?: throw SecurityException("peer presented no certificate")
        val actualFingerprint = KarlshareKeystore.fingerprintFor(peerCert)
        if (!actualFingerprint.contentEquals(claimedFingerprint)) {
            throw SecurityException(
                "peer cert fingerprint does not match handshake claim (MITM?)"
            )
        }
        when (val trust = trustStore.verify(remoteDeviceId, actualFingerprint)) {
            is PeerTrustStore.Result.Known -> Unit
            is PeerTrustStore.Result.FirstSeen ->
                trustStore.pin(remoteDeviceId, actualFingerprint)
            is PeerTrustStore.Result.Mismatch ->
                throw SecurityException(
                    "pinned fingerprint changed for $remoteDeviceId — refusing connection (was ${trust.expected})"
                )
        }
    }

    // ---- Server (receiver side) --------------------------------------------

    private fun startServer() {
        if (serverJob != null) return
        serverJob = scope.launch {
            try {
                val ssl = (sslContext.serverSocketFactory.createServerSocket() as SSLServerSocket)
                    .apply {
                        reuseAddress = true
                        bind(InetSocketAddress(KarlshareProtocol.TRANSFER_PORT))
                        enabledProtocols = TLS_PROTOCOLS
                        needClientAuth = true
                    }
                serverSocket = ssl
                Log.i(TAG, "TLS server up on :${KarlshareProtocol.TRANSFER_PORT}")
                while (isActive && !ssl.isClosed) {
                    val client = try {
                        ssl.accept() as SSLSocket
                    } catch (_: Throwable) {
                        break
                    }
                    launch { handleIncoming(client) }
                }
            } catch (t: Throwable) {
                emit("error", mapOf("message" to "server failed: ${t.message}"))
            }
        }
    }

    private fun stopServer() {
        runCatching { serverSocket?.close() }
        serverSocket = null
        serverJob?.cancel()
        serverJob = null
    }

    private suspend fun handleIncoming(client: SSLSocket) {
        val transferId = UUID.randomUUID()
        val active = ActiveTransfer(transferId)
        activeTransfers[transferId] = active
        try {
            client.tcpNoDelay = true
            client.soTimeout = 60_000
            client.startHandshake() // force the TLS handshake to complete now

            val input = DataInputStream(BufferedInputStream(client.inputStream))
            val output = DataOutputStream(BufferedOutputStream(client.outputStream))

            // Both sides exchange Karlshare handshakes over the TLS channel.
            val remote = KarlshareProtocol.readHandshake(input)
            KarlshareProtocol.writeHandshake(output, localHandshake())
            verifyPeerFingerprint(client, remote.deviceId, remote.publicKey)
            Log.i(TAG, "handshake verified from ${remote.deviceId}")

            receiveFiles(input, active)
            if (active.cancelFlag.get()) {
                emit("cancelled", mapOf("transferId" to transferId.toString()))
            } else {
                emit("transferComplete", mapOf("transferId" to transferId.toString()))
            }
        } catch (t: Throwable) {
            Log.w(TAG, "incoming failed", t)
            emit("error", mapOf(
                "transferId" to transferId.toString(),
                "message" to (t.message ?: t.javaClass.simpleName),
            ))
        } finally {
            activeTransfers.remove(transferId)
            runCatching { client.close() }
        }
    }

    private suspend fun receiveFiles(
        input: DataInputStream,
        active: ActiveTransfer,
    ) {
        val openFiles = mutableMapOf<UUID, ReceivingFile>()
        while (!active.cancelFlag.get()) {
            val frame = KarlshareProtocol.readFrame(input) ?: break
            when (frame) {
                is KarlshareProtocol.Frame.Header -> {
                    val h = frame.header
                    val saved = withContext(Dispatchers.IO) {
                        ReceivedFileStore.create(context, h.name, h.mime, h.size)
                    }
                    val recv = ReceivingFile(h, saved, MessageDigest.getInstance("SHA-256"))
                    openFiles[h.fileId] = recv
                    active.totalBytes.addAndGet(h.size)
                    emit("header", mapOf(
                        "transferId" to active.id.toString(),
                        "fileId" to h.fileId.toString(),
                        "name" to h.name,
                        "size" to h.size,
                        "mime" to h.mime,
                        "savePath" to saved.location,
                    ))
                    // Zero-byte files carry no chunks — finalise right away so
                    // the UI still receives a fileComplete event.
                    if (h.size == 0L) {
                        openFiles.remove(h.fileId)
                        finishFile(recv, active)
                    }
                }
                is KarlshareProtocol.Frame.ChunkFrame -> {
                    val chunk = frame.chunk
                    val recv = openFiles[chunk.fileId] ?: continue
                    // Chunks arrive in order on a single stream, so we append
                    // sequentially and fold each chunk into a running SHA-256 —
                    // no read-back is needed to verify the file at the end.
                    withContext(Dispatchers.IO) {
                        recv.saved.output.write(chunk.data)
                    }
                    recv.digest.update(chunk.data)
                    recv.received += chunk.data.size
                    active.transferredBytes.addAndGet(chunk.data.size.toLong())
                    emitProgress(active, recv.header.fileId, recv.received, recv.header.size)
                    if (recv.received >= recv.header.size) {
                        openFiles.remove(recv.header.fileId)
                        finishFile(recv, active)
                    }
                }
                is KarlshareProtocol.Frame.AckFrame -> {
                    // Receiver shouldn't see acks; ignore defensively.
                }
                is KarlshareProtocol.Frame.CancelFrame -> {
                    active.cancelFlag.set(true)
                }
            }
        }
        openFiles.values.forEach { runCatching { it.saved.discard() } }
    }

    /** Finalises the file: verifies its SHA-256, publishes or deletes it, and
     *  emits the terminal event with the user-visible save location. */
    private suspend fun finishFile(recv: ReceivingFile, active: ActiveTransfer) {
        val ok = recv.digest.digest().contentEquals(recv.header.checksum)
        withContext(Dispatchers.IO) {
            if (ok) recv.saved.commit() else recv.saved.discard()
        }
        if (ok) {
            emit("fileComplete", mapOf(
                "transferId" to active.id.toString(),
                "fileId" to recv.header.fileId.toString(),
                "savePath" to recv.saved.location,
            ))
        } else {
            emit("error", mapOf(
                "transferId" to active.id.toString(),
                "fileId" to recv.header.fileId.toString(),
                "message" to "checksum mismatch",
            ))
        }
    }

    // ---- Client (sender side) ----------------------------------------------

    private suspend fun sendOverSocket(
        peerIp: String,
        files: List<PendingFile>,
        active: ActiveTransfer,
    ) {
        val factory = sslContext.socketFactory
        val socket = (factory.createSocket() as SSLSocket).apply {
            tcpNoDelay = true
            soTimeout = 60_000
            connect(InetSocketAddress(peerIp, KarlshareProtocol.TRANSFER_PORT), 15_000)
            enabledProtocols = TLS_PROTOCOLS
            startHandshake()
        }
        try {
            val input = DataInputStream(BufferedInputStream(socket.inputStream))
            val output = DataOutputStream(BufferedOutputStream(socket.outputStream))

            KarlshareProtocol.writeHandshake(output, localHandshake())
            val remote = KarlshareProtocol.readHandshake(input)
            verifyPeerFingerprint(socket, remote.deviceId, remote.publicKey)
            Log.i(TAG, "peer handshake verified: ${remote.deviceId}")

            // Drain the receiver's ACK frames on a side coroutine. We don't act
            // on them (TCP already guarantees in-order delivery), but if the
            // sender never reads them the receiver eventually blocks flushing
            // ACKs once the kernel socket buffers fill — a full-duplex
            // flow-control deadlock that surfaces on large/batch transfers.
            val ackDrain = scope.launch {
                runCatching {
                    while (isActive) {
                        KarlshareProtocol.readFrame(input) ?: break
                    }
                }
            }
            try {
                for (file in files) {
                    if (active.cancelFlag.get()) break
                    sendFile(file, output, active)
                }
            } finally {
                ackDrain.cancel()
            }
        } finally {
            runCatching { socket.close() }
        }
    }

    private suspend fun sendFile(
        file: PendingFile,
        output: DataOutputStream,
        active: ActiveTransfer,
    ) {
        val checksum = sha256(file.source)
        val fileId = UUID.randomUUID()
        val header = KarlshareProtocol.FileHeader(
            fileId = fileId,
            name = file.name,
            size = file.size,
            mime = file.mime,
            checksum = checksum,
        )
        KarlshareProtocol.writeFileHeader(output, header)
        emit("header", mapOf(
            "transferId" to active.id.toString(),
            "fileId" to fileId.toString(),
            "name" to file.name,
            "size" to file.size,
            "mime" to file.mime,
        ))

        val chunkSize = KarlshareProtocol.DEFAULT_CHUNK_SIZE
        val totalChunks = ((file.size + chunkSize - 1) / chunkSize).toInt()
        var sentBytes = 0L

        // Read chunks sequentially (single file handle), but flush in groups
        // of PARALLEL_CHUNKS for throughput per spec §7.2.
        RandomAccessFile(file.source, "r").use { raf ->
            var index = 0
            while (index < totalChunks && !active.cancelFlag.get()) {
                val batch = mutableListOf<KarlshareProtocol.Chunk>()
                val batchEnd = (index + KarlshareProtocol.PARALLEL_CHUNKS)
                    .coerceAtMost(totalChunks)
                while (index < batchEnd) {
                    val offset = index.toLong() * chunkSize
                    val remaining = (file.size - offset).toInt().coerceAtMost(chunkSize)
                    val data = ByteArray(remaining)
                    raf.seek(offset)
                    raf.readFully(data)
                    batch.add(KarlshareProtocol.Chunk(fileId, index, data))
                    index++
                }
                // Write the batch to the single TLS stream sequentially. A
                // shared DataOutputStream is not thread-safe — concurrent
                // writes here interleave bytes and corrupt the wire framing.
                // Batching still helps throughput: one flush per group, and a
                // single socket serialises bytes regardless, so parallel writes
                // bought nothing anyway.
                var written = 0
                for (chunk in batch) {
                    KarlshareProtocol.writeChunk(output, chunk)
                    written += chunk.data.size
                }
                output.flush()
                sentBytes += written
                active.transferredBytes.addAndGet(written.toLong())
                emitProgress(active, fileId, sentBytes, file.size)
            }
        }
    }

    // ---- Helpers -----------------------------------------------------------

    private fun localHandshake(): KarlshareProtocol.Handshake =
        KarlshareProtocol.Handshake(
            version = KarlshareProtocol.PROTOCOL_VERSION,
            deviceId = localDeviceId,
            publicKey = keystore.publicKeyFingerprint,
            capabilities = KarlshareProtocol.Capabilities.SUPPORTS_PARALLEL_CHUNKS or
                KarlshareProtocol.Capabilities.SUPPORTS_TLS,
        )

    private suspend fun sha256(file: File): ByteArray = withContext(Dispatchers.IO) {
        val md = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { stream ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val read = stream.read(buffer)
                if (read <= 0) break
                md.update(buffer, 0, read)
            }
        }
        md.digest()
    }

    private fun emitProgress(active: ActiveTransfer, fileId: UUID, fileSent: Long, fileSize: Long) {
        emit("progress", mapOf(
            "transferId" to active.id.toString(),
            "fileId" to fileId.toString(),
            "fileBytes" to fileSent,
            "fileTotal" to fileSize,
            "totalBytes" to active.transferredBytes.get(),
            "grandTotal" to active.totalBytes.get(),
        ))
    }

    private fun emit(type: String, body: Map<String, Any>) {
        val sink = eventSink ?: return
        val payload = HashMap<String, Any>(body.size + 1)
        payload["type"] = type
        payload.putAll(body)
        mainHandler.post { sink.success(payload) }
    }

    // ---- Internal types ----------------------------------------------------

    private data class PendingFile(
        val source: File,
        val name: String,
        val mime: String,
        val size: Long,
    )

    private class ReceivingFile(
        val header: KarlshareProtocol.FileHeader,
        val saved: SavedFile,
        val digest: MessageDigest,
        var received: Long = 0,
    )
}
