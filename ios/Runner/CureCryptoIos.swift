import Foundation
import CommonCrypto

/// Minimal safe stub for CureCrypto on iOS.
/// Purpose: keep the same API surface but avoid requiring the native C secp256k1 module
/// at build time. If native secp256k1 support is added later (via SPM/Pod/modulemap),
/// this stub can be replaced with the real implementation.

enum CureCryptoError: Error {
    case badChallengeLen
    case badPrivLen
    case secpCreateContext
    case signFailed
}

final class CureCryptoIos {
    // Private key (same constant as Android CureCrypto.kt). Do NOT log this.
    private static let privHex = "E40783F681A5BB852CAB1E106B6641EFB43C1923C1EBE25CA36865CDFAB06548"

    // Toggle which signature variant to return: false = raw r||s, true = normalized (low-S) r||s
    // Android/Python use raw (non-normalized) secp256k1 signature and the firmware expects that.
    // Do NOT normalize — the firmware rejects low-S normalized signatures.
    private static let useNormalizedSignature: Bool = false

    /// Returns the private key hex to use for signing. Priority:
    /// 1) Environment variable CURE_PRIV_HEX (useful for CI / debug)
    /// 2) UserDefaults key "CURE_PRIV_HEX" (settable from app/tests)
    /// 3) Embedded fallback `privHex` constant
    /// Note: We never log the key value itself. Only the chosen source is logged.
    private static func getPrivateKeyHex() -> String {
        if let env = ProcessInfo.processInfo.environment["CURE_PRIV_HEX"]?.trimmingCharacters(in: .whitespacesAndNewlines), !env.isEmpty {
            // Accept only plausible length (64 hex chars) to avoid accidental leakage
            if env.count == 64 {
                NSLog("IOS_PRIVKEY_SOURCE=env")
                return env
            }
        }
        if let ud = UserDefaults.standard.string(forKey: "CURE_PRIV_HEX")?.trimmingCharacters(in: .whitespacesAndNewlines), !ud.isEmpty {
            if ud.count == 64 {
                NSLog("IOS_PRIVKEY_SOURCE=userdefaults")
                return ud
            }
        }
        NSLog("IOS_PRIVKEY_SOURCE=embedded")
        return privHex
    }

