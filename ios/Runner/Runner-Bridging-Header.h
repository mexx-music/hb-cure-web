#import "GeneratedPluginRegistrant.h"

// Conditionally include secp256k1 headers if available. This avoids a hard failure during header scanning
// when the native secp256k1 C headers aren't installed (via CocoaPods/SPM). If you see the fallback message
// in the build output, install secp256k1 via CocoaPods or Swift Package Manager and set Header Search Paths.
#if __has_include(<secp256k1/secp256k1.h>)
#include <secp256k1/secp256k1.h>
#elif __has_include("secp256k1.h")
#include "secp256k1.h"
#else
// secp256k1 headers not found at build-time. To fix:
// 1) Add the secp256k1 dependency to your iOS project (recommended):
//    - CocoaPods: add `pod 'secp256k1', :modular_headers => true` to ios/Podfile and run `pod install`.
//    - OR Swift Package: add https://github.com/21-DOT-DEV/swift-secp256k1 as Package Dependency.
// 2) Ensure the header search path includes the secp256k1 include directory (e.g. $(PODS_ROOT)/secp256k1/include).
// For now, define minimal dummy types so the bridging header can be parsed; if secp256k1 is missing at link
// time you will still need to install the library.

typedef struct secp256k1_context_struct secp256k1_context;
struct secp256k1_ecdsa_signature { unsigned char data[64]; };

// Forward prototypes used by CureCryptoIos.swift (no-op stubs will be linked only if library present):
extern secp256k1_context *secp256k1_context_create(unsigned int flags);
extern void secp256k1_context_destroy(secp256k1_context *ctx);
extern int secp256k1_ec_seckey_verify(const secp256k1_context *ctx, const unsigned char *seckey);
extern int secp256k1_ecdsa_sign(const secp256k1_context *ctx, struct secp256k1_ecdsa_signature *sig, const unsigned char *msg32, const unsigned char *seckey, void *noncefp, void *ndata);
extern int secp256k1_ecdsa_signature_serialize_compact(const secp256k1_context *ctx, unsigned char *out64, const struct secp256k1_ecdsa_signature *sig);

#endif
