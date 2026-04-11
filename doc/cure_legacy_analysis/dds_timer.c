#include "led.h"
#include "miniz.h"
#define LOG_LOCAL_LEVEL ESP_LOG_VERBOSE

/*
 * dds.c
 *
 *  Created on: 01.12.2020
 *      Author: hans
 */
#include <stdint.h>
#include "dds.h"

#include "sdkconfig.h"
#include "esp_system.h"
#include "esp_log.h"

#include "driver/periph_ctrl.h"
#include "driver/timer.h"
#include "esp_timer.h"
#include "ledc_mod.h"


#include <stdint.h>


#include "freertos/semphr.h"

#include "esp32/rom/gpio.h"
#include "soc/gpio_sig_map.h"

static const int intFrequency=100e3;
static const int ddsBits=6;
static const int shiftBits=32-ddsBits;

esp_timer_handle_t dds_timer;

static void IRAM_ATTR dds_timer_callback(void* arg) {
    const uint8_t TableIndex0=((Accumulators[0])>>shiftBits);
    const uint8_t TableIndex1=((Accumulators[1])>>shiftBits);

    Accumulators[0]+=Increments[0];
    Accumulators[1]+=Increments[1];

    ledc_mod_setDutyFromISR(LEDC_CHANNEL_0, WaveTable[0][TableIndex0]);
    ledc_mod_setDutyFromISR(LEDC_CHANNEL_1, WaveTable[1][TableIndex1]);
}


void DDS_Timer_start(int values, double *frequencies, double *amplitudes, int EFieldWaveForm, int HFieldWaveForm) {

    ESP_LOGI("DDS", "DDS_start\n");

    DDS_generateWaveTable(WaveTable[0], amplitudes[0], EFieldWaveForm, ddsBits);
    DDS_generateWaveTable(WaveTable[1], amplitudes[1], HFieldWaveForm, ddsBits);

    for (int i=0;i<values && i<numDDS; i++) {
        Increments[i]=(double)0xFFFFFFFF*(double)frequencies[i]/intFrequency;
        ESP_LOGW("DDS", "Frequency %X : %d\n", i, (unsigned int)frequencies[i]);
        ESP_LOGW("DDS", "Increment %X : %d\n", i, (unsigned int)Increments[i]);
        ESP_LOGW("DDS", "Amplitude: %lf\n", amplitudes[i]);
    }
}

void DDS_Timer_stop() {
    ESP_LOGI("DDS", "DDS_stop\n");

    Increments[0]=0;
    Increments[1]=0;
    Accumulators[0]=0;
    Accumulators[1]=0;

    ledc_set_duty(LEDC_HIGH_SPEED_MODE, LEDC_CHANNEL_0, (1<<ddsBits)/2);
    ledc_set_duty(LEDC_HIGH_SPEED_MODE, LEDC_CHANNEL_1, (1<<ddsBits)/2);
}

void DDS_Timer_init() {
    ESP_LOGI("DDS", "DDS_init\n");

    Increments[0]=0;
    Increments[1]=0;
    Accumulators[0]=0;
    Accumulators[1]=0;

    // Prepare and then apply the LEDC PWM timer configuration
    ledc_timer_config_t ledc_timer = {
        .speed_mode       = LEDC_HIGH_SPEED_MODE,
        .timer_num        = LEDC_TIMER_1,
        .duty_resolution  = LEDC_TIMER_6_BIT,
        .freq_hz          = 1250000,
        .clk_cfg          = LEDC_AUTO_CLK
    };
    ESP_ERROR_CHECK(ledc_timer_config(&ledc_timer));

    // Prepare and then apply the LEDC PWM channel configuration
    ledc_channel_config_t ledc_channel = {
        .speed_mode     = LEDC_HIGH_SPEED_MODE,
        .channel        = LEDC_CHANNEL_0,
        .timer_sel      = LEDC_TIMER_1,
        .intr_type      = LEDC_INTR_DISABLE,
        .gpio_num       = 27,
        .duty           = (1<<ddsBits)/2,
        .hpoint         = 0
    };

    ESP_ERROR_CHECK(ledc_channel_config(&ledc_channel));
    ledc_channel.channel=LEDC_CHANNEL_1;
    ledc_channel.gpio_num=21;
    ESP_ERROR_CHECK(ledc_channel_config(&ledc_channel));

    gpio_set_direction(4, GPIO_MODE_OUTPUT);
    gpio_set_direction(22, GPIO_MODE_OUTPUT);

    ESP_ERROR_CHECK(ledc_set_duty(LEDC_HIGH_SPEED_MODE, LEDC_CHANNEL_0, (1<<ddsBits)/2));
    ESP_ERROR_CHECK(ledc_set_duty(LEDC_HIGH_SPEED_MODE, LEDC_CHANNEL_1, (1<<ddsBits)/2));
    //start timer after LEDC is initialized! Otherwise, the ISR will generate a PANIC!

    ledc_set_pin_inv(4, LEDC_HIGH_SPEED_MODE, LEDC_CHANNEL_0);
    ledc_set_pin_inv(22, LEDC_HIGH_SPEED_MODE, LEDC_CHANNEL_1);

    const esp_timer_create_args_t dds_timer_args = {
            .callback = &dds_timer_callback,
            .name = "DDS"
    };

    ESP_ERROR_CHECK(esp_timer_create(&dds_timer_args, &dds_timer));

    const int timerTicks=(1e6/intFrequency);
    ESP_ERROR_CHECK(esp_timer_start_periodic(dds_timer, timerTicks));

	DDS_stop();


/*
    double f[2];
    double a[2];
    f[0]=.5;
    f[1]=1;
    a[0]=1.0;
    a[1]=0.5;
    DDS_start(2, f, a);
*/

}
