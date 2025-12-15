// filepath: tools/sign_challenge.cpp
// Kleine Konsolen-Hilfe zum Signieren / Verifizieren von 32-Byte-Challenges
// gegen die CureBase-Schlüssel (secp256k1 / micro-ecc).
//
// Verwendung:
//   ./sign_challenge sign <64-hex-challenge>
//     -> schreibt 128-hex (r||s)
//   ./sign_challenge verify <64-hex-challenge> <128-hex-signature>
//     -> schreibt OK (stdout) oder FAIL (stdout)
//
// WICHTIG:
// - Ersetze die Platzhalter-Keys `privHex` und `pubHex` weiter unten mit den
//   echten Bytes aus dem alten CureApp/CureBase-Repo (private_key_CureApp und
//   public_key_CureBase). Die private key ist 32 Bytes (64 hex chars). Die
//   public key ist 64 Bytes (128 hex chars) in unkomprimiertem x||y Format.
// - Die Signatur wird genau so erzeugt wie in der Qt-App: aktuell signieren
//   wir die 32 Byte Challenge direkt (ohne weiteres Hashing) mit uECC_sign().
//   Falls die alte App zuerst SHA-256 gehasht hat, passe die Zeile an
//   (Kommentar im Code zeigt wo).

#include <cstdio>
#include <cstring>
#include <iostream>
#include <string>
#include <vector>
#include <algorithm>
#include <cctype>

extern "C" {
#include "uECC.h"
}

static void hex_to_bytes(const std::string &hex, std::vector<uint8_t> &out) {
    out.clear();
    out.reserve(hex.size() / 2);
    for (size_t i = 0; i + 1 < hex.size(); i += 2) {
        unsigned int byte = 0;
        // sscanf is convenient but locale-safe parsing is fine here since only 0-9a-fA-F expected
        if (sscanf(hex.substr(i, 2).c_str(), "%02x", &byte) != 1) {
            out.clear();
            return;
        }
        out.push_back((uint8_t)byte);
    }
}

static std::string bytes_to_hex(const uint8_t *data, size_t len) {
    static const char *hexchars = "0123456789abcdef";
    std::string s;
    s.resize(len * 2);
    for (size_t i = 0; i < len; ++i) {
        s[2*i] = hexchars[(data[i] >> 4) & 0xF];
        s[2*i+1] = hexchars[data[i] & 0xF];
    }
    return s;
}

static std::string normalize_hex(const std::string &in) {
    std::string out;
    out.reserve(in.size());
    for (char c : in) {
        if (!std::isspace((unsigned char)c)) out.push_back(c);
    }
    return out;
}

int cmd_sign(const std::string &hexChallenge) {
    std::string cleaned = normalize_hex(hexChallenge);
    if (cleaned.size() != 64) {
        std::fprintf(stderr, "Expected 64 hex chars (32 bytes) challenge, got %zu chars\n", cleaned.size());
        return 3;
    }
    std::vector<uint8_t> challenge;
    hex_to_bytes(cleaned, challenge);
    if (challenge.size() != 32) {
        std::fprintf(stderr, "Parsed challenge size != 32 bytes\n");
        return 4;
    }

    // TODO: Replace the following placeholder private key with the real
    // `private_key_CureApp` bytes (32 bytes / 64 hex chars) from the old repo.
    const char *privHex = "E40783F681A5BB852CAB1E106B6641EFB43C1923C1EBE25CA36865CDFAB06548";
    std::vector<uint8_t> priv;
    hex_to_bytes(std::string(privHex), priv);
    if (priv.size() != 32) {
        std::fprintf(stderr, "Private key not 32 bytes - please replace privHex in the source with the real key.\n");
        return 5;
    }

    const struct uECC_Curve_t * curve = uECC_secp256k1();
    uint8_t signature[64];
    memset(signature, 0, sizeof(signature));

    // IMPORTANT: The legacy Qt app signs the raw 32-byte challenge directly
    // with uECC_sign(). If the old code hashed the challenge first (SHA-256),
    // you must hash here instead and pass the hash to uECC_sign.
    // Example (not active):
    //   uint8_t hash[32];
    //   sha256(challenge.data(), challenge.size(), hash);
    //   uECC_sign(priv.data(), hash, 32, signature, curve);

    int ok = uECC_sign(priv.data(), challenge.data(), (unsigned)challenge.size(), signature, curve);
    if (!ok) {
        std::fprintf(stderr, "uECC_sign failed\n");
        return 6;
    }

    std::string sighex = bytes_to_hex(signature, sizeof(signature));
    std::cout << sighex << std::endl;
    return 0;
}

int cmd_verify(const std::string &hexChallenge, const std::string &hexSignature) {
    std::string cleanedC = normalize_hex(hexChallenge);
    std::string cleanedS = normalize_hex(hexSignature);
    if (cleanedC.size() != 64) {
        std::fprintf(stderr, "Expected 64 hex chars (32 bytes) challenge, got %zu\n", cleanedC.size());
        return 3;
    }
    if (cleanedS.size() != 128) {
        std::fprintf(stderr, "Expected 128 hex chars (64 bytes) signature (r||s), got %zu\n", cleanedS.size());
        return 4;
    }
    std::vector<uint8_t> challenge;
    std::vector<uint8_t> sig;
    hex_to_bytes(cleanedC, challenge);
    hex_to_bytes(cleanedS, sig);
    if (challenge.size() != 32 || sig.size() != 64) {
        std::fprintf(stderr, "Parsed sizes wrong\n");
        return 5;
    }

    // TODO: Replace the following placeholder public key with the real
    // `public_key_CureBase` bytes (64 bytes / 128 hex chars) from the old repo.
    const char *pubHex =
        "84993D74CACCB0901406255ECE4295E727A3D670918DDEA4246BBEF89FBB7BD9"
        "4EE1A8EDA4C0379309D9681BFE3D332E4815786B89F8F1F0F7F57DABED608116";
    std::vector<uint8_t> pub;
    hex_to_bytes(std::string(pubHex), pub);
    if (pub.size() != 64) {
        std::fprintf(stderr, "Public key not 64 bytes - please replace pubHex in the source with the real key.\n");
        return 6;
    }

    const struct uECC_Curve_t * curve = uECC_secp256k1();

    int ok = uECC_verify(pub.data(), challenge.data(), (unsigned)challenge.size(), sig.data(), curve);
    if (ok) {
        std::cout << "OK" << std::endl;
        return 0;
    } else {
        std::cout << "FAIL" << std::endl;
        return 1;
    }
}

int main(int argc, char **argv) {
    if (argc < 2) {
        std::fprintf(stderr, "Usage:\n  %s sign <64hex-challenge>\n  %s verify <64hex-challenge> <128hex-signature>\n", argv[0], argv[0]);
        return 2;
    }
    std::string cmd = argv[1];
    if (cmd == "sign") {
        if (argc < 3) {
            std::fprintf(stderr, "Usage: %s sign <64hex-challenge>\n", argv[0]);
            return 2;
        }
        return cmd_sign(argv[2]);
    } else if (cmd == "verify") {
        if (argc < 4) {
            std::fprintf(stderr, "Usage: %s verify <64hex-challenge> <128hex-signature>\n", argv[0]);
            return 2;
        }
        return cmd_verify(argv[2], argv[3]);
    } else {
        std::fprintf(stderr, "Unknown command '%s'\n", cmd.c_str());
        return 2;
    }
}
