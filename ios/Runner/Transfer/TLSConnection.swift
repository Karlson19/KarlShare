import Foundation
import Network
import CryptoKit

/// Async/await wrapper around an `NWConnection` carrying a Karlshare TLS 1.3
/// session. Bridges Network.framework's callback API to `async` reads/writes
/// and exposes the peer's SubjectPublicKeyInfo fingerprint (read from the TLS
/// metadata after the handshake) so the engine can bind it to the Karlshare
/// handshake frame.
final class TLSConnection {

    let connection: NWConnection
    private let queue = DispatchQueue(label: "karlshare.tls.conn")
    private var buffer = Data()

    init(connection: NWConnection) {
        self.connection = connection
    }

    func start() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.connection.stateUpdateHandler = nil
                    cont.resume()
                case .failed(let error), .waiting(let error):
                    self?.connection.stateUpdateHandler = nil
                    cont.resume(throwing: error)
                case .cancelled:
                    self?.connection.stateUpdateHandler = nil
                    cont.resume(throwing: KarlshareProtocol.ProtocolError.eof)
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }

    func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume() }
            })
        }
    }

    /// Reads exactly `n` bytes, buffering any excess. Throws `.eof` if the
    /// connection closes before `n` bytes arrive.
    func readExactly(_ n: Int) async throws -> Data {
        if n == 0 { return Data() }
        while buffer.count < n {
            let more = try await receiveChunk()
            if more.isEmpty { throw KarlshareProtocol.ProtocolError.eof }
            buffer.append(more)
        }
        let out = buffer.prefix(n)
        buffer.removeFirst(n)
        return Data(out)
    }

    private func receiveChunk() async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) {
                data, _, isComplete, error in
                if let error { cont.resume(throwing: error); return }
                if let data, !data.isEmpty { cont.resume(returning: data); return }
                cont.resume(returning: Data()) // EOF (isComplete) or empty
            }
        }
    }

    /// SHA-256(SPKI) of the peer's leaf certificate, read from the established
    /// TLS metadata. Reconstructs SPKI via CryptoKit from the EC point so it
    /// matches the bytes Android hashes (`cert.publicKey.encoded`).
    func peerFingerprint() -> Data? {
        guard let tlsMeta = connection.metadata(definition: NWProtocolTLS.definition)
                as? NWProtocolTLS.Metadata else { return nil }
        let sec = tlsMeta.securityProtocolMetadata

        var leaf: SecCertificate?
        sec_protocol_metadata_access_peer_certificate_chain(sec) { certRef in
            if leaf == nil {
                leaf = sec_certificate_copy_ref(certRef).takeRetainedValue()
            }
        }
        guard let cert = leaf,
              let key = SecCertificateCopyKey(cert),
              let x963 = SecKeyCopyExternalRepresentation(key, nil) as Data?,
              let pub = try? P256.Signing.PublicKey(x963Representation: x963)
        else { return nil }
        return Data(SHA256.hash(data: pub.derRepresentation))
    }

    func cancel() { connection.cancel() }
}

/// Builds Karlshare TLS 1.3 parameters with our local identity and an
/// accept-any peer-verify block (the real check is fingerprint binding after
/// the handshake — mirrors Android's trust-all `X509TrustManager`).
enum KarlshareTLS {

    static func parameters(identity: KarlshareIdentity) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let sec = tls.securityProtocolOptions

        if let secIdentity = identity.secIdentity() {
            sec_protocol_options_set_local_identity(sec, secIdentity)
        }
        sec_protocol_options_set_min_tls_protocol_version(sec, .TLSv13)
        sec_protocol_options_set_max_tls_protocol_version(sec, .TLSv13)
        sec_protocol_options_set_peer_authentication_required(sec, true)

        // Accept any cert at the TLS layer; we bind identity via the
        // post-handshake fingerprint check.
        sec_protocol_options_set_verify_block(sec, { _, _, complete in
            complete(true)
        }, DispatchQueue(label: "karlshare.tls.verify"))

        let params = NWParameters(tls: tls)
        params.allowLocalEndpointReuse = true
        params.includePeerToPeer = true
        return params
    }
}
