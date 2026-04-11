typedef struct {
    uint8_t private_key_CureBase[32];
    uint8_t public_key_CureBase[64];
    uint8_t private_key_CureApp[32];
    uint8_t public_key_CureApp[64];
	uint8_t OTA_key[32];
	uint8_t OTA_iv[16];
} CureBaseKeys_t;
