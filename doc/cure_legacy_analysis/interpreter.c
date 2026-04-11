#define LOG_LOCAL_LEVEL ESP_LOG_VERBOSE

#include "interpreter.h"
//#include "hal/cpu_types.h"
#include "sdkconfig.h"
#include "esp_system.h"
#include "esp_log.h"

#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "led.h"
#include "dds.h"

#include "comm.h"
#include "miniz.h"
#include <stdlib.h>

#define TAG "INTERPRETER"


static EXT_RAM_BSS_ATTR uint8_t CureProgram[maxProgrammSize];

CureProgramCmd_id_t *ProgramId;
CureProgramCmd_frequency_t *ProgramFrequency;
CureProgramCmd_program_t *ProgramLastStart;
CureProgramCmd_waveForm_t *ProgramLastWaveForm;
CureProgramCmd_customName_t *ProgramLastCustomName;



bool ProgramPaused;
int ProgrammCounter;
int ProgrammLength;

int ProgramFrequencyElapsed;
int ProgramFrequencyTotal;

int ProgramTotalElapsed;
int ProgramTotal;
int ProgramCurrentFrequencyDwellTime;

SemaphoreHandle_t Interpreter_Mutex = NULL;


void startDDS() {
    double frequencies[2];
    double amplitudes[2];

    amplitudes[0]=((double)ProgramLastStart->Eintensity)/10.0;
    amplitudes[1]=((double)ProgramLastStart->Hintensity)/10.0;
    ESP_LOGE(TAG, "E Amplitude=%lf", amplitudes[0]);
    ESP_LOGE(TAG, "H Amplitude=%lf", amplitudes[1]);

    frequencies[0]=ProgramFrequency->frequency;
    frequencies[1]=ProgramFrequency->frequency;
    ESP_LOGE(TAG, "Frequency=%lf", frequencies[0]);

    int EFieldWaveForm=WaveForm_Sine;
    int HFieldWaveForm=WaveForm_Sine;

    if (ProgramLastWaveForm!=NULL) {
        EFieldWaveForm=ProgramLastWaveForm->EwaveForm;
        HFieldWaveForm=ProgramLastWaveForm->HwaveForm;
    }

    DDS_startEx(2, frequencies, amplitudes, EFieldWaveForm, HFieldWaveForm);

}

void Interpreter_clearProgram() {
    ESP_LOGI(TAG, "Interpreter_clearProgram()");
/*
    if (CureFirmwareSupportsStoredCureProg) {
        loadCureProgFromNVS();
        return;
    }
*/
    xSemaphoreTake(Interpreter_Mutex, portMAX_DELAY);

    ProgrammCounter=-1;
    ProgrammLength=0;
    ProgramLastStart=NULL;
    ProgramCurrentFrequencyDwellTime=0;

    ProgramFrequencyElapsed=0;
    ProgramFrequencyTotal=0;

    ProgramTotalElapsed=0;
    ProgramTotal=0;

    ProgramPaused=false;

    ProgramId=NULL;
    ProgramFrequency=NULL;
    ProgramLastWaveForm=NULL;
    ProgramLastCustomName=NULL;

    for (int i=0;i<maxProgrammSize;i++) {
        CureProgram[i]=INSTRUCTIN_end;
    }

    led_setIdle();

    xSemaphoreGive(Interpreter_Mutex);
}

