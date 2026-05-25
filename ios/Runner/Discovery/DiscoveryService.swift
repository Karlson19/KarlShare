import Foundation
import Flutter

/// Flutter platform-channel bridge for discovery — Swift counterpart to the
/// Android `DiscoveryService.kt`. Unifies the Bonjour/TCP path
/// (`BonjourManager`) and the iOS↔iOS Multipeer path (`MultipeerManager`) into
/// one `karlshare/discovery` channel.
///
/// MethodChannel `karlshare/discovery`:
///   isSupported → Bool, start, stop, connect(deviceAddress), createGroup, disconnect
/// EventChannel `karlshare/discovery/events`:
///   { type ∈ peerFound | peerLost | groupReady | error, ... }
final class DiscoveryService: NSObject, FlutterStreamHandler {

    static let methodChannelName = "karlshare/discovery"
    static let eventChannelName = "karlshare/discovery/events"

    private let methodChannel: FlutterMethodChannel
    private let eventChannel: FlutterEventChannel
    private var eventSink: FlutterEventSink?

    private lazy var bonjour = BonjourManager(emit: { [weak self] in self?.emit($0, $1) })
    let multipeer: MultipeerManager

    init(messenger: FlutterBinaryMessenger, saveDir: URL,
         transferEmit: @escaping (String, [String: Any]) -> Void) {
        self.methodChannel = FlutterMethodChannel(
            name: DiscoveryService.methodChannelName, binaryMessenger: messenger)
        self.eventChannel = FlutterEventChannel(
            name: DiscoveryService.eventChannelName, binaryMessenger: messenger)
        // Built here so it can carry both the discovery and transfer emitters.
        var discoveryEmitProxy: ((String, [String: Any]) -> Void)?
        self.multipeer = MultipeerManager(
            saveDir: saveDir,
            discoveryEmit: { discoveryEmitProxy?($0, $1) },
            transferEmit: transferEmit)
        super.init()
        discoveryEmitProxy = { [weak self] in self?.emit($0, $1) }
        eventChannel.setStreamHandler(self)
        methodChannel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result)
        }
    }

    func dispose() {
        bonjour.stop()
        multipeer.stop()
        methodChannel.setMethodCallHandler(nil)
        eventChannel.setStreamHandler(nil)
        eventSink = nil
    }

    /// Routing hook for `TransferEngine` — mc:-addressed sends go to Multipeer.
    func sendViaMultipeer(peerKey: String, files: [[String: Any]], transferId: String) {
        multipeer.send(peerKey: peerKey, files: files, transferId: transferId)
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
        case "isSupported":
            result(true)
        case "start":
            bonjour.start(); multipeer.start(); result(nil)
        case "stop":
            bonjour.stop(); multipeer.stop(); result(nil)
        case "createGroup":
            // No explicit group owner on iOS — discoverability is handled by
            // TransferEngine.startServer (Bonjour advertise) / MC advertiser.
            result(nil)
        case "connect":
            guard let address = (call.arguments as? [String: Any])?["deviceAddress"] as? String,
                  !address.isEmpty else {
                result(FlutterError(code: "ARG", message: "deviceAddress required", details: nil))
                return
            }
            if address.hasPrefix("mc:") { multipeer.connect(address: address) }
            else { bonjour.connect(address: address) }
            result(nil)
        case "disconnect":
            bonjour.disconnect(); multipeer.disconnect(); result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func emit(_ type: String, _ body: [String: Any]) {
        guard let sink = eventSink else { return }
        var payload = body
        payload["type"] = type
        DispatchQueue.main.async { sink(payload) }
    }
}
