import Foundation
import P256K

enum CureCryptoError: Error {
    case invalidLength
    case invalidHex
    case signFailed
}

final class CureCryptoIos {
    private static let privHex = "E40783F681A5BB852CAB1E106B6641EFB43C1923C1EBE25CA36865CDFAB06548"
    private static let pubHex  = "84993D74CACCB0901406255ECE4295E727A3D670918DDEA4246BBEF89FBB7BD94EE1A8EDA4C0379309D9681BFE3D332E4815786B89F8F1F0F7F57DABED608116"

    // hex cleaning like Kotlin: keep only 0-9a-fA-F
    private static func hexClean(_ s: String) -> String {
        s.filter { "0123456789abcdefABCDEF".contains($0) }
    }

    private static func hexToData(_ s: String) -> Data? {
        let cleaned = hexClean(s)
        guard cleaned.count % 2 == 0 else { return nil }
        var out = Data(capacity: cleaned.count / 2)
        var i = cleaned.startIndex
        while i < cleaned.endIndex {
            let j = cleaned.index(i, offsetBy: 2)
            guard let b = UInt8(cleaned[i..<j], radix: 16) else { return nil }
            out.append(b)
            i = j
        }
        return out
    }

    private static func dataToHexLower(_ d: Data) -> String {
        d.map { String(format: "%02x", $0) }.joined()
    }

    /// Returns 128-char hex (64 bytes: r||s), lowercase
    static func buildUnlockResponse(challengeHex: String) throws -> String {
        guard let msg = hexToData(challengeHex), msg.count == 32 else { throw CureCryptoError.invalidLength }
        guard let priv = hexToData(privHex), priv.count == 32 else { throw CureCryptoError.invalidLength }

        // P256K expects message bytes (no hashing here!)
        let sk = try P256K.Signing.PrivateKey(derRepresentation: priv)

        // Sign without hashing: use "signature(for: Data)" if it doesn't hash.
        // In this library, signature is computed over the provided bytes (secp256k1 lib style).
        let sig = try sk.signature(for: msg)

        // Try to get compact 64 bytes directly (preferred).
        // Preferred: try to get compact 64-byte representation directly
        let compact = try sig.compact64()
        return dataToHexLower(compact)
    }

    static func verifyDeviceSignature(challengeHex: String, sigHex: String) -> Bool {
        guard let msg = hexToData(challengeHex), msg.count == 32 else { return false }
        guard let sig64 = hexToData(sigHex), sig64.count == 64 else { return false }
        guard let pubXY = hexToData(pubHex), pubXY.count == 64 else { return false }

        do {
            // Build uncompressed pubkey (0x04 + x + y)
            var uncompressed = Data([0x04])
            uncompressed.append(pubXY)
            // Try x963Representation (common name for uncompressed EC point representation)
            let pk = try P256K.Signing.PublicKey(x963Representation: uncompressed)

            // Build signature from compact64
            let sig = try P256K.Signing.ECDSASignature(compactRepresentation: sig64)

            return pk.isValidSignature(sig, for: msg)
        } catch {
            return false
        }
    }

    // MARK: - DER -> compact(64) helper (minimal ASN.1)
    private static func derToCompact64(_ der: Data) throws -> Data {
        // Very small ASN.1 parser for ECDSA signature:
        // SEQUENCE { INTEGER r; INTEGER s }
        var idx = 0
        func readByte() throws -> UInt8 {
            guard idx < der.count else { throw CureCryptoError.signFailed }
            let b = der[idx]
            idx += 1
            return b
        }
        func readLen() throws -> Int {
            let first = try readByte()
            if first < 0x80 { return Int(first) }
            let n = Int(first & 0x7F)
            guard n > 0 && n <= 2 else { throw CureCryptoError.signFailed }
            var val = 0
            for _ in 0..<n {
                val = (val << 8) | Int(try readByte())
            }
            return val
        }
        func readInt() throws -> Data {
            let tag = try readByte()
            guard tag == 0x02 else { throw CureCryptoError.signFailed }
            let len = try readLen()
            guard idx + len <= der.count else { throw CureCryptoError.signFailed }
            let v = der.subdata(in: idx..<(idx+len))
            idx += len
            return v
        }

        let seqTag = try readByte()
        guard seqTag == 0x30 else { throw CureCryptoError.signFailed }
        _ = try readLen()

        var r = try readInt()
        var s = try readInt()

        // strip leading 0x00 if present
        if r.count > 0 && r.first == 0x00 { r = r.dropFirst() }
        if s.count > 0 && s.first == 0x00 { s = s.dropFirst() }

        func leftPad32(_ d: Data) -> Data {
            if d.count == 32 { return d }
            if d.count > 32 { return d.suffix(32) }
            return Data(repeating: 0, count: 32 - d.count) + d
        }

        let out = leftPad32(r) + leftPad32(s)
        guard out.count == 64 else { throw CureCryptoError.signFailed }
        return out
    }
}

private extension P256K.Signing.ECDSASignature {
    // Unified helper: return compact 64-byte (r||s) representation or throw.
    func compact64() throws -> Data {
        return try self.compactRepresentation
    }
}