bool Interpreter_appendProgramm(int len, uint8_t *bytes) {
    ESP_LOGI(TAG, "Interpreter_appendProgramm()");

    xSemaphoreTake(Interpreter_Mutex, portMAX_DELAY);

    for (int i=0; (i<len) && (i+ProgrammLength<maxProgrammSize);i++) {
        CureProgram[i+ProgrammLength]=bytes[i];
    }
    ProgrammLength+=len;

    //something bad happened... resetting the interpreter is maybe the best option.
    if (ProgrammLength>maxProgrammSize) {
        ProgrammCounter=-1;
        ProgrammLength=0;
        ProgramLastStart=NULL;
        ProgramLastWaveForm=NULL;
        ProgramLastCustomName=NULL;

        for (int i=0;i<maxProgrammSize;i++) {
            CureProgram[i]=INSTRUCTIN_end;
        }

        xSemaphoreGive(Interpreter_Mutex);
        return false;
    }

    if (CureFirmwareSupportsStoredCureProg) {

        bool programIsValid=false;
        if (ProgrammLength>sizeof(CureProgramCmd_id_t)) {
            if (CureProgram[0]==INSTRUCTIN_programId) {
                CureProgramCmd_id_t *idEntry=(CureProgramCmd_id_t *)CureProgram;
                ESP_LOGI(TAG, "ProgrammLength %d %d",(int)ProgrammLength, (int)idEntry->programLen+sizeof(CureProgramCmd_id_t));

                if (ProgrammLength==idEntry->programLen+sizeof(CureProgramCmd_id_t)) {
                    uint32_t crc=0;
                    crc=mz_crc32(crc,(const unsigned char *)(const char *)&CureProgram[sizeof(CureProgramCmd_id_t)], idEntry->programLen);
                    if (crc==idEntry->programId) {
                        programIsValid=true;
                        ESP_LOGI(TAG, "successfully stored loaded!");
                    } else {
                        ESP_LOGI(TAG, "crc does not match! (%x %x)",(unsigned int)crc,(unsigned int)idEntry->programId);
                    }
                }
            }
        }

        if (programIsValid) {
            ESP_LOGI(TAG, "storing new cureProg in NVS!");
            nvs_set_blob(NVS_Handle, "CureProg", CureProgram, maxProgrammSize);
            nvs_commit(NVS_Handle);
        }
    }

    xSemaphoreGive(Interpreter_Mutex);
    return true;
}

void Interpreter_init() {
    ESP_LOGI(TAG, "Interpreter_init()");
    Interpreter_Mutex=xSemaphoreCreateMutex();
    Interpreter_clearProgram();
}

int Interpreter_process(int elapsedms) {
//    ESP_LOGI(TAG, "Interpreter_process()");
 //  ESP_LOGE(TAG, "Interpreter_process(%d); PC=%X", elapsedms, ProgrammCounter);

    bool simulate=false;
    if (elapsedms<0) {
        simulate=true;
        elapsedms=ProgramCurrentFrequencyDwellTime;
    }

    if (ProgramPaused)
        return ProgramCurrentFrequencyDwellTime;

    ProgramCurrentFrequencyDwellTime-=elapsedms;

    if (ProgramFrequencyTotal>0) {
        ProgramTotalElapsed+=elapsedms;
        ProgramFrequencyElapsed+=ProgramFrequencyElapsed;
    }

    if (ProgramCurrentFrequencyDwellTime>0) {
        return ProgramCurrentFrequencyDwellTime;
    } else
        ProgramCurrentFrequencyDwellTime=0;

//     ESP_LOGI(TAG, "ProgramTotalElapsed=%d",ProgramTotalElapsed);

    bool stop=false;
    bool invalid=false;



    if (!simulate)
        xSemaphoreTake(Interpreter_Mutex, portMAX_DELAY);

    if ((ProgrammCounter>=ProgrammLength) || ProgrammCounter>=maxProgrammSize) {
        stop=true;
        invalid=true;
    }

    if ( (ProgrammCounter>=0) && (!stop) && (!invalid)) {
        uint8_t currentInstruction=CureProgram[ProgrammCounter];

        switch (currentInstruction) {
            case INSTRUCTIN_end:
                ESP_LOGE(TAG, "INSTRUCTION INSTRUCTIN_end");

                stop=true;
                break;


            case INSTRUCTIN_programm:
                ESP_LOGE(TAG, "INSTRUCTION INSTRUCTIN_programm");

                ProgramLastStart=(CureProgramCmd_program_t *)(&CureProgram[ProgrammCounter]);
                ProgrammCounter+=sizeof(CureProgramCmd_program_t);

                ProgramFrequencyTotal=0;
                ProgramFrequencyElapsed=0;

                ProgramLastWaveForm=NULL;
                ProgramLastCustomName=NULL;

                break;
            case INSTRUCTIN_waveForm:
                ESP_LOGE(TAG, "INSTRUCTION INSTRUCTIN_waveForm");

                ProgramLastWaveForm=(CureProgramCmd_waveForm_t *)(&CureProgram[ProgrammCounter]);
                ProgrammCounter+=sizeof(CureProgramCmd_waveForm_t);

                break;
            case INSTRUCTIN_customName:
                ESP_LOGE(TAG, "INSTRUCTION INSTRUCTIN_customName");

                ProgramLastCustomName=(CureProgramCmd_customName_t *)(&CureProgram[ProgrammCounter]);
                ProgrammCounter+=2+ProgramLastCustomName->len;

                break;
            case INSTRUCTIN_frequency: {
                ESP_LOGE(TAG, "INSTRUCTION INSTRUCTIN_frequency");

                CureProgramCmd_frequency_t *data=(CureProgramCmd_frequency_t *)(&CureProgram[ProgrammCounter]);
                ProgramFrequency=data;

                ProgrammCounter+=sizeof(CureProgramCmd_frequency_t);

                ProgramCurrentFrequencyDwellTime=ProgramFrequency->dwelltime*1000;
                ESP_LOGE(TAG, "DwellTime=%d", ProgramCurrentFrequencyDwellTime);

                ProgramFrequencyTotal=ProgramCurrentFrequencyDwellTime;
                ProgramFrequencyElapsed=0;
                if (!simulate) {
                    DDS_stop();
                    startDDS();
                }

                }
                break;
            case INSTRUCTIN_programId: {
                ESP_LOGE(TAG, "INSTRUCTION INSTRUCTIN_programId");

                ProgramId=(CureProgramCmd_id_t *)(&CureProgram[ProgrammCounter]);
                ProgrammCounter+=sizeof(CureProgramCmd_id_t);
                break;
                }
            default:
                ESP_LOGE(TAG, "unknown interpreter instruction %X at location %X!\nstopping!\n\n", currentInstruction, ProgrammCounter);
                stop=true;
                invalid=true;
                break;
        }
    }

    if (!simulate)
        xSemaphoreGive(Interpreter_Mutex);

    if (stop) {
        if (!simulate) {
            Interpreter_stop();
        } else {
            ProgrammCounter=-1;
        }
    }

    if (invalid) {
        Interpreter_clearProgram();
        return 0;
    }


    return ProgramCurrentFrequencyDwellTime;
}

