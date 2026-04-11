#define LOG_LOCAL_LEVEL ESP_LOG_VERBOSE

#include "types.h"
#include <inttypes.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "sdkconfig.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_system.h"
#include "esp_mac.h"

#include "esp_spi_flash.h"

#include "esp_log.h"

#include "esp_bt.h"
#include "esp_bt_device.h"
//#include "bta_api.h"

#include "esp_gap_ble_api.h"
#include "esp_gatts_api.h"
#include "esp_bt_defs.h"
#include "esp_bt_main.h"
#include "ble_uart_server.h"
#include "nvs_flash.h"
#define GATTS_TAG "MAIN"


#include "driver/gpio.h"

#include "comm.h"
#include "dds.h"
#include "led.h"
#include "interpreter.h"

#include "esp_sleep.h"
#include "driver/rtc_io.h"
#include "soc/rtc.h"
#include "esp_task_wdt.h"

#include "esp_adc/adc_oneshot.h"
#include "esp_adc/adc_cali.h"
#include "esp_adc/adc_cali_scheme.h"

#include "esp_pm.h"




SemaphoreHandle_t BluetoothTxSemaphore=NULL;
SemaphoreHandle_t BluetoothBatTxSemaphore=NULL;
SemaphoreHandle_t BluetoothTxConfirmationEventSemaphore=NULL;
SemaphoreHandle_t BluetoothBatTxConfirmationEventSemaphore=NULL;

esp_app_desc_t app_desc;

char HardwareRevisionString[17]="0.0";

//double BatVoltageFactor=0.00139251634125; //convert from raw values
double BatVoltageFactor=5.999999999999999;

bool CureFirmwareSupportsStoredCureProg;


uint32_t CureDeviceType;

nvs_handle_t NVS_Handle;


void getCureClipBatSoC();
bool isCharging; //is set in getCureClipBatSoC();

adc_oneshot_unit_handle_t adc2_handle;
adc_cali_handle_t Adc2CalibrationHandle;

static bool example_adc_calibration_init(adc_unit_t unit, adc_channel_t channel, adc_atten_t atten, adc_bitwidth_t bitwidth, adc_cali_handle_t *out_handle)
{
    adc_cali_handle_t handle = NULL;
    esp_err_t ret = ESP_FAIL;
    bool calibrated = false;

#if ADC_CALI_SCHEME_CURVE_FITTING_SUPPORTED
    if (!calibrated) {
        ESP_LOGE(GATTS_TAG, "calibration scheme version is %s", "Curve Fitting");
        adc_cali_curve_fitting_config_t cali_config = {
            .unit_id = unit,
            .chan = channel,
            .atten = atten,
            .bitwidth = bitwidth,
        };
        ret = adc_cali_create_scheme_curve_fitting(&cali_config, &handle);
        if (ret == ESP_OK) {
            calibrated = true;
        }
    }
#endif

#if ADC_CALI_SCHEME_LINE_FITTING_SUPPORTED
    if (!calibrated) {
        ESP_LOGE(GATTS_TAG, "calibration scheme version is %s", "Line Fitting");
        adc_cali_line_fitting_config_t cali_config = {
            .unit_id = unit,
            .atten = atten,
            .bitwidth = bitwidth,
        };
        ret = adc_cali_create_scheme_line_fitting(&cali_config, &handle);
        if (ret == ESP_OK) {
            calibrated = true;
        }
    }
#endif

    *out_handle = handle;
    if (ret == ESP_OK) {
        ESP_LOGE(GATTS_TAG, "Calibration Success");
    } else if (ret == ESP_ERR_NOT_SUPPORTED || !calibrated) {
        ESP_LOGE(GATTS_TAG, "eFuse not burnt, skip software calibration");
    } else {
        ESP_LOGE(GATTS_TAG, "Invalid arg or no memory");
    }

    return calibrated;
}




