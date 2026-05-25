package com.karlshare.karlshare.transfer

import android.content.Context
import android.util.Base64
import android.util.Log
import java.util.UUID

/**
 * Trust-on-first-use cache for peer cert fingerprints.
 *
 * First time we successfully complete a Karlshare handshake with a peer
 * (TLS auth + fingerprint binding verified), we cache their device UUID →
 * fingerprint mapping. Subsequent connections with the same UUID must
 * present the same fingerprint, else we refuse the connection — that's the
 * signal that someone has spoofed the deviceId.
 *
 * Stored in SharedPreferences as base64(SHA-256) strings keyed by UUID.
 */
class PeerTrustStore(context: Context) {

    companion object {
        private const val TAG = "PeerTrustStore"
        private const val PREFS = "karlshare_peers"
    }

    private val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /**
     * Result of consulting the trust store before completing a handshake.
     */
    sealed class Result {
        /** Brand-new peer — caller should pin the fingerprint after success. */
        object FirstSeen : Result()

        /** Same peer we've seen before. Safe to proceed. */
        object Known : Result()

        /** Same deviceId but a different fingerprint — refuse. */
        data class Mismatch(val expected: String, val actual: String) : Result()
    }

    /**
     * Checks the proposed [(deviceId, fingerprint)] pair against the cache.
     * Does NOT write — call [pin] after the handshake completes successfully
     * so we don't pin a fingerprint that turned out to belong to a session
     * we later aborted.
     */
    fun verify(deviceId: UUID, fingerprint: ByteArray): Result {
        val encoded = Base64.encodeToString(fingerprint, Base64.NO_WRAP)
        val existing = prefs.getString(deviceId.toString(), null)
        return when {
            existing == null -> Result.FirstSeen
            existing == encoded -> Result.Known
            else -> {
                Log.w(TAG, "fingerprint mismatch for $deviceId")
                Result.Mismatch(existing, encoded)
            }
        }
    }

    fun pin(deviceId: UUID, fingerprint: ByteArray) {
        val encoded = Base64.encodeToString(fingerprint, Base64.NO_WRAP)
        prefs.edit().putString(deviceId.toString(), encoded).apply()
    }

    fun forget(deviceId: UUID) {
        prefs.edit().remove(deviceId.toString()).apply()
    }

    fun forgetAll() {
        prefs.edit().clear().apply()
    }
}
