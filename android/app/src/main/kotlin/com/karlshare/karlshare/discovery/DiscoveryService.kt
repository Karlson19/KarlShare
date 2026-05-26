package com.karlshare.karlshare.discovery

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

/**
 * Flutter platform-channel bridge over {@link LanDiscovery}.
 *
 * MethodChannel `karlshare/discovery`:
 *   - `isSupported`            -> Bool
 *   - `start` / `stop`         -> begin/end Wi-Fi LAN discovery
 *   - `connect(deviceAddress)` -> no-op: the peer IP is already known from its
 *                                 beacon, so the transfer engine dials directly
 *   - `createGroup` / `disconnect` -> no-op (no group-owner step on the LAN path)
 *
 * EventChannel `karlshare/discovery/events`:
 *   { type in peerFound | peerLost | error, ... }. A peerFound carries the
 *   peer's `address` (its IP), `name`, `signalStrength`, `isAvailable`, `platform`.
 */
class DiscoveryService(
    private val context: Context,
    messenger: BinaryMessenger,
    deviceId: UUID,
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

    // ip -> (name, platform), so we can replay peers when Dart re-subscribes.
    private val peers = ConcurrentHashMap<String, Pair<String, String>>()
    private val lan = LanDiscovery(context, deviceId, ListenerImpl())

    fun dispose() {
        lan.stop()
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        eventSink = null
        peers.clear()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> result.success(true)
            "start" -> { lan.start(); result.success(null) }
            "stop" -> { lan.stop(); peers.clear(); result.success(null) }
            // The LAN path needs no group formation; the peer IP arrives with
            // its beacon, so these are accepted no-ops for API compatibility.
            "createGroup", "connect", "disconnect" -> result.success(null)
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        // Replay peers we already know so the radar repopulates instantly.
        peers.forEach { (ip, info) ->
            emit("peerFound", mapOf(
                "address" to ip,
                "name" to info.first,
                "signalStrength" to 100,
                "isAvailable" to true,
                "platform" to info.second,
            ))
        }
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private inner class ListenerImpl : LanDiscovery.Listener {
        override fun onPeerFound(address: String, name: String, platform: String) {
            peers[address] = name to platform
            emit("peerFound", mapOf(
                "address" to address,
                "name" to name,
                "signalStrength" to 100,
                "isAvailable" to true,
                "platform" to platform,
            ))
        }

        override fun onPeerLost(address: String) {
            peers.remove(address)
            emit("peerLost", mapOf("address" to address))
        }

        override fun onError(stage: String, reason: Int) {
            emit("error", mapOf("stage" to stage, "reason" to reason))
        }
    }

    private fun emit(type: String, body: Map<String, Any>) {
        val sink = eventSink ?: return
        val payload = HashMap<String, Any>(body.size + 1)
        payload["type"] = type
        payload.putAll(body)
        android.os.Handler(context.mainLooper).post { sink.success(payload) }
    }
}
