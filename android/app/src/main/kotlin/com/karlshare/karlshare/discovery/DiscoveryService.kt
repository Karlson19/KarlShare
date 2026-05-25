package com.karlshare.karlshare.discovery

import android.content.Context
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.BinaryMessenger
import java.util.concurrent.ConcurrentHashMap

/**
 * Flutter platform-channel bridge over {@link WifiDirectManager}.
 *
 * MethodChannel: `karlshare/discovery`
 *   - `isSupported`               → Bool
 *   - `start`                     → void
 *   - `stop`                      → void
 *   - `connect(deviceAddress)`    → void
 *   - `createGroup`               → void (receiver-side group owner)
 *
 * EventChannel: `karlshare/discovery/events`
 *   Emits maps with `type` ∈ { peerFound, peerLost, groupReady, error }.
 */
class DiscoveryService(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        const val METHOD_CHANNEL = "karlshare/discovery"
        const val EVENT_CHANNEL = "karlshare/discovery/events"
    }

    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL).also {
        it.setMethodCallHandler(this)
    }
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL).also {
        it.setStreamHandler(this)
    }

    private var eventSink: EventChannel.EventSink? = null
    private val peers = ConcurrentHashMap<String, WifiDirectManager.PeerDevice>()
    private val wifiDirect: WifiDirectManager = WifiDirectManager(context, ListenerImpl())

    fun dispose() {
        wifiDirect.stop()
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        eventSink = null
        peers.clear()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> result.success(wifiDirect.isSupported)
            "start" -> {
                wifiDirect.start()
                wifiDirect.startDiscovery()
                result.success(null)
            }
            "stop" -> {
                wifiDirect.stopDiscovery()
                result.success(null)
            }
            "createGroup" -> {
                wifiDirect.createGroup()
                result.success(null)
            }
            "connect" -> {
                val address = call.argument<String>("deviceAddress")
                if (address.isNullOrBlank()) {
                    result.error("ARG", "deviceAddress required", null)
                } else {
                    wifiDirect.connectTo(address)
                    result.success(null)
                }
            }
            "disconnect" -> {
                wifiDirect.disconnect()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        // Replay any peers we'd already collected so the Dart side rebuilds state.
        peers.values.forEach { emit("peerFound", it.toMap()) }
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    // ---- Listener wiring ---------------------------------------------------

    private inner class ListenerImpl : WifiDirectManager.Listener {
        override fun onPeerFound(device: WifiDirectManager.PeerDevice) {
            peers[device.address] = device
            emit("peerFound", device.toMap())
        }

        override fun onPeerLost(deviceAddress: String) {
            peers.remove(deviceAddress)
            emit("peerLost", mapOf("address" to deviceAddress))
        }

        override fun onGroupReady(ownerIp: String, isGroupOwner: Boolean) {
            emit(
                "groupReady",
                mapOf("ownerIp" to ownerIp, "isGroupOwner" to isGroupOwner),
            )
        }

        override fun onError(stage: String, reason: Int) {
            emit("error", mapOf("stage" to stage, "reason" to reason))
        }
    }

    private fun WifiDirectManager.PeerDevice.toMap(): Map<String, Any> = mapOf(
        "address" to address,
        "name" to name,
        "signalStrength" to signalStrength,
        "isAvailable" to isAvailable,
    )

    private fun emit(type: String, body: Map<String, Any>) {
        val payload = HashMap<String, Any>(body.size + 1)
        payload["type"] = type
        payload.putAll(body)
        // EventSink callbacks must run on the main thread.
        val sink = eventSink ?: return
        android.os.Handler(context.mainLooper).post { sink.success(payload) }
    }
}
