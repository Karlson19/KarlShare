import Foundation

/// Trust-on-first-use cache for peer cert fingerprints — Swift mirror of the
/// Android `PeerTrustStore.kt`.
///
/// First time we complete a Karlshare handshake with a peer (TLS auth +
/// fingerprint binding verified), we cache their device UUID → fingerprint.
/// Subsequent connections with the same UUID must present the same
/// fingerprint, else we refuse — that's the signal someone has spoofed the
/// deviceId. Stored in UserDefaults as base64(SHA-256) keyed by UUID.
final class PeerTrustStore {

    enum Result {
        /// Brand-new peer — caller should pin the fingerprint after success.
        case firstSeen
        /// Same peer we've seen before. Safe to proceed.
        case known
        /// Same deviceId but a different fingerprint — refuse.
        case mismatch(expected: String, actual: String)
    }

    private let defaults: UserDefaults
    private let keyPrefix = "karlshare_peer."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Checks the proposed (deviceId, fingerprint) pair against the cache.
    /// Does NOT write — call `pin` after the handshake completes successfully.
    func verify(deviceId: UUID, fingerprint: Data) -> Result {
        let encoded = fingerprint.base64EncodedString()
        guard let existing = defaults.string(forKey: key(deviceId)) else {
            return .firstSeen
        }
        return existing == encoded
            ? .known
            : .mismatch(expected: existing, actual: encoded)
    }

    func pin(deviceId: UUID, fingerprint: Data) {
        defaults.set(fingerprint.base64EncodedString(), forKey: key(deviceId))
    }

    func forget(deviceId: UUID) {
        defaults.removeObject(forKey: key(deviceId))
    }

    func forgetAll() {
        for k in defaults.dictionaryRepresentation().keys where k.hasPrefix(keyPrefix) {
            defaults.removeObject(forKey: k)
        }
    }

    private func key(_ id: UUID) -> String { keyPrefix + id.uuidString }
}