void app_main(void) {

    esp_task_wdt_reset();
    esp_err_t ret;
    esp_task_wdt_add(xTaskGetCurrentTaskHandle());
    esp_task_wdt_reset();

    {
        esp_pm_config_esp32_t pm_config = {
            .max_freq_mhz = 160,
            .min_freq_mhz = 80,
            .light_sleep_enable = true //light-sleep != modem-sleep
        };
        ESP_ERROR_CHECK(esp_pm_configure(&pm_config));
    }


    CommMutex=xSemaphoreCreateMutex();

    BluetoothTxConfirmationEventSemaphore = xSemaphoreCreateBinary();
    BluetoothBatTxConfirmationEventSemaphore = xSemaphoreCreateBinary();

    BluetoothTxSemaphore=xSemaphoreCreateBinary();
    BluetoothBatTxSemaphore=xSemaphoreCreateBinary();

    xSemaphoreGive(BluetoothTxSemaphore);
    xSemaphoreGive(BluetoothBatTxSemaphore);

    RxQueueHandle=xQueueCreateStatic(1024,1,RxQueueBuffer,&RxQueue);

    CureDeviceType=0;

    PartitionInfoRunning=esp_ota_get_running_partition();
    PartitionInfoBooting=esp_ota_get_boot_partition();
    PartitionInfoOTA=esp_ota_get_next_update_partition(NULL);

    ESP_LOGE("BASE", "Running from %s\n", PartitionInfoRunning->label);
    ESP_LOGE("BASE", "Booting from %s\n", PartitionInfoBooting->label);
    ESP_LOGE("BASE", "Next update to %s\n", PartitionInfoOTA->label);

    memcpy(&app_desc, esp_ota_get_app_description(), sizeof(esp_app_desc_t) );

    ESP_LOGI("BASE", "app_desc.magic_word %X\n", (unsigned int)app_desc.magic_word);
    ESP_LOGI("BASE", "app_desc.secure_version %X\n", (unsigned int)app_desc.secure_version);
    ESP_LOGE("BASE", "app_desc.version %s\n", app_desc.version);
    ESP_LOGI("BASE", "app_desc.project_name %s\n", app_desc.project_name);
    ESP_LOGE("BASE", "app_desc.time %s\n", app_desc.time);
    ESP_LOGE("BASE", "app_desc.date %s\n", app_desc.date);
    ESP_LOGE("BASE", "app_desc.idf_ver %s\n", app_desc.idf_ver);

    printf("\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n");
    switch (esp_sleep_get_wakeup_cause()) {
        case ESP_SLEEP_WAKEUP_EXT0: {
            printf("Wake up from ext0\n");
            break;
        }
        case ESP_SLEEP_WAKEUP_EXT1: {
            uint64_t wakeup_pin_mask = esp_sleep_get_ext1_wakeup_status();
            if (wakeup_pin_mask != 0) {
                int pin = __builtin_ffsll(wakeup_pin_mask) - 1;
                printf("Wake up from GPIO %d\n", pin);
            } else {
                printf("Wake up from GPIO\n");
            }
            break;
        }
        case ESP_SLEEP_WAKEUP_UNDEFINED:
        default:
            printf("Not a deep sleep reset\n");
    }
    esp_task_wdt_reset();


    CureFirmwareSupportsStoredCureProg=false;

    Interpreter_init();

     
    esp_task_wdt_reset();
    ret=nvs_flash_init();
    esp_task_wdt_reset();

     nvs_iterator_t it = NULL;
    nvs_entry_find("nvs","factory", NVS_TYPE_ANY, &it);

printf("--- NVS KEYS START ---\n");

    esp_task_wdt_reset();
 while(it != NULL) {
     nvs_entry_info_t info;
     nvs_entry_info(it, &info); // Can omit error check if parameters are guaranteed to be non-NULL
     printf("key '%s', type '%d' \n", info.key, info.type);
     nvs_entry_next(&it);
     esp_task_wdt_reset();
 }
 nvs_release_iterator(it);
    esp_task_wdt_reset();

printf("--- NVS KEYS STOP ---\n");

     if (ret) {
        ESP_LOGE(GATTS_TAG, "nvs_flash_init failed with return code %d in app_main()\n", ret);
        while(1) {
            esp_task_wdt_reset();
            vTaskDelay(200 / portTICK_PERIOD_MS);

        }
        return;
    }
    

    esp_task_wdt_reset();
    ret = nvs_open("factory", NVS_READWRITE, &NVS_Handle);
    esp_task_wdt_reset();

    if (ret != ESP_OK) {
        ESP_LOGE(GATTS_TAG, "nvs_open failed with return code %d in app_main()\n", ret);
        while(1) {
            esp_task_wdt_reset();
            vTaskDelay(200 / portTICK_PERIOD_MS);
        }
        return;
    } else {
        size_t len=17;
    esp_task_wdt_reset();
        ret=nvs_get_str(NVS_Handle, "hwrev", HardwareRevisionString, &len);
    esp_task_wdt_reset();
        ESP_LOGE(GATTS_TAG, "nvs_get_str returned %d when reading hwrev\n", ret);

        if (ret != ESP_OK) {
            led_setError();
            while(1) {
                esp_task_wdt_reset();
                vTaskDelay(200 / portTICK_PERIOD_MS);
            }
            return;
        }
    }
    
    ESP_LOGE("BASE", "HW Revision %s\n", HardwareRevisionString);

    CureFirmwareSupportsStoredCureProg=false;
    CureDeviceType=CureDeviceType_CureBase;

    if ( (HardwareRevisionString[0]=='4') && (HardwareRevisionString[1]==0) ) {
        esp_task_wdt_reset();

        uint8_t tmp=0;
        ret=nvs_get_u8(NVS_Handle, "storeCureProg", &tmp);

        esp_task_wdt_reset();

        if (tmp==0)
            CureFirmwareSupportsStoredCureProg=false;
        else
            CureFirmwareSupportsStoredCureProg=true;

        if (ret != ESP_OK) {
            ESP_LOGE(GATTS_TAG, "nvs_get_str failed with return code %d in app_main()\n", ret);

            nvs_stats_t stats;
            ret=nvs_get_stats(NULL, &stats);
            ESP_LOGI(GATTS_TAG, "NV STATS:\nCount: UsedEntries = (%d), FreeEntries = (%d), AllEntries = (%d)\n",
            stats.used_entries, stats.free_entries, stats.total_entries);

            led_setError();
            while(1) {
                esp_task_wdt_reset();
                vTaskDelay(200 / portTICK_PERIOD_MS);
            }
            return;
        }

        esp_task_wdt_reset();
        ret=nvs_get_u32(NVS_Handle, "CureDeviceType", &CureDeviceType);
        esp_task_wdt_reset();

        if (ret != ESP_OK) {
            ESP_LOGE(GATTS_TAG, "nvs_get_str failed with return code %d in app_main()\n", ret);

            nvs_stats_t stats;
            ret=nvs_get_stats(NULL, &stats);
            ESP_LOGI(GATTS_TAG, "NV STATS:\nCount: UsedEntries = (%d), FreeEntries = (%d), AllEntries = (%d)\n",
            stats.used_entries, stats.free_entries, stats.total_entries);

            led_setError();
            while(1) {
                esp_task_wdt_reset();
                vTaskDelay(200 / portTICK_PERIOD_MS);
            }
            return;
        }

        esp_task_wdt_reset();
        ret=nvs_get_u64(NVS_Handle, "BatVtgFactor", (uint64_t *)&BatVoltageFactor);
        esp_task_wdt_reset();
        if (ret != ESP_OK) {
            ESP_LOGE(GATTS_TAG, "nvs_get_str failed with return code %d in app_main()\n", ret);

            nvs_stats_t stats;
            ret=nvs_get_stats(NULL, &stats);
            ESP_LOGI(GATTS_TAG, "NV STATS:\nCount: UsedEntries = (%d), FreeEntries = (%d), AllEntries = (%d)\n",
            stats.used_entries, stats.free_entries, stats.total_entries);

            led_setError();
            while(1) {
                esp_task_wdt_reset();
                vTaskDelay(200 / portTICK_PERIOD_MS);
            }
            return;
        }
    }

    if (CureFirmwareSupportsStoredCureProg) {
        esp_task_wdt_reset();
        loadCureProgFromNVS();
        esp_task_wdt_reset();
    }


    if ( (CureDeviceType==CureDeviceType_CureClip) || (CureDeviceType==CureDeviceType_VetClip) ){
        gpio_deep_sleep_hold_dis();

        //Vsense_EN
        gpio_reset_pin(GPIO_NUM_4);
        gpio_set_direction(GPIO_NUM_4, GPIO_MODE_OUTPUT);
        gpio_set_level(GPIO_NUM_4, 0);

        gpio_hold_dis(GPIO_NUM_4);//BAT_SENSE_EN

        gpio_reset_pin(GPIO_NUM_34);
        gpio_set_direction(GPIO_NUM_34, GPIO_MODE_INPUT);

        gpio_hold_dis(GPIO_NUM_23);//B
        gpio_hold_dis(GPIO_NUM_19);//R
        gpio_hold_dis(GPIO_NUM_18);//G

      //  gpio_hold_dis(GPIO_NUM_22);//H_N
     //  gpio_hold_dis(GPIO_NUM_21);//H_P

      //  gpio_hold_dis(GPIO_NUM_4);//H_N
      //  gpio_hold_dis(GPIO_NUM_12);//H_P

        adc_oneshot_unit_init_cfg_t init_config2 = {.unit_id = ADC_UNIT_2, .ulp_mode = ADC_ULP_MODE_DISABLE,};
        ESP_ERROR_CHECK(adc_oneshot_new_unit(&init_config2, &adc2_handle));
        adc_oneshot_chan_cfg_t config = {.bitwidth = ADC_BITWIDTH_12,.atten = ADC_ATTEN_DB_0,};
        ESP_ERROR_CHECK(adc_oneshot_config_channel(adc2_handle, ADC_CHANNEL_7, &config));

        example_adc_calibration_init(ADC_UNIT_2, ADC_CHANNEL_7, ADC_ATTEN_DB_0, ADC_BITWIDTH_12, &Adc2CalibrationHandle);

        esp_task_wdt_reset();
        getCureClipBatSoC();
    }

    led_init();

    TaskHandle_t xLEDTaskHandle = NULL;
    xTaskCreate(LedTask, "LedTask", 10240, NULL, configMAX_PRIORITIES-1, &xLEDTaskHandle);
    configASSERT( xLEDTaskHandle );

    DDS_init();

    //don't do this for CureBase! ADC2_CHANNEL_7 is E_P output!
    //getCureClipBatSoC();

    esp_bt_controller_config_t bt_cfg = BT_CONTROLLER_INIT_CONFIG_DEFAULT();

    ret = esp_bt_controller_init(&bt_cfg);
    if (ret) {
        ESP_LOGE(GATTS_TAG, "%s initialize controller failed\n", __func__);
        vTaskDelay(200 / portTICK_PERIOD_MS);
        return;
    }

    ret = esp_bt_controller_enable(bt_cfg.mode);
    if (ret) {
        ESP_LOGE(GATTS_TAG, "%s enable controller failed\n", __func__);
        vTaskDelay(200 / portTICK_PERIOD_MS);
        return;
    }


    ret = esp_bluedroid_init();
    if (ret) {
        ESP_LOGE(GATTS_TAG, "%s init bluetooth failed\n", __func__);
        vTaskDelay(200 / portTICK_PERIOD_MS);
        return;
    }
    ret = esp_bluedroid_enable();
    if (ret) {
        ESP_LOGE(GATTS_TAG, "%s enable bluetooth failed\n", __func__);
        vTaskDelay(200 / portTICK_PERIOD_MS);
        return;
    }

    esp_task_wdt_reset();

    uint8_t mac[6];
    esp_base_mac_addr_get(mac);

    switch (CureDeviceType) {
        case CureDeviceType_CureBase:
            sprintf(BLE_DEVICE_NAME, "CureBase-");
            break;
        case CureDeviceType_CureClip:
            sprintf(BLE_DEVICE_NAME, "CureClip-");
            getCureClipBatSoC();
            break;
        case CureDeviceType_VetClip:
            sprintf(BLE_DEVICE_NAME, "VetClip-");
            getCureClipBatSoC();
            break;
        default:
            sprintf(BLE_DEVICE_NAME, "CureDevice-");
    }

    const char dec2hex[]="0123456789ABCDEF";
    for (int i=0;i<6;i++) {
        uint8_t byte=mac[i];
        unsigned char high=dec2hex[byte>>4];
        unsigned char low=dec2hex[byte&0x0f];
        char part[]={high, low, 0};
        strcat (BLE_DEVICE_NAME,part);
    }
    
    ESP_LOGE("BASE", "Advertising as %s\n", BLE_DEVICE_NAME);

    esp_ble_gatts_register_callback(gatts_event_handler);
    esp_ble_gap_register_callback(gap_event_handler);
    esp_ble_gatts_app_register(BLE_PROFILE_APP_ID);
   
    TaskHandle_t xCommRxTaskHandle = NULL;
    xTaskCreate(CommRxTask, "CommRxTask", 10240, NULL, tskIDLE_PRIORITY+1, &xCommRxTaskHandle);
    configASSERT( xCommRxTaskHandle );

    TaskHandle_t xDDSTaskHandle = NULL;
    xTaskCreate(DDSTask, "DDSTask", 10240, NULL, configMAX_PRIORITIES/2, &xDDSTaskHandle);
    configASSERT( xDDSTaskHandle );
    
    gpio_reset_pin(GPIO_NUM_35);
    gpio_pullup_en(GPIO_NUM_35);
    gpio_set_direction(GPIO_NUM_35, GPIO_MODE_INPUT);

    unsigned int idleCounter=0;
    unsigned int Counter=0;

    ESP_LOGE("BASE", "Enter Idle Loop...");
/*
    double f[2];
    double a[2];
    f[0]=1;
    f[1]=5;
    a[0]=1.0;
    a[1]=1.0;
    DDS_DAC_start(2, f,a);
*/

    if (CureDeviceType==CureDeviceType_CureBase) {
        while (1) {
            esp_task_wdt_reset();
            ESP_LOGE("BASE", ".");
            ESP_LOGE("BASE", "%d: - RAM left %lu", __LINE__, esp_get_free_heap_size());

            vTaskDelay(500 / portTICK_PERIOD_MS);
        }
    } else {
        while (1) {
            if (Interpreter_isRunning())
                idleCounter=0;

            isCharging=(gpio_get_level(GPIO_NUM_34)==0);
/* power down even under charging. Since we do not update the advertised SOC, it is more intitive to power down
            if (isCharging)
                idleCounter=0;
*/
            vTaskDelay(100 / portTICK_PERIOD_MS);
            esp_task_wdt_reset();

            Counter++;
            if (gpio_get_level(GPIO_NUM_35)==0) {
                idleCounter=0;

                int i=0;
                for (i=0;i<10;i++) {
                    vTaskDelay(100 / portTICK_PERIOD_MS);
                    esp_task_wdt_reset();

                    if (gpio_get_level(GPIO_NUM_35)==1)
                        break;
                }

                if (i<5) {
                    ESP_LOGE("BASE", "short press");
                    if (Interpreter_isRunning()) {
                        if (Interpreter_isPaused()) {
                            Interpreter_resume();
                        } else {
                            Interpreter_pause();
                        }
                    }

                } else {
                    ESP_LOGE("BASE", "long press");
                    if (!Interpreter_isRunning()) {
                        Interpreter_start();
                    } else {
                        Interpreter_stop();
                    }
                }

                while (gpio_get_level(GPIO_NUM_35)==0) {
                    vTaskDelay(100 / portTICK_PERIOD_MS);
                    esp_task_wdt_reset();
                }
            }

            if ( (Counter>=300) || ((gpio_get_level(GPIO_NUM_27)==0)!=isCharging) ) { //check SoC every 30s or when charging pin changes..
                Counter=0;
                getCureClipBatSoC();
            }


            idleCounter++;
            //after 60s of idle, we power down...


            if (isCurebaseUnlocked())
            idleCounter=0;

            if (idleCounter>600) {

            ESP_LOGI("BASE", "deep-sleep!");
            {
            esp_pm_config_esp32_t pm_config = {
            .max_freq_mhz = 160,
            .min_freq_mhz = 160,
            .light_sleep_enable = false
            };
            ESP_ERROR_CHECK(esp_pm_configure(&pm_config));
            }

            esp_ble_gatts_app_unregister(BLE_PROFILE_APP_ID);
            esp_ble_gap_stop_advertising();
            esp_bluedroid_disable();
            esp_bt_controller_disable();
            vTaskDelay(200 / portTICK_PERIOD_MS); //just give the LED-task some time to really shut down the LEDs

            const int ext_wakeup_pin_2 = 35; //!Button
            //const int ext_wakeup_pin_3 = 34; //!Charge signal

            const uint64_t ext_wakeup_pin_2_mask = 1ULL << ext_wakeup_pin_2;
           // const uint64_t ext_wakeup_pin_3_mask = 1ULL << ext_wakeup_pin_3;

            //needed... some driver sets some wakeup-source. so wakeup happens without button press...
            esp_sleep_disable_wakeup_source(ESP_SLEEP_WAKEUP_ALL);
            ESP_ERROR_CHECK(esp_sleep_enable_ext1_wakeup(ext_wakeup_pin_2_mask/* | ext_wakeup_pin_3_mask*/, ESP_EXT1_WAKEUP_ALL_LOW));

            led_off();

            rtc_gpio_isolate(GPIO_NUM_12);

            gpio_hold_en(GPIO_NUM_4);//BAT_SENSE_EN


            gpio_hold_en(GPIO_NUM_23);//B
            gpio_hold_en(GPIO_NUM_19);//R
            gpio_hold_en(GPIO_NUM_18);//G

            //  gpio_hold_en(GPIO_NUM_22);//H_N
            //  gpio_hold_en(GPIO_NUM_21);//H_P

            // gpio_hold_en(GPIO_NUM_4);//H_N
            // gpio_hold_en(GPIO_NUM_12);//H_P

            gpio_deep_sleep_hold_en();

            printf("Entering deep sleep (wakeup-pin-level:%d)\n", gpio_get_level(GPIO_NUM_35));
            //    gettimeofday(&sleep_enter_time, NULL);

            vTaskDelay(200 / portTICK_PERIOD_MS); //just give the LED-task some time to really shut down the LEDs
            esp_deep_sleep_start();

            }
        }
    }
}


