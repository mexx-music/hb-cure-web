#ifndef INTERPRETER_H_
#define INTERPRETER_H_

#include <stdint.h>
#include <stdbool.h>
#include "nvs_flash.h"


#define WaveForm_Sine 0x00
#define WaveForm_Triangle 0x01
#define WaveForm_Rectangular 0x02
#define WaveForm_SawTooth 0x03

#define maxProgrammSize 32768


//1 byte
#define INSTRUCTIN_end 0x00

//18 byte: 1byte instructin; 16byte Uuid; 1 nibble E intensity 0-10; 1 nibble H intensity 0-10
#define INSTRUCTIN_programm 0x01

//5 byte: 1byte instructin; 4byte float frequency; 2byte duration
#define INSTRUCTIN_frequency 0x02

//5 byte 1byte instruction; 4byte id
#define INSTRUCTIN_programId 0x03

//2 byte: 1byte instruction; 1nibble H waveform 1nibble E waveform
#define INSTRUCTIN_waveForm 0x04

//n bye: 1byte instruction 1byte length; n-bytes data (base64)
#define INSTRUCTIN_customName 0x05

#pragma pack(push,1)
typedef struct {
    uint8_t cmd;
} CureProgramCmd_end_t;

typedef struct {
    uint8_t cmd;
    uint8_t uuid[16];
    uint8_t Eintensity:4;
    uint8_t Hintensity:4;
} CureProgramCmd_program_t;

typedef struct {
    uint8_t cmd;
    float frequency;
    uint16_t dwelltime;
} CureProgramCmd_frequency_t;

typedef struct {
    uint8_t cmd;
    uint32_t programLen;
    uint32_t programId;
} CureProgramCmd_id_t;

typedef struct {
    uint8_t cmd;
    uint8_t EwaveForm:4;
    uint8_t HwaveForm:4;
} CureProgramCmd_waveForm_t;

typedef struct {
    uint8_t cmd;
    uint8_t len;
    uint8_t data[];
} CureProgramCmd_customName_t;
#pragma pack(pop)

void Interpreter_init();
int Interpreter_process(int elapsedms);
void Interpreter_stop();
void Interpreter_start();
void Interpreter_pause();
void Interpreter_resume();
void Interpreter_clearProgram();
void Interpreter_status(bool *running, bool *paused, int *elapsed, int *total, CureProgramCmd_id_t **id, uint32_t *PC, int *WaitTime);
bool Interpreter_isRunning();
bool Interpreter_isPaused();
void Interpreter_Id(int *len, uint32_t *id);
int Interpreter_readProgram(int pos, int len, uint8_t *bytes);

bool Interpreter_appendProgramm(int len, uint8_t *bytes);

extern bool CureFirmwareSupportsStoredCureProg;
extern nvs_handle_t NVS_Handle;
void loadCureProgFromNVS();

#endif