void Interpreter_stop() {
    ESP_LOGI(TAG, "Interpreter_stop()");
    xSemaphoreTake(Interpreter_Mutex, portMAX_DELAY);

    ProgrammCounter=-1;
    ProgramFrequency=NULL;
    ProgramId=NULL;
    ProgramLastStart=NULL;

    if (isCurebaseUnlocked()) {
        led_setIdle();
    } else {
        led_setAdvertising();
    }

    DDS_stop();

    xSemaphoreGive(Interpreter_Mutex);
}

void Interpreter_start() {
    ESP_LOGE(TAG, "Interpreter_start()");

    xSemaphoreTake(Interpreter_Mutex, portMAX_DELAY);

    ProgramTotalElapsed=0;
    ProgramTotal=0;
    ProgrammCounter=0;
    ProgramPaused=false;

    ProgramFrequency=NULL;
    ProgramId=NULL;
    ProgramLastStart=NULL;
    ProgramLastWaveForm=NULL;
    ProgramLastCustomName=NULL;


    //simulate one run in order to calculate the total running time and to check for a valid program...
    //todo: invalid data is reported to the debug-output, only!
    while (ProgrammCounter>=0) {
        int dwelltime=Interpreter_process(-1);
        ESP_LOGE(TAG, "dwelltime=%d", dwelltime);
    }

    ProgramTotal=ProgramTotalElapsed;

    //ESP_LOGI(TAG, "ProgramTotal=%d", ProgramTotal);

    led_setCuring();

    ProgramTotalElapsed=0;
    ProgrammCounter=0;

    ProgramFrequency=NULL;
    ProgramId=NULL;
    ProgramLastStart=NULL;

    ProgramPaused=false;

    xSemaphoreGive(Interpreter_Mutex);
    ESP_LOGE(TAG, "return from Interpreter_start()");
}

void Interpreter_status(bool *running, bool *paused, int *elapsed, int *total, CureProgramCmd_id_t **id, uint32_t *PC, int *WaitTime) {
     xSemaphoreTake(Interpreter_Mutex, portMAX_DELAY);
 //  ESP_LOGI(TAG, "Interpreter_status()");
    *running=false;
    *paused=false;
    *elapsed=0;
    *total=0;
    *id=NULL;
    *PC=-1;
    *WaitTime=0;

    if (ProgramId) {
        *running=(ProgrammCounter>=0); //call to Interpreter_isRunning would cause a dead-lock...
        *paused=ProgramPaused;
        *elapsed=ProgramTotalElapsed;
        *total=ProgramTotal;
        *id=ProgramId;
        *WaitTime=ProgramCurrentFrequencyDwellTime;
        *PC=ProgrammCounter;
    }

    xSemaphoreGive(Interpreter_Mutex);

}