int rawBatVoltage=-1;

void getCureClipBatSoC() {

    ESP_LOGE("BASE", "getCureClipBatSoC()");
    esp_task_wdt_reset();
    gpio_set_level(GPIO_NUM_4, 1);
    vTaskDelay(200 / portTICK_PERIOD_MS);

    esp_task_wdt_reset();

  //  adc2_config_channel_atten( ADC2_CHANNEL_7, ADC_ATTEN_DB_0 );

    esp_err_t r=ESP_OK;

    rawBatVoltage=0;
    for (int i=0;i<10;i++) {
        int rawValue=0;
        int rawVoltage=0;
    //    r = adc2_get_raw(ADC2_CHANNEL_7 , ADC_BITWIDTH_12, &rawValue);
        ESP_ERROR_CHECK(adc_oneshot_read(adc2_handle, ADC_CHANNEL_7, &rawValue));
     //   ESP_LOGE(GATTS_TAG, "ADC%d Channel[%d] Raw Data: %d", ADC_UNIT_2, ADC_CHANNEL_7, rawValue);
        ESP_ERROR_CHECK(adc_cali_raw_to_voltage(Adc2CalibrationHandle, rawValue, &rawVoltage));
     //   ESP_LOGE(GATTS_TAG, "ADC%d Channel[%d] Cali Voltage: %d mV", ADC_UNIT_2, ADC_CHANNEL_7, rawVoltage);

     //   if (ESP_OK!=ESP_OK) {
      //      ESP_LOGE(GATTS_TAG, "adc2_get_raw returned %d!\n", r);
      //  }
//        rawBatVoltage+=rawValue;
                rawBatVoltage+=rawVoltage;
    }
    rawBatVoltage/=10;

    esp_task_wdt_reset();

    gpio_set_level(GPIO_NUM_4, 0);

    if (rawBatVoltage!=-1) {
        double Voltage=((double)rawBatVoltage)*BatVoltageFactor/1000.0;
//        float Voltage=(1.1*((float)rawBatVoltage)/4096.)*((1.2+.0406)/(0.2+.0406));
 //       ESP_LOGE(GATTS_TAG, "RawBatVoltage:%d \n", rawBatVoltage);
  //      ESP_LOGE(GATTS_TAG, "BatVoltage:%lf\n", Voltage);

        int SoC=100;
        //SoC data from https://blog.ampow.com/lipo-voltage-chart/

        if (Voltage<4.15)
            SoC=95;
        if (Voltage<4.11)
            SoC=90;
        if (Voltage<4.08)
            SoC=85;
        if (Voltage<4.02)
            SoC=75;
        if (Voltage<3.98)
            SoC=70;
        if (Voltage<3.95)
            SoC=65;
        if (Voltage<3.91)
            SoC=60;
        if (Voltage<3.87)
            SoC=55;
        if (Voltage<3.85)
            SoC=50;
        if (Voltage<3.84)
            SoC=45;
        if (Voltage<3.82)
            SoC=40;
        if (Voltage<3.8)
            SoC=35;
        if (Voltage<3.79)
            SoC=30;
        if (Voltage<3.77)
            SoC=25;
        if (Voltage<3.75)
            SoC=20;
        if (Voltage<3.73)
            SoC=15;
        if (Voltage<3.71)
            SoC=10;
        if (Voltage<3.69)
            SoC=5;
        if (Voltage<3.61)
            SoC=0;



        ESP_LOGE(GATTS_TAG, "Bat SoC:%d%%\n", SoC);

        isCharging=(gpio_get_level(GPIO_NUM_34)==0);

        ESP_LOGE(GATTS_TAG, "isCharging SoC:%d\n", isCharging);

        updateBatState(isCharging, SoC);
    }
    esp_task_wdt_reset();
}
