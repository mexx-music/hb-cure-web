package com.example.hbcure

import org.bouncycastle.crypto.digests.SHA256Digest
import org.bouncycastle.crypto.signers.ECDSASigner
import org.bouncycastle.crypto.signers.HMacDSAKCalculator
import org.bouncycastle.crypto.params.ECPrivateKeyParameters
import org.bouncycastle.crypto.params.ECPublicKeyParameters
import org.bouncycastle.asn1.sec.SECNamedCurves
import org.bouncycastle.crypto.params.ECDomainParameters
import java.math.BigInteger
import android.util.Log

/**
 * CureCrypto: native Kotlin helper to build unlock response signatures using secp256k1.
 * The signature is produced as 64 bytes: r||s (each 32 bytes, big-endian) and returned as hex.
 * Uses deterministic k (RFC6979 via HMacDSAKCalculator with SHA-256) for stable signatures.
 */
object CureCrypto {
    // private_key_CureApp from legacy Qt (32 bytes hex)
    private const val privHex = "E40783F681A5BB852CAB1E106B6641EFB43C1923C1EBE25CA36865CDFAB06548"

    private val domainParams: ECDomainParameters by lazy {
        val params = SECNamedCurves.getByName("secp256k1")
        ECDomainParameters(params.curve, params.g, params.n, params.h)
    }

    /**
     * Build unlock response signature for a 32-byte challenge given as hex string.
     * Returns 128-char hex (r||s) lowercase.
     */
    @JvmStatic
    fun buildUnlockResponse(challengeHex: String): String {
        val cleaned = challengeHex.replace(Regex("[^0-9A-Fa-f]"), "")
        if (cleaned.length != 64) {
            throw IllegalArgumentException("challengeHex must be 64 hex chars (32 bytes)")
        }
        val msg = hexStringToByteArray(cleaned)

        val priv = BigInteger(privHex, 16)
        val privParams = ECPrivateKeyParameters(priv, domainParams)

        val signer = ECDSASigner(HMacDSAKCalculator(SHA256Digest()))
        signer.init(true, privParams)

        val components = signer.generateSignature(msg)
        val r = components[0]
        val s = components[1]

        val rBytes = toFixedLength(r, 32)
        val sBytes = toFixedLength(s, 32)

        Log.d("CureCrypto", "buildUnlockResponse: challenge=$cleaned sig=${(rBytes + sBytes).toHexString()} (len=${(rBytes + sBytes).toHexString().length})")

        return (rBytes + sBytes).toHexString()
    }

    /**
     * Verifies a device signature for a given challenge using the public key.
     * @param challengeHex 64-char hex string representing the challenge (32 bytes).
     * @param sigHex 128-char hex string representing the signature (64 bytes: r||s).
     * @return true if the signature is valid, false otherwise.
     */
    @JvmStatic
    fun verifyDeviceSignature(challengeHex: String, sigHex: String): Boolean {
        val cleanedChallenge = challengeHex.replace(Regex("[^0-9A-Fa-f]"), "")
        val cleanedSig = sigHex.replace(Regex("[^0-9A-Fa-f]"), "")

        if (cleanedChallenge.length != 64 || cleanedSig.length != 128) {
            Log.w("CureCrypto", "verifyDeviceSignature: Invalid input lengths")
            return false
        }

        val challenge = hexStringToByteArray(cleanedChallenge)
        val sig = hexStringToByteArray(cleanedSig)
        val r = BigInteger(1, sig.copyOfRange(0, 32))
        val s = BigInteger(1, sig.copyOfRange(32, 64))

        // Public key from legacy Qt project
        val pubHex = "84993D74CACCB0901406255ECE4295E727A3D670918DDEA4246BBEF89FBB7BD9" +
                     "4EE1A8EDA4C0379309D9681BFE3D332E4815786B89F8F1F0F7F57DABED608116"
        val pubKeyBytes = hexStringToByteArray(pubHex)
        val x = BigInteger(1, pubKeyBytes.copyOfRange(0, 32))
        val y = BigInteger(1, pubKeyBytes.copyOfRange(32, 64))

        val ecPoint = domainParams.curve.createPoint(x, y)
        val publicKeyParams = ECPublicKeyParameters(ecPoint, domainParams)

        val signer = ECDSASigner()
        signer.init(false, publicKeyParams)

        val isValid = signer.verifySignature(challenge, r, s)

        Log.d(
            "CureCrypto",
            "verifyDeviceSignature: challenge=$cleanedChallenge sig=${cleanedSig.take(16)}... result=$isValid"
        )

        return isValid
    }

    private fun toFixedLength(bi: BigInteger, length: Int): ByteArray {
        val raw = bi.toByteArray()
        if (raw.size == length) return raw
        if (raw.size > length) {
            // raw may contain leading zero for sign
            return raw.copyOfRange(raw.size - length, raw.size)
        }
        val out = ByteArray(length)
        System.arraycopy(raw, 0, out, length - raw.size, raw.size)
        return out
    }

    private fun hexStringToByteArray(s: String): ByteArray {
        val len = s.length
        val data = ByteArray(len / 2)
        var i = 0
        while (i < len) {
            data[i / 2] = ((Character.digit(s[i], 16) shl 4) + Character.digit(s[i + 1], 16)).toByte()
            i += 2
        }
        return data
    }

    private fun ByteArray.toHexString(): String {
        val sb = StringBuilder(this.size * 2)
        for (b in this) sb.append(String.format("%02x", b))
        return sb.toString()
    }
}
