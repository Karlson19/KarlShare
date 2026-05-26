package com.karlshare.karlshare.discovery

import android.content.Context
import android.net.wifi.WifiManager
import android.os.Build
import android.util.Log
import org.json.JSONObject
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.util.UUID
import kotlin.concurrent.thread

/**
 * Reliable peer discovery over the local Wi-Fi network (replaces the flaky
 * WiFi Direct path). Every Karlshare device broadcasts a small UDP beacon
 * { id, name, platform, port } a couple of times a second and listens for
 * others, so phones and PCs on the same network find each other with no
 * pairing. The peer's IP comes straight off the beacon, so the transfer engine
 * can dial it directly with no group-owner negotiation.
 *
 * Android filters incoming broadcast/multicast at the Wi-Fi chip unless a
 * [WifiManager.MulticastLock] is held, so we acquire one while discovering.
 */
class LanDiscovery(
    private val context: Context,
    private val deviceId: UUID,
    private val listener: Listener,
) {
    interface Listener {
        fun onPeerFound(address: String, name: String, platform: String)
        fun onPeerLost(address: String)
        fun onError(stage: String, reason: Int)
    }

    companion object {
        private const val TAG = "LanDiscovery"
        const val BEACON_PORT = 8987
        const val TRANSFER_PORT = 8988
        private const val ANNOUNCE_MS = 2000L
        private const val TIMEOUT_MS = 6000L
    }

    @Volatile private var running = false
    private var socket: DatagramSocket? = null
    private var multicastLock: WifiManager.MulticastLock? = null

    // ip -> last time we heard a beacon from it (guarded by `lock`)
    private val seen = HashMap<String, Long>()
    private val lock = Any()

    private val deviceName: String = Build.MODEL ?: "Android device"

    fun start() {
        if (running) return
        running = true
        try {
            val wifi = context.applicationContext
                .getSystemService(Context.WIFI_SERVICE) as WifiManager
            multicastLock = wifi.createMulticastLock("karlshare-lan").apply {
                setReferenceCounted(true)
                acquire()
            }

            val sock = DatagramSocket(null).apply {
                reuseAddress = true
                broadcast = true
                soTimeout = 0
                bind(InetSocketAddress(BEACON_PORT))
            }
            socket = sock

            thread(name = "karlshare-lan-rx", isDaemon = true) { receiveLoop(sock) }
            thread(name = "karlshare-lan-tx", isDaemon = true) { announceLoop(sock) }
            thread(name = "karlshare-lan-reap", isDaemon = true) { reapLoop() }
            Log.i(TAG, "LAN discovery up on :$BEACON_PORT")
        } catch (t: Throwable) {
            Log.w(TAG, "start failed", t)
            listener.onError("lanStart", -1)
            stop()
        }
    }

    fun stop() {
        running = false
        runCatching { socket?.close() }
        socket = null
        runCatching { if (multicastLock?.isHeld == true) multicastLock?.release() }
        multicastLock = null
        synchronized(lock) { seen.clear() }
    }

    // ---- loops --------------------------------------------------------------

    private fun announceLoop(sock: DatagramSocket) {
        val payload = JSONObject(
            mapOf(
                "v" to 1,
                "id" to deviceId.toString(),
                "name" to deviceName,
                "platform" to "android",
                "port" to TRANSFER_PORT,
            ),
        ).toString().toByteArray(Charsets.UTF_8)
        val broadcast = InetAddress.getByName("255.255.255.255")
        while (running) {
            runCatching {
                sock.send(DatagramPacket(payload, payload.size, broadcast, BEACON_PORT))
            }
            try {
                Thread.sleep(ANNOUNCE_MS)
            } catch (_: InterruptedException) {
                break
            }
        }
    }

    private fun receiveLoop(sock: DatagramSocket) {
        val buf = ByteArray(2048)
        while (running) {
            try {
                val packet = DatagramPacket(buf, buf.size)
                sock.receive(packet)
                val json = JSONObject(String(packet.data, 0, packet.length, Charsets.UTF_8))
                val id = json.optString("id")
                if (id.isEmpty() || id == deviceId.toString()) continue
                val ip = packet.address.hostAddress ?: continue
                val name = json.optString("name", "Device")
                val platform = json.optString("platform", "unknown")

                val isNew: Boolean
                synchronized(lock) {
                    isNew = !seen.containsKey(ip)
                    seen[ip] = System.currentTimeMillis()
                }
                if (isNew) listener.onPeerFound(ip, name, platform)
            } catch (_: Throwable) {
                if (!running) break
                // Malformed packet or transient read error; keep listening.
            }
        }
    }

    private fun reapLoop() {
        while (running) {
            try {
                Thread.sleep(ANNOUNCE_MS)
            } catch (_: InterruptedException) {
                break
            }
            val now = System.currentTimeMillis()
            val gone = ArrayList<String>()
            synchronized(lock) {
                val it = seen.entries.iterator()
                while (it.hasNext()) {
                    val e = it.next()
                    if (now - e.value > TIMEOUT_MS) {
                        gone.add(e.key)
                        it.remove()
                    }
                }
            }
            for (ip in gone) listener.onPeerLost(ip)
        }
    }
}
