import Foundation
import MultipeerConnectivity
import UIKit

/// iOS↔iOS fast path via MultipeerConnectivity (spec §7.3). Handles discovery
/// (advertiser + browser), session lifecycle, and file transfer over
/// `MCSession.sendResource` — which carries its own encryption, so the
/// TLS/fingerprint binding used on the TCP path doesn't apply here.
///
/// Peers surface on the discovery stream with `mc:`-prefixed addresses;
/// `TransferEngine` routes `sendFiles(peerIp:)` whose peerIp starts with `mc:`
/// to this manager.
final class MultipeerManager: NSObject {

    typealias Emit = (_ type: String, _ body: [String: Any]) -> Void

    private let serviceType = "karlshare-mc" // ≤15 chars; matches Info.plist
    private let discoveryEmit: Emit
    private let transferEmit: Emit
    private let saveDir: URL

    private let myPeerId = MCPeerID(displayName: UIDevice.current.name)
    private lazy var session: MCSession = {
        let s = MCSession(peer: myPeerId, securityIdentity: nil, encryptionPreference: .required)
        s.delegate = self
        return s
    }()
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    /// address-key ("mc:<displayName>") → MCPeerID.
    private var peers: [String: MCPeerID] = [:]
    /// Active outbound transfer bookkeeping, keyed by transferId.
    private var outbound: [String: OutboundState] = [:]
    private var progressObservations: [NSKeyValueObservation] = []

    let isSupported = true

    init(saveDir: URL, discoveryEmit: @escaping Emit, transferEmit: @escaping Emit) {
        self.saveDir = saveDir
        self.discoveryEmit = discoveryEmit
        self.transferEmit = transferEmit
        super.init()
    }

    // MARK: - Discovery

    func start() {
        let adv = MCNearbyServiceAdvertiser(peer: myPeerId, discoveryInfo: nil, serviceType: serviceType)
        adv.delegate = self
        adv.startAdvertisingPeer()
        advertiser = adv

        let br = MCNearbyServiceBrowser(peer: myPeerId, serviceType: serviceType)
        br.delegate = self
        br.startBrowsingForPeers()
        browser = br
    }

    func stop() {
        advertiser?.stopAdvertisingPeer(); advertiser = nil
        browser?.stopBrowsingForPeers(); browser = nil
        session.disconnect()
        peers.removeAll()
    }

    func connect(address: String) {
        guard let peer = peers[address], let browser else { return }
        browser.invitePeer(peer, to: session, withContext: nil, timeout: 30)
    }

    func disconnect() { session.disconnect() }

    // MARK: - Transfer (routed here for mc: peers)

    func send(peerKey: String, files: [[String: Any]], transferId: String) {
        guard let peer = peers[peerKey] else {
            transferEmit("error", ["transferId": transferId, "message": "peer not connected"])
            return
        }
        let parsed: [(url: URL, name: String, size: Int)] = files.compactMap { f in
            guard let path = f["path"] as? String else { return nil }
            let url = URL(fileURLWithPath: path)
            let name = (f["name"] as? String) ?? url.lastPathComponent
            let size = (f["size"] as? NSNumber)?.intValue ?? 0
            return (url, name, size)
        }
        outbound[transferId] = OutboundState(remaining: parsed.count)

        for file in parsed {
            let fileId = UUID().uuidString
            transferEmit("header", [
                "transferId": transferId, "fileId": fileId,
                "name": file.name, "size": file.size, "mime": "application/octet-stream",
            ])
            let progress = session.sendResource(at: file.url, withName: file.name, toPeer: peer) {
                [weak self] error in
                guard let self else { return }
                if let error {
                    self.transferEmit("error", ["transferId": transferId, "fileId": fileId,
                                                "message": error.localizedDescription])
                } else {
                    self.transferEmit("fileComplete", ["transferId": transferId, "fileId": fileId])
                }
                self.finishOne(transferId)
            }
            if let progress {
                let obs = progress.observe(\.fractionCompleted) { [weak self] p, _ in
                    self?.transferEmit("progress", [
                        "transferId": transferId, "fileId": fileId,
                        "fileBytes": Int(Double(file.size) * p.fractionCompleted),
                        "fileTotal": file.size,
                    ])
                }
                progressObservations.append(obs)
            }
        }
    }

    private func finishOne(_ transferId: String) {
        guard var state = outbound[transferId] else { return }
        state.remaining -= 1
        outbound[transferId] = state
        if state.remaining <= 0 {
            outbound.removeValue(forKey: transferId)
            transferEmit("transferComplete", ["transferId": transferId])
        }
    }

    private struct OutboundState { var remaining: Int }
}

// MARK: - Browser

extension MultipeerManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
                 withDiscoveryInfo info: [String: String]?) {
        let key = "mc:\(peerID.displayName)"
        peers[key] = peerID
        discoveryEmit("peerFound", [
            "address": key, "name": peerID.displayName,
            "signalStrength": 100, "isAvailable": true,
        ])
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        let key = "mc:\(peerID.displayName)"
        peers.removeValue(forKey: key)
        discoveryEmit("peerLost", ["address": key])
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        discoveryEmit("error", ["stage": "mcBrowse", "reason": -1])
    }
}

// MARK: - Advertiser

extension MultipeerManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Auto-accept — the app-level UI gates who you transfer with.
        invitationHandler(true, session)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didNotStartAdvertisingPeer error: Error) {
        discoveryEmit("error", ["stage": "mcAdvertise", "reason": -1])
    }
}

// MARK: - Session

extension MultipeerManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        // No IP semantics for MC; the UI treats a connected MC peer as ready.
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {}

    func session(_ session: MCSession, didReceive stream: InputStream,
                 withName streamName: String, fromPeer peerID: MCPeerID) {}

    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, with progress: Progress) {
        let transferId = "mc-in:\(peerID.displayName)"
        transferEmit("header", [
            "transferId": transferId, "fileId": resourceName,
            "name": resourceName, "size": Int(progress.totalUnitCount),
            "mime": "application/octet-stream", "direction": "received",
        ])
        let obs = progress.observe(\.fractionCompleted) { [weak self] p, _ in
            self?.transferEmit("progress", [
                "transferId": transferId, "fileId": resourceName,
                "fileBytes": Int(Double(progress.totalUnitCount) * p.fractionCompleted),
                "fileTotal": Int(progress.totalUnitCount),
            ])
        }
        progressObservations.append(obs)
    }

    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        let transferId = "mc-in:\(peerID.displayName)"
        guard error == nil, let localURL else {
            transferEmit("error", ["transferId": transferId, "fileId": resourceName,
                                   "message": error?.localizedDescription ?? "receive failed"])
            return
        }
        let dest = uniqueURL(for: resourceName)
        try? FileManager.default.moveItem(at: localURL, to: dest)
        transferEmit("fileComplete", ["transferId": transferId, "fileId": resourceName,
                                      "savePath": dest.path])
        transferEmit("transferComplete", ["transferId": transferId])
    }

    private func uniqueURL(for name: String) -> URL {
        let base = saveDir.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: base.path) { return base }
        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        var i = 1
        while true {
            let candidate = ext.isEmpty
                ? saveDir.appendingPathComponent("\(stem) (\(i))")
                : saveDir.appendingPathComponent("\(stem) (\(i)).\(ext)")
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            i += 1
        }
    }
}