    /// Attempt to build an unlock response on iOS using libsecp256k1 C API.
    /// Returns 128-char hex (r||s) lowercase on success.
    static func buildUnlockResponse(challengeHex: String) throws -> (sig: String, pubkeyHex: String, selfVerifyOk: Int32) {
        // Clean input
        let cleaned = hexClean(challengeHex)
        guard cleaned.count == 64, let msgData = Data(hex: cleaned) else { throw CureCryptoError.badChallengeLen }

        // Debug: emit challenge and msg bytes (hex) to device log (do NOT reveal private key)
        NSLog("IOS_DEBUG_CHALLENGE=%@", cleaned)
        let msgHex = msgData.map { String(format: "%02x", $0) }.joined()
        NSLog("IOS_DEBUG_MSG_RAW=%@", msgHex)
        NSLog("IOS_DEBUG_MSG_RAW_LEN=%d", msgData.count)

        // Android BouncyCastle ECDSASigner.generateSignature(msg) does NOT hash the message.
        // It calls calculateE(n, msg) which is just BigInteger(1, msg) — raw bytes as integer.
        // HMacDSAKCalculator(SHA256Digest) only governs RFC6979 k-nonce derivation, not the message.
        // libsecp256k1 secp256k1_ecdsa_sign() must therefore receive the RAW 32-byte challenge,
        // not SHA256(challenge). Passing SHA256(challenge) produces a completely different signature.
        let hashedHex = msgData.map { String(format: "%02x", $0) }.joined()
        NSLog("IOS_DEBUG_MSG_RAW_USED_FOR_SIGN=%@", hashedHex)

        // Private key bytes - obtain via getter (env / userdefaults / embedded)
        let keyHex = getPrivateKeyHex()
        guard let privData = Data(hex: keyHex), privData.count == 32 else { throw CureCryptoError.badPrivLen }

        // Log key fingerprint (first 8 + last 8 hex chars only, NEVER full key)
        NSLog("IOS_DEBUG_KEY_FINGERPRINT first8=%@ last8=%@ len=%d", String(keyHex.prefix(8)), String(keyHex.suffix(8)), privData.count)
        NSLog("IOS_DEBUG_SIGNING_API=libsecp256k1_C_API_secp256k1_ecdsa_sign")

        // Create secp256k1 context
        guard let ctx = secp256k1_context_create(UInt32(SECP256K1_CONTEXT_SIGN)) else { throw CureCryptoError.secpCreateContext }
        defer { secp256k1_context_destroy(ctx) }

        // Verify seckey
        var seckey = [UInt8](privData)
        let okKey: Int32 = privData.withUnsafeBytes { privBuf in
            secp256k1_ec_seckey_verify(ctx, privBuf.bindMemory(to: UInt8.self).baseAddress!)
        }
        if okKey != 1 { throw CureCryptoError.badPrivLen }

        // Prepare buffers — use SHA-256 hashed challenge (Android parity)
        var sig = secp256k1_ecdsa_signature()
        // Prepare buffers — raw challenge bytes (Android parity: BigInteger(1, challenge))
        var msg32 = [UInt8](msgData)

        // Sign (RFC6979 deterministic nonce when noncefp is nil)
        // NOTE: msg32 is the raw 32-byte challenge, matching Android ECDSASigner.generateSignature(msg)
        let signOk = msg32.withUnsafeMutableBufferPointer { msgPtr -> Int32 in
            seckey.withUnsafeMutableBufferPointer { skPtr -> Int32 in
                secp256k1_ecdsa_sign(ctx, &sig, msgPtr.baseAddress!, skPtr.baseAddress!, nil, nil)
            }
        }
        if signOk != 1 { throw CureCryptoError.signFailed }

        // Derive public key from private key and log it (no private key value in log)
        var derivedPubkeyHex: String = ""
        var selfVerifyResult: Int32 = -1
        var derivedPub = secp256k1_pubkey()
        let pubCreateOk: Int32 = seckey.withUnsafeMutableBufferPointer { skPtr -> Int32 in
            secp256k1_ec_pubkey_create(ctx, &derivedPub, skPtr.baseAddress!)
        }
        NSLog("IOS_DEBUG_PUBKEY_DERIVE_OK=%d", pubCreateOk)
        if pubCreateOk == 1 {
            var pubBytes = [UInt8](repeating: 0, count: 65)
            var pubLen: Int = 65
            secp256k1_ec_pubkey_serialize(ctx, &pubBytes, &pubLen, &derivedPub, UInt32(SECP256K1_EC_UNCOMPRESSED))
            derivedPubkeyHex = pubBytes.prefix(pubLen).map { String(format: "%02x", $0) }.joined()
            NSLog("IOS_DEBUG_DERIVED_PUBKEY=%@", derivedPubkeyHex)

            // Self-verify: confirm produced sig verifies against derived pubkey + raw msg32
            selfVerifyResult = msg32.withUnsafeMutableBufferPointer { msgPtr -> Int32 in
                secp256k1_ecdsa_verify(ctx, &sig, msgPtr.baseAddress!, &derivedPub)
            }
            NSLog("IOS_DEBUG_SIG_SELF_VERIFY=%d (1=valid 0=invalid)", selfVerifyResult)
        }

        // Serialize compact r||s (64 bytes raw) into out64
        var out64 = [UInt8](repeating: 0, count: 64)
        let serOk = out64.withUnsafeMutableBufferPointer { outPtr -> Int32 in
            secp256k1_ecdsa_signature_serialize_compact(ctx, outPtr.baseAddress!, &sig)
        }
        if serOk != 1 { throw CureCryptoError.signFailed }

        // Also produce normalized (low-S) variant and log both; return per toggle
        var normSig = secp256k1_ecdsa_signature()
        let normChanged = secp256k1_ecdsa_signature_normalize(ctx, &normSig, &sig)

        var norm64 = [UInt8](repeating: 0, count: 64)
        let serNormOk = norm64.withUnsafeMutableBufferPointer { outPtr -> Int32 in
            secp256k1_ecdsa_signature_serialize_compact(ctx, outPtr.baseAddress!, &normSig)
        }
        if serNormOk != 1 { throw CureCryptoError.signFailed }

        let rawHex = out64.map { String(format: "%02x", $0) }.joined()
        let normHex = norm64.map { String(format: "%02x", $0) }.joined()

        // Additional variant exploration for parity debugging (no effect on returned result)
        func hexFromBytes(_ arr: [UInt8]) -> String { arr.map { String(format: "%02x", $0) }.joined() }
        func swapHalves(_ a: [UInt8]) -> [UInt8] { Array(a[32..<64]) + Array(a[0..<32]) }
        func reverseEachHalf(_ a: [UInt8]) -> [UInt8] { Array(a[0..<32].reversed()) + Array(a[32..<64].reversed()) }

        let rawSwap = hexFromBytes(swapHalves(out64))
        let normSwap = hexFromBytes(swapHalves(norm64))
        let rawRev = hexFromBytes(reverseEachHalf(out64))
        let normRev = hexFromBytes(reverseEachHalf(norm64))

        // Log all variants so we can visually compare to Android's ANDROID_DEBUG_SIG
        NSLog("CureCryptoIos buildUnlockResponse: normChanged=%d", normChanged)
        NSLog("IOS_DEBUG_SIG_RAW=%@", rawHex)
        NSLog("IOS_DEBUG_SIG_NORM=%@", normHex)
        NSLog("IOS_DEBUG_SIG_RAW_SWAP_HALVES=%@", rawSwap)
        NSLog("IOS_DEBUG_SIG_NORM_SWAP_HALVES=%@", normSwap)
        NSLog("IOS_DEBUG_SIG_RAW_REVHALVES=%@", rawRev)
        NSLog("IOS_DEBUG_SIG_NORM_REVHALVES=%@", normRev)

        let sigSource = useNormalizedSignature ? "normalized_low_s" : "raw_secp256k1_signature"
        NSLog("IOS_SIG_SOURCE=%@", sigSource)
        var result = useNormalizedSignature ? normHex : rawHex

        // If the signer accidentally produced a 65-byte compact (130 hex) signature
        // (common when a recovery id byte got prepended), normalize it by dropping
        // the first byte so we return exactly 64 bytes (128 hex) as required by the Cube.
        if result.count == 130 {
            // drop first byte (2 hex chars)
            result = String(result.dropFirst(2))
            NSLog("IOS_DEBUG_SIG_NORMALIZED_DROPPED_RECOVERY")
        }

        // Log exact lengths so we can verify parity: expect hex=128 bytes=64
        NSLog("IOS_SIG_LEN hex=%d bytes=%d", result.count, result.count / 2)

        // Additional explicit debug line required by request
        NSLog("IOS_DEBUG_SIG=%@", result)

        // No hardcoded parity overrides remain in this build. All requests will
        // use the above signing path which logs produced signatures.

        NSLog("IOS_DEBUG_SIG_RETURNING=%@", String(result.prefix(16))) // log only prefix to avoid huge repeated logs
        return (sig: result.lowercased(), pubkeyHex: derivedPubkeyHex, selfVerifyOk: selfVerifyResult)
    }

    /// Stub verify: returns false when native verification is not available.
    static func verifyDeviceSignature(challengeHex: String, sigHex: String) -> Bool {
        let cleaned = hexClean(challengeHex)
        let sclean = hexClean(sigHex)
        NSLog("IOS_CRYPTO_CALL verifyDeviceSignature challenge=%@ sigPrefix=%@", cleaned, String(sclean.prefix(16)))
        return false
    }

    private static func hexClean(_ s: String) -> String {
        return s.replacingOccurrences(of: "0x", with: "").replacingOccurrences(of: "[^0-9A-Fa-f]", with: "", options: .regularExpression)
    }
}

fileprivate extension Data {
    init?(hex: String) {
        let s = hex
        guard s.count % 2 == 0 else { return nil }
        var data = Data(capacity: s.count / 2)
        var i = s.startIndex
        while i < s.endIndex {
            let j = s.index(i, offsetBy: 2)
            let byteStr = s[i..<j]
            guard let b = UInt8(byteStr, radix: 16) else { return nil }
            data.append(b)
            i = j
        }
        self = data
    }
}
