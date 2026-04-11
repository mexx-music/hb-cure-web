#include "rand.h"
#include "limits.h"

#include "esp_system.h"
#include "esp_random.h"

int GetRandomData(uint8_t *block, unsigned int len) {
    esp_fill_random(block,len);
    return 1;
}

int AvailableRandomData() {
    return INT_MAX;
}
