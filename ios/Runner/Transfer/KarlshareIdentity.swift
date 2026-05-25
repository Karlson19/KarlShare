import Foundation
import CryptoKit
import Network
import Security
import X509            // SwiftPM: apple/swift-certificates
import SwiftASN1       // SwiftPM: transitive dep of swift-certificates

/// Karlshare's per-install TLS identity on iOS — the counterpart to Android's
/// `KarlshareKeystore.kt`.
///
/// iOS has no equivalent of Android's `KeyGenParameterSpec`, which mints a
/// self-signed cert for free. So we:
///   1. Generate (and persist) a P-256 signing key.
///   2. Mint a 10-year self-signed X.509 cert over it with swift-certificates.
///   3. Expose a `sec_identity_t` for NWProtocolTLS, and the SHA-256 of the
///      cert's SubjectPublicKeyInfo as the handshake binding token.
///
/// The fingerprint is computed as `SHA256(publicKey.derRepresentation)`.
/// CryptoKit's `derRepresentation` for a P-256 public key is exactly the
/// X.509 SubjectPublicKeyInfo DER — the same bytes Android hashes via
/// `cert.publicKey.encoded` — so fingerprints match across platforms.
///
/// REQUIRED Xcode setup (cannot be verified on a non-macOS host):
///   • Add Swift Package dependencies:
///       - https://github.com/apple/swift-certificates  (product: X509)
///       - https://github.com/apple/swift-crypto         (pulled transitively)
///   • Add this file + the other Runner/Transfer & Runner/Discovery files to
///     the Runner target's "Compile Sources" build phase.
///
/// NOTE: the key here lives in the Keychain rather than the Secure Enclave.
/// SE-backed signing + cert minting is possible but materially more complex;
/// it's a hardening follow-up. The wire protocol is unaffected either way.
final class KarlshareIdentity {

    private let deviceId: UUID
    private let keychainTag = "com.karlshare.identity.p256"

    init(deviceId: UUID) {
        self.deviceId = deviceId
    }

    // Generated lazily on first use, then reused for the process lifetime.
    private lazy var privateKey: P256.Signing.PrivateKey = loadOrCreateKey()

    /// SHA-256 of the cert's SubjectPublicKeyInfo (DER). Binding token for the
    /// Karlshare handshake's PUBLIC_KEY field. 32 bytes.
    lazy var publicKeyFingerprint: Data = {
        Data(SHA256.hash(data: privateKey.publicKey.derRepresentation))
    }()

    /// The self-signed leaf certificate, minted once and cached in the Keychain
    /// as DER so the identity is stable across launches.
    private lazy var certificate: Certificate = loadOrCreateCertificate()

    // MARK: - sec_identity for NWProtocolTLS

    /// Builds a `sec_identity_t` (cert + private key) for use as the local TLS
    /// identity. Imports the cert+key into the keychain and queries back a
    /// `SecIdentity`, which is what Network.framework requires.
    func secIdentity() -> sec_identity_t? {
        guard let secCert = makeSecCertificate(),
              let secKey = makeSecKey() else { return nil }

        // Ensure both halves are in the keychain so an identity can be formed.
        addToKeychain(secCert: secCert, secKey: secKey)

        guard let identity = queryIdentity() else { return nil }
        return sec_identity_create(identity)
    }

    // MARK: - Key persistence

    private func loadOrCreateKey() -> P256.Signing.PrivateKey {
        if let raw = keychainRead(account: keychainTag),
           let key = try? P256.Signing.PrivateKey(rawRepresentation: raw) {
            return key
        }
        let key = P256.Signing.PrivateKey()
        keychainWrite(account: keychainTag, data: key.rawRepresentation)
        return key
    }

    // MARK: - Certificate minting

    private func loadOrCreateCertificate() -> Certificate {
        let certTag = keychainTag + ".cert"
        if let der = keychainRead(account: certTag),
           let cert = try? Certificate(derEncoded: [UInt8](der)) {
            return cert
        }
        let cert = mintSelfSignedCertificate()
        if let der = try? derBytes(of: cert) {
            keychainWrite(account: certTag, data: Data(der))
        }
        return cert
    }

    private func mintSelfSignedCertificate() -> Certificate {
        let certKey = Certificate.PrivateKey(privateKey)
        let now = Date()
        let tenYears = now.addingTimeInterval(10 * 365 * 24 * 60 * 60)
        let name = try! DistinguishedName {
            CommonName(deviceId.uuidString)
            OrganizationName("Karlshare")
        }
        return try! Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: certKey.publicKey,
            notValidBefore: now,
            notValidAfter: tenYears,
            issuer: name,
            subject: name,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: try! Certificate.Extensions {
                Critical(BasicConstraints.isCertificateAuthority(maxPathLength: nil))
            },
            issuerPrivateKey: certKey
        )
    }

    private func derBytes(of cert: Certificate) throws -> [UInt8] {
        var serializer = DER.Serializer()
        try serializer.serialize(cert)
        return serializer.serializedBytes
    }

    // MARK: - Security framework bridging

    private func makeSecCertificate() -> SecCertificate? {
        guard let der = try? derBytes(of: certificate) else { return nil }
        return SecCertificateCreateWithData(nil, Data(der) as CFData)
    }

    private func makeSecKey() -> SecKey? {
        // CryptoKit x963 representation → SecKey (EC private key).
        let attrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: 256,
        ]
        var error: Unmanaged<CFError>?
        return SecKeyCreateWithData(
            privateKey.x963Representation as CFData,
            attrs as CFDictionary,
            &error
        )
    }

    private func addToKeychain(secCert: SecCertificate, secKey: SecKey) {
        let certAdd: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: secCert,
        ]
        SecItemAdd(certAdd as CFDictionary, nil) // errSecDuplicateItem is fine

        let keyAdd: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keychainTag.data(using: .utf8)!,
            kSecValueRef as String: secKey,
        ]
        SecItemAdd(keyAdd as CFDictionary, nil)
    }

    private func queryIdentity() -> SecIdentity? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess
        else { return nil }
        // swiftlint:disable:next force_cast
        return (result as! SecIdentity)
    }

    // MARK: - Keychain generic-password helpers

    private func keychainRead(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess
        else { return nil }
        return result as? Data
    }

    private func keychainWrite(account: String, data: Data) {
        let delete: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(delete as CFDictionary)
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(add as CFDictionary, nil)
    }

    /// SHA-256 of a peer cert's SubjectPublicKeyInfo. Matches Android's
    /// `KarlshareKeystore.fingerprintFor`.
    static func fingerprint(forSPKI spki: Data) -> Data {
        Data(SHA256.hash(data: spki))
    }
}
