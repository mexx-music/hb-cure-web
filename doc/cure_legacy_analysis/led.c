#define LOG_LOCAL_LEVEL ESP_LOG_ERROR

#include "led.h"
#include <math.h>
#include <stdint.h>

#include "sdkconfig.h"
#include "esp_system.h"
#include "esp_log.h"

#include "ledc_mod.h"
#include "types.h"

extern uint32_t CureDeviceType;

void led_update();

// don't change the numeric channel... the channel-to-pin-mapping is fixed because of the needed invertion of the logic level...
/*
#define LED_CHANNEL_B LEDC_CHANNEL_0
#define LED_CHANNEL_G LEDC_CHANNEL_1
#define LED_CHANNEL_R LEDC_CHANNEL_2
*/


#define LED_CHANNEL_B LEDC_CHANNEL_1
#define LED_CHANNEL_G LEDC_CHANNEL_2
#define LED_CHANNEL_R LEDC_CHANNEL_0

typedef enum {
	led_state_idle,
	led_state_error,
	led_state_advertising,
    led_state_locked,
	led_state_curing,
	led_state_off,
	led_state_invalid,

} led_states;

volatile led_states State=led_state_error;


void led_init() {
       ESP_LOGE("LED", "led_init\n");
       
     // Prepare and then apply the LEDC PWM timer configuration
    ledc_timer_config_t ledc_timer = {
        .speed_mode       = LEDC_LOW_SPEED_MODE,
        .timer_num        = LEDC_TIMER_2,
        .duty_resolution  = LEDC_TIMER_16_BIT,
        .freq_hz          = 1220,
        .clk_cfg          = LEDC_AUTO_CLK
    };
    ESP_ERROR_CHECK(ledc_timer_config(&ledc_timer));

    if (CureDeviceType!=CureDeviceType_CureBase) {
       ESP_LOGE("LED", "led_init CureDeviceType_CureClip\n");
        // Prepare and then apply the LEDC PWM channel configuration
        ledc_channel_config_t ledc_channel = {
            .speed_mode     = LEDC_LOW_SPEED_MODE,
            .channel        = LEDC_CHANNEL_0,
            .timer_sel      = LEDC_TIMER_2,
            .intr_type      = LEDC_INTR_DISABLE,
            .gpio_num       = 19,
            .duty           = 65536/2, // Set duty to 0%
            .hpoint         = 0,
            .flags.output_invert = 1
        };

        ESP_ERROR_CHECK(ledc_channel_config(&ledc_channel));
        ledc_channel.channel=LEDC_CHANNEL_2;
        ledc_channel.gpio_num=23;
        ledc_channel.duty=65536/4;

        ESP_ERROR_CHECK(ledc_channel_config(&ledc_channel));
        ledc_channel.channel=LEDC_CHANNEL_1;
        ledc_channel.gpio_num=18;
        ledc_channel.duty=65536/8;

        ESP_ERROR_CHECK(ledc_channel_config(&ledc_channel));
    } else {
        // Prepare and then apply the LEDC PWM channel configuration
        ledc_channel_config_t ledc_channel = {
            .speed_mode     = LEDC_LOW_SPEED_MODE,
            .channel        = LEDC_CHANNEL_0,
            .timer_sel      = LEDC_TIMER_2,
            .intr_type      = LEDC_INTR_DISABLE,
            .gpio_num       = 19,
            .duty           = 65536/2, // Set duty to 0%
            .hpoint         = 0,
            .flags.output_invert = 0
        };

        ESP_ERROR_CHECK(ledc_channel_config(&ledc_channel));
        ledc_channel.channel=LEDC_CHANNEL_1;
        ledc_channel.gpio_num=23;
        ledc_channel.duty=65536/4;

        ESP_ERROR_CHECK(ledc_channel_config(&ledc_channel));
        ledc_channel.channel=LEDC_CHANNEL_2;
        ledc_channel.gpio_num=18;
        ledc_channel.duty=65536/8;

        ESP_ERROR_CHECK(ledc_channel_config(&ledc_channel));

    }

  
    led_setError();
}

void led_setLocked() {
    ESP_LOGI("LED", "led_setLocked()\n");
	State=led_state_locked;
	led_update();
}

void led_setCuring() {
    ESP_LOGI("LED", "led_setCuring()\n");
	State=led_state_curing;
	led_update();
}

void led_setIdle() {
    ESP_LOGI("LED", "led_setIdle()\n");
	State=led_state_idle;
	led_update();
}

void led_setError() {
    ESP_LOGI("LED", "led_setError()\n");
	State=led_state_error;
	led_update();
}

void led_setAdvertising() {
    ESP_LOGI("LED", "led_setAdvertising()\n");

	State=led_state_advertising;
	led_update();
}

