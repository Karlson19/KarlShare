package com.karlshare.karlshare.discovery

import android.content.Context
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSpecifier
import android.os.Build
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.net.Inet4Address

/**
 * Karlshare's offline transport ("the Xender way"): the receiver turns its own
 * phone into a Wi-Fi hotspot, the sender joins that hotspot, and the file moves
 * over that private network with no router and no internet.
 *
 *  - Host: [startHotspot] uses [WifiManager.startLocalOnlyHotspot] and reports
 *    the SSID + passphrase, which the UI turns into a QR code.
 *  - Joiner: [joinHotspot] uses a [WifiNetworkSpecifier] to connect just this
 *    app to that hotspot, then reports the host's gateway IP so the transfer
 *    engine can dial it.
 *
 * Every step emits a status event so failures are visible on screen (we cannot
 * read logcat without a cable). MethodChannel `karlshare/hotspot`,
 * EventChannel `karlshare/hotspot/events`.
 */
class HotspotManager(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        private const val TAG = "HotspotManager"
        const val METHOD_CHANNEL = "karlshare/hotspot"
        const val EVENT_CHANNEL = "karlshare/hotspot/events"
    }

    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL).also {
        it.setMethodCallHandler(this)
    }
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL).also {
        it.setStreamHandler(this)
    }
    private var eventSink: EventChannel.EventSink? = null

    private val wifi = context.applicationContext
        .getSystemService(Context.WIFI_SERVICE) as WifiManager
    private val connectivity = context.applicationContext
        .getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

    private var hotspotReservation: WifiManager.LocalOnlyHotspotReservation? = null
    private var joinCallback: ConnectivityManager.NetworkCallback? = null

    fun dispose() {
        stopHotspot()
        leaveHotspot()
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        eventSink = null
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" ->
                result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            "startHotspot" -> { startHotspot(); result.success(null) }
            "stopHotspot" -> { stopHotspot(); result.success(null) }
            "joinHotspot" -> {
                val ssid = call.argument<String>("ssid")
                val pass = call.argument<String>("password")
                if (ssid.isNullOrEmpty() || pass.isNullOrEmpty()) {
                    result.error("ARG", "ssid + password required", null)
                } else {
                    joinHotspot(ssid, pass)
                    result.success(null)
                }
            }
            "leaveHotspot" -> { leaveHotspot(); result.success(null) }
            else -> result.notImplemented()
        }
    }

    // ---- Host side ----------------------------------------------------------

    private fun startHotspot() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            emit("hotspotError", mapOf("message" to "Hotspot needs Android 8 or newer"))
            return
        }
        if (hotspotReservation != null) {
            emitReady(hotspotReservation!!)
            return
        }
        emit("status", mapOf("message" to "Starting hotspot…"))
        try {
            wifi.startLocalOnlyHotspot(object : WifiManager.LocalOnlyHotspotCallback() {
                override fun onStarted(reservation: WifiManager.LocalOnlyHotspotReservation) {
                    hotspotReservation = reservation
                    emitReady(reservation)
                }

                override fun onFailed(reason: Int) {
                    emit("hotspotError", mapOf(
                        "message" to "Couldn't start hotspot (code $reason). " +
                            "Make sure Location is on and you're not already sharing a hotspot.",
                    ))
                }

                override fun onStopped() {
                    hotspotReservation = null
                    emit("status", mapOf("message" to "Hotspot stopped"))
                }
            }, android.os.Handler(context.mainLooper))
        } catch (t: Throwable) {
            Log.w(TAG, "startLocalOnlyHotspot threw", t)
            emit("hotspotError", mapOf("message" to (t.message ?: "Hotspot failed to start")))
        }
    }

    private fun emitReady(reservation: WifiManager.LocalOnlyHotspotReservation) {
        val ssid: String?
        val pass: String?
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val cfg = reservation.softApConfiguration
            ssid = cfg.ssid
            pass = cfg.passphrase
        } else {
            @Suppress("DEPRECATION")
            val cfg = reservation.wifiConfiguration
            ssid = cfg?.SSID
            pass = cfg?.preSharedKey
        }
        if (ssid.isNullOrEmpty() || pass.isNullOrEmpty()) {
            emit("hotspotError", mapOf("message" to "Hotspot started but gave no name/password"))
            return
        }
        emit("hotspotReady", mapOf("ssid" to ssid, "password" to pass))
    }

    private fun stopHotspot() {
        runCatching { hotspotReservation?.close() }
        hotspotReservation = null
    }

    // ---- Joiner side --------------------------------------------------------

    private fun joinHotspot(ssid: String, password: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            emit("joinError", mapOf("message" to "Joining needs Android 10 or newer"))
            return
        }
        emit("status", mapOf("message" to "Joining $ssid…"))
        leaveHotspot()

        val specifier = WifiNetworkSpecifier.Builder()
            .setSsid(ssid)
            .setWpa2Passphrase(password)
            .build()
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .setNetworkSpecifier(specifier)
            .build()

        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                // Route this app's sockets over the hotspot.
                connectivity.bindProcessToNetwork(network)
                val gateway = gatewayOf(network)
                if (gateway != null) {
                    emit("joined", mapOf("gatewayIp" to gateway))
                } else {
                    emit("status", mapOf("message" to "Joined, finding host…"))
                }
            }

            override fun onLinkPropertiesChanged(network: Network, lp: LinkProperties) {
                val gateway = gatewayFrom(lp)
                if (gateway != null) {
                    connectivity.bindProcessToNetwork(network)
                    emit("joined", mapOf("gatewayIp" to gateway))
                }
            }

            override fun onUnavailable() {
                emit("joinError", mapOf("message" to "Couldn't join the hotspot. Re-scan the code and try again."))
            }
        }
        joinCallback = callback
        try {
            connectivity.requestNetwork(request, callback)
        } catch (t: Throwable) {
            emit("joinError", mapOf("message" to (t.message ?: "Join failed")))
        }
    }

    private fun leaveHotspot() {
        joinCallback?.let { runCatching { connectivity.unregisterNetworkCallback(it) } }
        joinCallback = null
        runCatching { connectivity.bindProcessToNetwork(null) }
    }

    /** Host IP = the gateway of the joined hotspot network. */
    private fun gatewayOf(network: Network): String? {
        val lp = connectivity.getLinkProperties(network) ?: return null
        return gatewayFrom(lp)
    }

    private fun gatewayFrom(lp: LinkProperties): String? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            (lp.dhcpServerAddress as? Inet4Address)?.hostAddress?.let { return it }
        }
        for (route in lp.routes) {
            val gw = route.gateway
            if (gw is Inet4Address && !gw.isAnyLocalAddress) {
                return gw.hostAddress
            }
        }
        return null
    }

    private fun emit(type: String, body: Map<String, Any>) {
        val sink = eventSink ?: return
        val payload = HashMap<String, Any>(body.size + 1)
        payload["type"] = type
        payload.putAll(body)
        android.os.Handler(context.mainLooper).post { sink.success(payload) }
    }
}
