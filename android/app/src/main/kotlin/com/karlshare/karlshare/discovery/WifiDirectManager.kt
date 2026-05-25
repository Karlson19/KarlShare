package com.karlshare.karlshare.discovery

import android.Manifest
import android.annotation.SuppressLint
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.wifi.p2p.WifiP2pConfig
import android.net.wifi.p2p.WifiP2pDevice
import android.net.wifi.p2p.WifiP2pManager
import android.net.wifi.p2p.nsd.WifiP2pDnsSdServiceInfo
import android.net.wifi.p2p.nsd.WifiP2pDnsSdServiceRequest
import android.os.Build
import android.os.Looper
import android.util.Log
import androidx.core.content.ContextCompat

/**
 * Wraps Android's WifiP2pManager for Karlshare's Android↔Android discovery
 * path (spec Section 7.3). Advertises a `_karlshare._tcp` service via
 * Bonjour-over-WiFi-Direct so peers can find each other without manual
 * pairing, and exposes a {@link Listener} callback surface used by
 * {@link DiscoveryService}.
 *
 * Group creation/join is also handled here so the same instance can drive
 * both the sender (joins group) and receiver (group owner) flows.
 */
class WifiDirectManager(
    private val context: Context,
    private val listener: Listener,
) {
    companion object {
        private const val TAG = "WifiDirectManager"
        private const val SERVICE_INSTANCE = "Karlshare"
        private const val SERVICE_TYPE = "_karlshare._tcp"
    }

    interface Listener {
        fun onPeerFound(device: PeerDevice)
        fun onPeerLost(deviceAddress: String)
        fun onGroupReady(ownerIp: String, isGroupOwner: Boolean)
        fun onError(stage: String, reason: Int)
    }

    data class PeerDevice(
        val address: String,
        val name: String,
        val signalStrength: Int, // 0–100, derived from device.status + heuristics
        val isAvailable: Boolean,
    )

    private val manager: WifiP2pManager? =
        context.getSystemService(Context.WIFI_P2P_SERVICE) as? WifiP2pManager
    private var channel: WifiP2pManager.Channel? = null
    private var receiver: BroadcastReceiver? = null
    private val peers = mutableMapOf<String, PeerDevice>()
    private var serviceRequest: WifiP2pDnsSdServiceRequest? = null
    private var discovering: Boolean = false

    /** True when WiFi Direct is supported on this device. */
    val isSupported: Boolean = manager != null

    fun start() {
        val mgr = manager ?: run {
            listener.onError("init", -1)
            return
        }
        channel = mgr.initialize(context, Looper.getMainLooper(), null)
        registerReceiver()
    }

    fun stop() {
        stopDiscovery()
        receiver?.let {
            runCatching { context.unregisterReceiver(it) }
            receiver = null
        }
        channel?.let {
            // Channel.close is API 27+ and rarely needed; rely on GC otherwise.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) it.close()
        }
        channel = null
        peers.clear()
    }

    /** Advertise this device + start scanning for peers running Karlshare. */
    fun startDiscovery() {
        val mgr = manager ?: return
        val ch = channel ?: return
        if (discovering) return
        if (!hasRequiredPermissions()) {
            listener.onError("permission", -1)
            return
        }
        discovering = true
        advertiseService(mgr, ch)
        scanForServices(mgr, ch)
    }

    fun stopDiscovery() {
        val mgr = manager ?: return
        val ch = channel ?: return
        discovering = false
        runCatching {
            @SuppressLint("MissingPermission")
            mgr.stopPeerDiscovery(ch, noopActionListener("stopPeerDiscovery"))
            mgr.clearLocalServices(ch, noopActionListener("clearLocalServices"))
            mgr.clearServiceRequests(ch, noopActionListener("clearServiceRequests"))
        }
        serviceRequest = null
    }

    /** Receiver flow: create a group, become Group Owner. */
    fun createGroup() {
        val mgr = manager ?: return
        val ch = channel ?: return
        if (!hasRequiredPermissions()) {
            listener.onError("permission", -1)
            return
        }
        @SuppressLint("MissingPermission")
        mgr.createGroup(ch, object : WifiP2pManager.ActionListener {
            override fun onSuccess() { Log.d(TAG, "group created") }
            override fun onFailure(reason: Int) = listener.onError("createGroup", reason)
        })
    }

    /** Sender flow: connect to a peer that's acting as Group Owner. */
    fun connectTo(deviceAddress: String) {
        val mgr = manager ?: return
        val ch = channel ?: return
        if (!hasRequiredPermissions()) {
            listener.onError("permission", -1)
            return
        }
        val config = WifiP2pConfig().apply { this.deviceAddress = deviceAddress }
        @SuppressLint("MissingPermission")
        mgr.connect(ch, config, object : WifiP2pManager.ActionListener {
            override fun onSuccess() { Log.d(TAG, "connect requested") }
            override fun onFailure(reason: Int) = listener.onError("connect", reason)
        })
    }

    fun disconnect() {
        val mgr = manager ?: return
        val ch = channel ?: return
        mgr.removeGroup(ch, noopActionListener("removeGroup"))
    }

    // ---- Internals ---------------------------------------------------------

    @SuppressLint("MissingPermission")
    private fun advertiseService(mgr: WifiP2pManager, ch: WifiP2pManager.Channel) {
        val info = WifiP2pDnsSdServiceInfo.newInstance(
            SERVICE_INSTANCE,
            SERVICE_TYPE,
            mapOf("port" to "8988", "version" to "1"),
        )
        mgr.addLocalService(ch, info, noopActionListener("addLocalService"))
    }

    @SuppressLint("MissingPermission")
    private fun scanForServices(mgr: WifiP2pManager, ch: WifiP2pManager.Channel) {
        mgr.setDnsSdResponseListeners(
            ch,
            { instanceName, registrationType, srcDevice ->
                if (registrationType.startsWith(SERVICE_TYPE)) {
                    upsertPeer(srcDevice, instanceName)
                }
            },
            { _, _, _ -> /* TXT record — port/version live here; unused for now */ },
        )

        serviceRequest = WifiP2pDnsSdServiceRequest.newInstance(
            SERVICE_INSTANCE, SERVICE_TYPE,
        ).also {
            mgr.addServiceRequest(ch, it, noopActionListener("addServiceRequest"))
        }
        mgr.discoverServices(ch, noopActionListener("discoverServices"))
    }

    private fun upsertPeer(device: WifiP2pDevice, instanceName: String) {
        val signal = when (device.status) {
            WifiP2pDevice.AVAILABLE -> 90
            WifiP2pDevice.INVITED -> 70
            WifiP2pDevice.CONNECTED -> 100
            WifiP2pDevice.FAILED, WifiP2pDevice.UNAVAILABLE -> 20
            else -> 50
        }
        val displayName = device.deviceName.ifBlank { instanceName }
        val peer = PeerDevice(
            address = device.deviceAddress,
            name = displayName,
            signalStrength = signal,
            isAvailable = device.status == WifiP2pDevice.AVAILABLE,
        )
        val existing = peers[peer.address]
        if (existing != peer) {
            peers[peer.address] = peer
            listener.onPeerFound(peer)
        }
    }

    private fun registerReceiver() {
        val filter = IntentFilter().apply {
            addAction(WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION)
        }
        receiver = WifiDirectBroadcastReceiver()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(
                receiver,
                filter,
                Context.RECEIVER_NOT_EXPORTED,
            )
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            context.registerReceiver(receiver, filter)
        }
    }

    private fun hasRequiredPermissions(): Boolean {
        val needsNearby = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU
        val perms = buildList {
            if (needsNearby) add(Manifest.permission.NEARBY_WIFI_DEVICES)
            else add(Manifest.permission.ACCESS_FINE_LOCATION)
        }
        return perms.all {
            ContextCompat.checkSelfPermission(context, it) ==
                PackageManager.PERMISSION_GRANTED
        }
    }

    private fun noopActionListener(action: String) = object : WifiP2pManager.ActionListener {
        override fun onSuccess() { Log.d(TAG, "$action ok") }
        override fun onFailure(reason: Int) {
            Log.w(TAG, "$action failed: $reason")
            listener.onError(action, reason)
        }
    }

    private inner class WifiDirectBroadcastReceiver : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val mgr = manager ?: return
            val ch = channel ?: return
            when (intent.action) {
                WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION -> {
                    if (!hasRequiredPermissions()) return
                    @SuppressLint("MissingPermission")
                    mgr.requestPeers(ch) { peerList ->
                        // Drop devices that vanished.
                        val present = peerList.deviceList.map { it.deviceAddress }.toSet()
                        val gone = peers.keys - present
                        gone.forEach {
                            peers.remove(it)
                            listener.onPeerLost(it)
                        }
                    }
                }
                WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION -> {
                    @SuppressLint("MissingPermission")
                    mgr.requestConnectionInfo(ch) { info ->
                        val ip = info?.groupOwnerAddress?.hostAddress
                        if (info?.groupFormed == true && ip != null) {
                            listener.onGroupReady(ip, info.isGroupOwner)
                        }
                    }
                }
            }
        }
    }
}