void Interpreter_pause() {
    xSemaphoreTake(Interpreter_Mutex, portMAX_DELAY);

    ProgramPaused=true;

    DDS_stop();

    led_setIdle();
    xSemaphoreGive(Interpreter_Mutex);
}

void Interpreter_resume() {
    xSemaphoreTake(Interpreter_Mutex, portMAX_DELAY);

    ProgramPaused=false;

    startDDS();

    led_setCuring();

    xSemaphoreGive(Interpreter_Mutex);
}

void Interpreter_Id(int *len, uint32_t *id) {
     xSemaphoreTake(Interpreter_Mutex, portMAX_DELAY);
   *len=0;
    *id=0;
    if (ProgramId!=NULL) {
        *len=ProgramId->programLen;
        *id=ProgramId->programId;
    }
    xSemaphoreGive(Interpreter_Mutex);
}
int Interpreter_readProgram(int pos, int len, uint8_t *bytes) {
    xSemaphoreTake(Interpreter_Mutex, portMAX_DELAY);
    if (pos>=ProgrammLength) {
        xSemaphoreGive(Interpreter_Mutex);
        return 0;
    }
    int i;
    for (i=0;(i<len) && (pos+i<ProgrammLength);i++) {
        bytes[i]=CureProgram[pos+i];
    }
    xSemaphoreGive(Interpreter_Mutex);
    return i;
}

bool Interpreter_isRunning() {
  //  ESP_LOGI(TAG, "Interpreter_isRunning(); PC=%X", ProgrammCounter);
    xSemaphoreTake(Interpreter_Mutex, portMAX_DELAY);
    bool running=(ProgrammCounter>=0);
    xSemaphoreGive(Interpreter_Mutex);
    return running;
}

bool Interpreter_isPaused() {
  //  ESP_LOGI(TAG, "Interpreter_isPaused(); PC=%X", ProgrammCounter);
    xSemaphoreTake(Interpreter_Mutex, portMAX_DELAY);
    bool paused=ProgramPaused;
    xSemaphoreGive(Interpreter_Mutex);
    return paused;
}

void loadCureProgFromNVS() {
    ESP_LOGI(TAG, "loadCureProgFromNVS()");

    if (!CureFirmwareSupportsStoredCureProg) {
        Interpreter_clearProgram();
        return;
    }

    xSemaphoreTake(Interpreter_Mutex, portMAX_DELAY);

    ProgrammCounter=-1;
    ProgramLastStart=NULL;
    ProgramCurrentFrequencyDwellTime=0;

    ProgramFrequencyElapsed=0;
    ProgramFrequencyTotal=0;

    ProgramTotalElapsed=0;
    ProgramTotal=0;

    ProgramPaused=false;

    ProgramId=NULL;
    ProgramFrequency=NULL;
    ProgramLastWaveForm=NULL;
    ProgramLastCustomName=NULL;

    size_t bufferSize=maxProgrammSize;
    nvs_get_blob(NVS_Handle, "CureProg", CureProgram, &bufferSize);

    bool programIsValid=false;

    if (CureProgram[0]==INSTRUCTIN_programId) {
        CureProgramCmd_id_t *idEntry=(CureProgramCmd_id_t *)CureProgram;
        ProgrammLength=idEntry->programLen+sizeof(CureProgramCmd_id_t);

        uint32_t crc=0;
        if (ProgrammLength<=maxProgrammSize) {
            crc=mz_crc32(crc,(const unsigned char *)(const char *)&CureProgram[sizeof(CureProgramCmd_id_t)], idEntry->programLen);
            if (crc==idEntry->programId) {
                programIsValid=true;
                ESP_LOGI(TAG, "successfully stored loaded!");
            }
        }
    }

    if (!programIsValid) {
        ESP_LOGI(TAG, "stored program was not valid!");
        ProgrammLength=0;
        for (int i=0;i<maxProgrammSize;i++) {
            CureProgram[i]=INSTRUCTIN_end;
        }
    }

    xSemaphoreGive(Interpreter_Mutex);
}
