#include "sdkconfig.h"
#include "esp_system.h"
#include "esp_log.h"

#include "driver/dac_continuous.h"
#include "esp_check.h"

#include "dds.h"
#include <math.h>

#define nullptr NULL

static const int ddsBits=8;
static const int shiftBits=32-ddsBits;

dac_continuous_handle_t dac_handle=nullptr;


static uint8_t DmaTempBuffer[2048];

static bool IRAM_ATTR  dac_on_convert_done_callback(dac_continuous_handle_t handle, const dac_event_data_t *event, void *user_data) {
    for (int i=0;i<1024;i++) {
        const uint8_t TableIndex0=((Accumulators[0])>>shiftBits);
        const uint8_t TableIndex1=((Accumulators[1])>>shiftBits);

        Accumulators[0]+=Increments[0];
        Accumulators[1]+=Increments[1];

        DmaTempBuffer[i*2+1]=WaveTable[0][TableIndex0];
        DmaTempBuffer[i*2+0]=WaveTable[1][TableIndex1];

    }

    size_t written;
    dac_continuous_write_asynchronously(dac_handle, event->buf, event->buf_size, DmaTempBuffer, 2048, &written);

    return false;
}

void DDS_DAC_start(int values, double *frequencies, double *amplitudes, int EFieldWaveForm, int HFieldWaveForm) {
    ESP_LOGE("DDS", "DDS_DAC_start ([%f,%f],[%f,%f])\n", frequencies[0], frequencies[1], amplitudes[0], amplitudes[1]);

    if (dac_handle!=nullptr) {
        DDS_DAC_stop();
    }

    const int intFrequency=fmax(20000, 10*fmax(frequencies[0], frequencies[1]));

    dac_continuous_config_t cont_cfg = {
        .chan_mask = DAC_CHANNEL_MASK_ALL,
        .desc_num = 6,
        .buf_size = 2048,
        .freq_hz = intFrequency/2, //why?
        .offset = 0,
        .clk_src = DAC_DIGI_CLK_SRC_APLL,   // Using APLL as clock source to get a wider frequency range
        .chan_mode = DAC_CHANNEL_MODE_ALTER,
    };
        ESP_LOGE("DDS", "intFrequency %d\n", intFrequency);

    ESP_ERROR_CHECK(dac_continuous_new_channels(&cont_cfg, &dac_handle));

    dac_event_callbacks_t  cbs  = {
        .on_convert_done = dac_on_convert_done_callback,
        .on_stop = NULL,
    };
    /* Must register the callback if using asynchronous writing */
    ESP_ERROR_CHECK(dac_continuous_register_event_callback(dac_handle, &cbs, NULL));

    DDS_generateWaveTable(WaveTable[0], amplitudes[0], EFieldWaveForm, ddsBits);
    DDS_generateWaveTable(WaveTable[1], amplitudes[1], HFieldWaveForm, ddsBits);

    ESP_ERROR_CHECK(dac_continuous_enable(dac_handle));
    ESP_ERROR_CHECK(dac_continuous_start_async_writing(dac_handle));
}

void DDS_DAC_stop() {
    ESP_LOGE("DDS", "DDS_DAC_stop ()\n");
    if (dac_handle!=nullptr) {
        ESP_ERROR_CHECK(dac_continuous_stop_async_writing(dac_handle));
        ESP_ERROR_CHECK(dac_continuous_disable(dac_handle));
        ESP_ERROR_CHECK(dac_continuous_del_channels(dac_handle));
        dac_handle=nullptr;
    }

    Increments[0]=0;
    Increments[1]=0;
    Accumulators[0]=0;
    Accumulators[1]=0;
}

void DDS_DAC_init() {
    ESP_LOGE("DDS", "DDS_DAC_init ()\n");
}
