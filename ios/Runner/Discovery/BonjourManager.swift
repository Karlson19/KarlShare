import Foundation
import Network

/// Browses for `_karlshare._tcp` peers and resolves a chosen peer to an IP so
/// the IP-centric transfer engine can dial it. This is the iOS↔Android interop
/// path (spec §7.3) and also works iOS↔iOS on a shared Wi-Fi network.
///
/// Advertising is handled by `TransferEngine`'s listener (which publishes the
/// same service while in receive mode), so this manager is browse + resolve
/// only.
final class BonjourManager {

    typealias Emit = (_ type: String, _ body: [String: Any]) -> Void

    private let serviceType = "_karlshare._tcp"
    private let emit: Emit
    private let queue = DispatchQueue(label: "karlshare.bonjour")

    private var browser: NWBrowser?
    /// address-key → discovered endpoint, so `connect` can resolve it.
    private var endpoints: [String: NWEndpoint] = [:]

    let isSupported = true

    init(emit: @escaping Emit) {
        self.emit = emit
    }

    func start() {
        guard browser == nil else { return }
        let params = NWParameters()
        params.includePeerToPeer = true
        let b = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: params)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            self?.handleResults(results)
        }
        b.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.emit("error", ["stage": "browse", "reason": -1]) }
        }
        b.start(queue: queue)
        browser = b
    }

    func stop() {
        browser?.cancel()
        browser = nil
        endpoints.removeAll()
    }

    /// Resolve the chosen peer to an IP and report it as a "group ready" event,
    /// matching the Android WiFi-Direct flow the Dart layer expects.
    func connect(address: String) {
        guard let endpoint = endpoints[address] else {
            emit("error", ["stage": "connect", "reason": -1])
            return
        }
        // A transient connection forces name resolution; once ready we read the
        // resolved remote IP from the connection path, then tear it down.
        let conn = NWConnection(to: endpoint, using: .tcp)
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let ip = Self.remoteIP(of: conn) {
                    self?.emit("groupReady", ["ownerIp": ip, "isGroupOwner": false])
                } else {
                    self?.emit("error", ["stage": "resolve", "reason": -1])
                }
                conn.cancel()
            case .failed:
                self?.emit("error", ["stage": "resolve", "reason": -1])
                conn.cancel()
            default:
                break
            }
        }
        conn.start(queue: queue)
    }

    func disconnect() { /* nothing persistent to tear down for the TCP path */ }

    // MARK: - Internals

    private func handleResults(_ results: Set<NWBrowser.Result>) {
        var present = Set<String>()
        for result in results {
            let key = Self.addressKey(for: result.endpoint)
            present.insert(key)
            if endpoints[key] == nil {
                endpoints[key] = result.endpoint
                emit("peerFound", [
                    "address": key,
                    "name": Self.displayName(for: result.endpoint),
                    "signalStrength": 100, // Bonjour gives no RSSI; assume strong
                    "isAvailable": true,
                ])
            }
        }
        // Drop peers that disappeared from the browse set.
        for key in Array(endpoints.keys) where !present.contains(key) {
            endpoints.removeValue(forKey: key)
            emit("peerLost", ["address": key])
        }
    }

    private static func addressKey(for endpoint: NWEndpoint) -> String {
        if case let .service(name, _, _, _) = endpoint { return "bonjour:\(name)" }
        return "bonjour:\(endpoint.debugDescription)"
    }

    private static func displayName(for endpoint: NWEndpoint) -> String {
        if case let .service(name, _, _, _) = endpoint { return name }
        return "Karlshare device"
    }

    private static func remoteIP(of conn: NWConnection) -> String? {
        guard let remote = conn.currentPath?.remoteEndpoint else { return nil }
        if case let .hostPort(host, _) = remote {
            switch host {
            case .ipv4(let addr): return "\(addr)"
            case .ipv6(let addr): return "\(addr)"
            case .name(let name, _): return name
            @unknown default: return nil
            }
        }
        return nil
    }
}
