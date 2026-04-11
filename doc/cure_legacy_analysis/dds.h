/*
 * dds.h
 *
 *  Created on: 03.12.2020
 *      Author: hans
 */

#ifndef DDS_H_
#define DDS_H_

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "led.h"

typedef struct {
    uint8_t bytes[16];
}UUID_t;

typedef union {
 uint8_t Hfield:1;
 uint8_t Efield:1;
} programmItemBitField_t;

typedef struct {
    UUID_t uuid;
    float intensity;
    uint32_t duration;
    programmItemBitField_t bitfield;
}ProgrammItem_t;

#define maxItemsInPlaylist 128

void DDS_init();
void DDS_start(int values, double *frequencies, double *amplitudes);
void DDS_startEx(int values, double *frequencies, double *amplitudes, int EFieldWaveForm, int HFieldWaveForm);
void DDS_stop();

void DDS_generateWaveTable(uint8_t *WaveTable, const double Amplitude, const int WaveForm, const int Bits);


void DDS_Playlist_clear();
void DDS_Playlist_start();
void DDS_Playlist_stop();

ProgrammItem_t *DDS_Playlist_read(int index);

void DDS_Playlist_add(ProgrammItem_t *item);
void DDS_Playlist_status(int *duration, int *elapsed);


void DDSTask(void *);

void DDS_Timer_start(int values, double *frequencies, double *amplitudes, int EFieldWaveForm, int HFieldWaveForm);
void DDS_Timer_stop();
void DDS_Timer_init();

void DDS_DAC_start(int values, double *frequencies, double *amplitudes, int EFieldWaveForm, int HFieldWaveForm);
void DDS_DAC_stop();
void DDS_DAC_init();

//channel0=E
//channel1=H
#define numDDS 2
extern volatile uint32_t Accumulators[numDDS];
extern volatile uint32_t Increments[numDDS];
extern uint8_t WaveTable[numDDS][256];


#endif /* DDS_H_ */
