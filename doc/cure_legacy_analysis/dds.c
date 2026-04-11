#include "dds.h"
#include "interpreter.h"

#define LOG_LOCAL_LEVEL ESP_LOG_VERBOSE

#include "sdkconfig.h"
#include "esp_system.h"
#include "esp_log.h"

#include "types.h"
#include <math.h>

extern uint32_t CureDeviceType;


volatile uint32_t Accumulators[numDDS];
volatile uint32_t Increments[numDDS];
uint8_t WaveTable[numDDS][256];

void DDS_start(int values, double *frequencies, double *amplitudes) {
    DDS_startEx(values, frequencies, amplitudes, WaveForm_Sine, WaveForm_Sine);
}

void DDS_startEx(int values, double *frequencies, double *amplitudes, int EFieldWaveForm, int HFieldWaveForm) {
    if (CureDeviceType!=CureDeviceType_CureBase)
        DDS_DAC_start(values, frequencies, amplitudes, EFieldWaveForm, HFieldWaveForm);
    else
        DDS_Timer_start(values, frequencies, amplitudes, EFieldWaveForm, HFieldWaveForm);
}

void DDS_stop() {
    if (CureDeviceType!=CureDeviceType_CureBase)
        DDS_DAC_stop();
    else
        DDS_Timer_stop();
}

void DDS_init() {
    if (CureDeviceType!=CureDeviceType_CureBase)
        DDS_DAC_init();
    else
        DDS_Timer_init();
}

void DDSTask(void *param) {
    ESP_LOGI("DDS", "Entering DDSTask\n");


    TickType_t LastWakeTime = xTaskGetTickCount();

    while(1) {
        TickType_t currentTime = xTaskGetTickCount();

        //we tell the interpreter when we called it the last time...
        int waittime=Interpreter_process( (currentTime-LastWakeTime)*portTICK_PERIOD_MS);
        LastWakeTime=currentTime;

        //update every second if we're waiting for some dwell-time.
        if (waittime>0)
            if (waittime>1000)
                vTaskDelay(1000 / portTICK_PERIOD_MS);
            else
                vTaskDelay(waittime);
        else
            vTaskDelay(100 / portTICK_PERIOD_MS); //wait 100 ticks at a minimum.
    }
}

void DDS_generateWaveTable(uint8_t *WaveTable, const double Amplitude, const int WaveForm, const int Bits) {
    const int TopValue=(1<<Bits);
    const double WaveFormAmplitude=(double)((TopValue/2)-1);
    const int WaveFormOffset=TopValue/2;

    ESP_LOGI("DDS", "WaveForm %d\n", WaveForm);
    ESP_LOGI("DDS", "Bits %d\n", Bits);
    ESP_LOGI("DDS", "Amplitude %g\n", Amplitude);


    if (WaveForm==WaveForm_Sine) {
        for (int j=0;j<TopValue;j++) {
            WaveTable[j]=(int8_t)WaveFormOffset+(int8_t)(Amplitude*WaveFormAmplitude*sin(2.0*M_PI*(double)j/(double)TopValue));
        }
    } else if (WaveForm==WaveForm_Triangle) {
        for (int j=0;j<TopValue/4;j++) {
            WaveTable[j]=(int8_t)WaveFormOffset+ (int8_t)(Amplitude*WaveFormAmplitude * (0.0+4.0*(double)j/(double)TopValue));
        }

        for (int j=TopValue/4;j<3*(TopValue/4);j++) {
            WaveTable[j]=(int8_t)WaveFormOffset+ (int8_t)(Amplitude*WaveFormAmplitude * (1.0-4.0*(double)(j-TopValue/4)/(double)TopValue));
        }

        for (int j=3*(TopValue/4);j<TopValue;j++) {
            WaveTable[j]=(int8_t)WaveFormOffset+ (int8_t)(Amplitude*WaveFormAmplitude * (-1.0+4.0*(double)(j-3*(TopValue/4))/(double)TopValue));
        }
    } else if (WaveForm==WaveForm_Rectangular) {
        for (int j=0;j<TopValue;j++) {
            WaveTable[j]=(int8_t)WaveFormOffset+(int8_t)(Amplitude*WaveFormAmplitude* ( (j<TopValue/2)?1.0:-1.0) );
        }
    } else if (WaveForm==WaveForm_SawTooth) {
        for (int j=0;j<(1<<Bits);j++) {
            WaveTable[j]=(int8_t)WaveFormOffset+(int8_t)(Amplitude*WaveFormAmplitude* ( -1.0+2.0*(double)j/(double)TopValue) );
        }
    } else {
        ESP_LOGE("DDS", "Unknown waveform %d\n", WaveForm);
        //todo: report problem!
    }

    ESP_LOGI("DDS", "WaveTable:\n");
    for (int j=0;j<(1<<Bits);j++) {
        ESP_LOGI("DDS", "\t[%d]=%d\n", j, WaveTable[j]);
    }
}
