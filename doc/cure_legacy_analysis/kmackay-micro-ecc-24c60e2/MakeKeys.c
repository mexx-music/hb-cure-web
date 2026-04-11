/* Copyright 2014, Kenneth MacKay. Licensed under the BSD 2-clause license. */

#include "uECC.h"

#include <stdio.h>
#include <string.h>

#include "CureBaseKeys.h"
#include <openssl/rand.h>

int main() {
    uECC_Curve curve=uECC_secp256k1();

    int i, c;
    const int privKeySize=uECC_curve_private_key_size(curve);
    const int pubKeySize=uECC_curve_public_key_size(curve);
    
    CureBaseKeys_t Keys[16];

    for (int key=0;key<16;key++) {
        for (int i=0;i< privKeySize;i++) {
            Keys[key].private_key_CureBase[i]=0;
            Keys[key].private_key_CureApp[i]=0;
        }
        
        for (int i=0;i< pubKeySize;i++) {
            Keys[key].public_key_CureBase[i]=0;
            Keys[key].public_key_CureApp[i]=0;
        }

        
        if (!uECC_make_key(Keys[key].public_key_CureBase, Keys[key].private_key_CureBase, curve)) {
            printf("uECC_make_key() failed\n");
            return 1;
        }

        if (!uECC_make_key(Keys[key].public_key_CureApp, Keys[key].private_key_CureApp, curve)) {
            printf("uECC_make_key() failed\n");
            return 1;
        }
        
        if (!RAND_bytes(Keys[key].OTA_key, 32)) {
            printf("RAND_bytes() failed\n");
            return 1;
        }

        if (!RAND_bytes(Keys[key].OTA_iv, 16)) {
            printf("RAND_bytes() failed\n");
            return 1;
        }
    }
    
    printf("CureBaseKeys_t Keys[16]= {\n");
    for (int key=0;key<16;key++) {

        printf("\t\t{\n");
        printf("#ifdef IS_CURE_APP\n");
        
       printf("\t\t\t.public_key_CureBase={");
        for (int i=0;i<pubKeySize;i++) {
            printf("0x%0.2X",Keys[key].public_key_CureBase[i]);
            if (i<pubKeySize-1)
                printf(", ");
        }
        printf("},\n");
        
                printf("\t\t\t.private_key_CureApp={");
        for (int i=0;i<privKeySize;i++) {
            printf("0x%0.2X",Keys[key].private_key_CureApp[i]);
            if (i<privKeySize-1)
                printf(", ");
        }
        printf("}\n");

        printf("#endif\n");
        printf("#ifdef IS_CURE_BASE\n");
        
        printf("\t\t\t.private_key_CureBase={");
        for (int i=0;i<privKeySize;i++) {
            printf("0x%0.2X",Keys[key].private_key_CureBase[i]);
            if (i<privKeySize-1)
                printf(", ");
        }
        printf("},\n");
        
        
        printf("\t\t\t.public_key_CureApp={");
        for (int i=0;i<pubKeySize;i++) {
            printf("0x%0.2X",Keys[key].public_key_CureApp[i]);
            if (i<pubKeySize-1)
                printf(", ");
        }
        printf("},\n");
        
                printf("\t\t\t.OTA_key={");
        for (int i=0;i<32;i++) {
            printf("0x%0.2X",Keys[key].OTA_key[i]);
            if (i<31)
                printf(", ");
        }
        printf("},\n");
        
                printf("\t\t\t.OTA_iv={");
        for (int i=0;i<16;i++) {
            printf("0x%0.2X",Keys[key].OTA_iv[i]);
            if (i<15)
                printf(", ");
        }
        printf("}\n");

        printf("#endif\n");

        if (key<15)
            printf("\t\t},\n");
        else
            printf("\t\t}\n");

    }
    printf("    };\n");



/*
        uint8_t hash[32] = {0};
        uint8_t sig[64] = {0};


        if (!uECC_make_key(public, private, curve)) {
            printf("uECC_make_key() failed\n");
            return 1;
        }
            
    printf("uint8_t private_key[%d]={", privKeySize);
    for (int i=0;i<privKeySize;i++) {
        printf("0x%0.2X",private[i]);
        if (i<31)
            printf(", ");
    }

    printf("};\n");
    
    printf("uint8_t public_key[%d]={", pubKeySize);
    for (int i=0;i<pubKeySize;i++) {
        printf("0x%0.2X",public[i]);
        if (i<63)
            printf(", ");
    }

    printf("};\n");
    
    for (int i=0;i<32;i++) {
        hash[i]=rand();
    }

    uECC_sign(private,hash,32,sig,curve);

    if (!uECC_verify(public,hash,32,sig,curve)) {
        printf("Local Verify Failed!");
    } else {
        printf("Local Verify OK!");
    }
                
*/
    
    return 0;
}