void led_off() {
    ESP_LOGI("LED", "led_off()\n");

	State=led_state_off;

    ledc_stop(LEDC_LOW_SPEED_MODE, LEDC_CHANNEL_0, 1);
    ledc_stop(LEDC_LOW_SPEED_MODE, LEDC_CHANNEL_1, 1);
    ledc_stop(LEDC_LOW_SPEED_MODE, LEDC_CHANNEL_2, 1);

    gpio_reset_pin(GPIO_NUM_23);
    gpio_set_direction(GPIO_NUM_23, GPIO_MODE_OUTPUT);
    gpio_set_level(GPIO_NUM_23, 0);

    gpio_reset_pin(GPIO_NUM_19);
    gpio_set_direction(GPIO_NUM_19, GPIO_MODE_OUTPUT);
    gpio_set_level(GPIO_NUM_19, 0);

    gpio_reset_pin(GPIO_NUM_18);
    gpio_set_direction(GPIO_NUM_18, GPIO_MODE_OUTPUT);
    gpio_set_level(GPIO_NUM_18, 0);


	led_update();

}
void led_update() {
    //empty... was used on NRF52 to update waveforms... on ESP32, this is done in a software task...
}

void LedTask(void *param) {
    static led_states old_state=led_state_invalid;
    static uint32_t frameCounter=0;

    ESP_LOGE("LED", "Entering LedTask\n");
    
    TickType_t xLastWakeTime;
    const TickType_t xFrequency = 10;
    xLastWakeTime = xTaskGetTickCount();

    while(1) {

        int state_changed=(old_state!=State);
        old_state=State;
        
        if (state_changed)
            frameCounter=0;
        
        const double overallIntensityScale=1.0;
        const float sinValue=(0.5+0.4999*sin((2.0*M_PI*(float)frameCounter)/(float)0xffffFFFF));
        
        const uint32_t frameIntensity=(~(uint32_t)((float)0xFFFF*overallIntensityScale*(sinValue*sinValue)))&0xffff;
        //const uint32_t frameIntensity=(~(uint32_t)(frameCounter>>16))&0xffff;
        
        const uint32_t fullIntensity=(~(uint32_t)((float)0xFFFF*overallIntensityScale))&0xffff;
        const uint32_t zeroIntensity=(~(uint32_t)(0))&0xffff;
        
        frameCounter+=0xffffFFFF/400; //10ms update-frequency gives 2sec duration (1period=2pulses)...

        
       //ESP_LOGE("LED", "STATE %d frameIntensity %4X sinValue %f\n",State,(unsigned int)frameIntensity, sinValue);

        switch (State) {
            case led_state_off:
                ledc_set_duty(LEDC_LOW_SPEED_MODE, LED_CHANNEL_R, zeroIntensity);
                ledc_set_duty(LEDC_LOW_SPEED_MODE, LED_CHANNEL_G, zeroIntensity);
                ledc_set_duty(LEDC_LOW_SPEED_MODE, LED_CHANNEL_B, zeroIntensity);
                break;

            case led_state_idle:
                ledc_set_duty(LEDC_LOW_SPEED_MODE, LED_CHANNEL_R, zeroIntensity);
                ledc_set_duty(LEDC_LOW_SPEED_MODE, LED_CHANNEL_G, fullIntensity);
                ledc_set_duty(LEDC_LOW_SPEED_MODE, LED_CHANNEL_B, zeroIntensity);
                break;

            case led_state_advertising:
                ledc_set_duty(LEDC_LOW_SPEED_MODE, LED_CHANNEL_R, zeroIntensity);
                ledc_set_duty(LEDC_LOW_SPEED_MODE, LED_CHANNEL_G, zeroIntensity);
                ledc_set_duty(LEDC_LOW_SPEED_MODE, LED_CHANNEL_B, fullIntensity);
                break;
                
            case led_state_curing:
                ledc_set_duty(LEDC_LOW_SPEED_MODE, LED_CHANNEL_R, zeroIntensity);
                ledc_set_duty(LEDC_LOW_SPEED_MODE, LED_CHANNEL_G, frameIntensity);
                ledc_set_duty(LEDC_LOW_SPEED_MODE, LED_CHANNEL_B, zeroIntensity);
                break;

            case led_state_locked:
                ledc_set_duty(LEDC_LOW_SPEED_MODE, LED_CHANNEL_R, zeroIntensity);
                ledc_set_duty(LEDC_LOW_SPEED_MODE, LED_CHANNEL_G, zeroIntensity);
                ledc_set_duty(LEDC_LOW_SPEED_MODE, LED_CHANNEL_B, frameIntensity);
                break;

            case led_state_error:
                ledc_set_duty(LEDC_LOW_SPEED_MODE, LED_CHANNEL_R, fullIntensity);
                ledc_set_duty(LEDC_LOW_SPEED_MODE, LED_CHANNEL_G, zeroIntensity);
                ledc_set_duty(LEDC_LOW_SPEED_MODE, LED_CHANNEL_B, zeroIntensity);
                break;
                
            default:
                ledc_set_duty(LEDC_LOW_SPEED_MODE, LED_CHANNEL_R, frameIntensity);
                ledc_set_duty(LEDC_LOW_SPEED_MODE, LED_CHANNEL_G, zeroIntensity);
                ledc_set_duty(LEDC_LOW_SPEED_MODE, LED_CHANNEL_B, zeroIntensity);
        }

        ledc_update_duty(LEDC_LOW_SPEED_MODE, LED_CHANNEL_R);
        ledc_update_duty(LEDC_LOW_SPEED_MODE, LED_CHANNEL_G);
        ledc_update_duty(LEDC_LOW_SPEED_MODE, LED_CHANNEL_B);

        vTaskDelayUntil( &xLastWakeTime, xFrequency );
    }
}

