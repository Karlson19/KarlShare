package com.karlshare.karlshare.transfer

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.math.BigInteger
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.MessageDigest
import java.security.PrivateKey
import java.security.cert.X509Certificate
import java.util.Date
import java.util.UUID
import javax.net.ssl.KeyManagerFactory
import javax.security.auth.x500.X500Principal

/**
 * Karlshare's per-install TLS identity.
 *
 * On first launch we generate an ECDSA P-256 keypair inside Android's
 * hardware-backed keystore — the private key never leaves the secure
 * element. A 10-year self-signed X.509 cert is generated alongside (CN =
 * device UUID). Both are cached and re-used across launches.
 *
 * The 32-byte SHA-256 of the cert's SubjectPublicKeyInfo is what we put in
 * the Karlshare handshake frame's PUBLIC_KEY field — a stable fingerprint
 * that lets both peers cross-check the TLS-negotiated identity against the
 * one declared in plaintext at the protocol layer (MITM resistance).
 */
class KarlshareKeystore(private val deviceId: UUID) {

    // Companion is declared at the bottom of the class so it can host both
    // the constants and the static `fingerprintFor` helper.

    private val keystore: KeyStore = KeyStore.getInstance(KEYSTORE).apply { load(null) }

    val privateKey: PrivateKey by lazy {
        ensureKeyPair()
        keystore.getKey(ALIAS, null) as PrivateKey
    }

    val certificate: X509Certificate by lazy {
        ensureKeyPair()
        keystore.getCertificate(ALIAS) as X509Certificate
    }

    /**
     * SHA-256 of the certificate's SubjectPublicKeyInfo (the X.509
     * `subjectPublicKey` field as DER). Used as the binding token in the
     * Karlshare handshake.
     */
    val publicKeyFingerprint: ByteArray by lazy {
        fingerprintFor(certificate)
    }

    /** [KeyManagerFactory] feeding the JSSE so TLS can present our cert. */
    fun keyManagerFactory(): KeyManagerFactory {
        ensureKeyPair()
        return KeyManagerFactory.getInstance(
            KeyManagerFactory.getDefaultAlgorithm(),
        ).apply { init(keystore, null) }
    }

    private fun ensureKeyPair() {
        if (keystore.containsAlias(ALIAS)) return

        val now = Date()
        val tenYearsLater = Date(now.time + 10L * 365 * 24 * 60 * 60 * 1000)

        val spec = KeyGenParameterSpec.Builder(
            ALIAS,
            KeyProperties.PURPOSE_SIGN,
        )
            .setAlgorithmParameterSpec(java.security.spec.ECGenParameterSpec("secp256r1"))
            .setDigests(KeyProperties.DIGEST_SHA256)
            .setCertificateSubject(X500Principal("CN=$deviceId,O=Karlshare"))
            .setCertificateSerialNumber(BigInteger.valueOf(System.currentTimeMillis()))
            .setCertificateNotBefore(now)
            .setCertificateNotAfter(tenYearsLater)
            .build()

        val generator = KeyPairGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_EC,
            KEYSTORE,
        )
        generator.initialize(spec)
        generator.generateKeyPair()
    }

    companion object {
        private const val ALIAS = "karlshare_identity"
        private const val KEYSTORE = "AndroidKeyStore"

        /** SHA-256 of an X.509 cert's SubjectPublicKeyInfo (the DER public-key bytes). */
        fun fingerprintFor(cert: X509Certificate): ByteArray {
            val md = MessageDigest.getInstance("SHA-256")
            return md.digest(cert.publicKey.encoded)
        }
    }
}
