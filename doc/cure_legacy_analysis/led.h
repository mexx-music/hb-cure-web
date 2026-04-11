#ifndef _LED_H_
#define _LED_H_

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

void led_setAdvertising();
void led_setLocked();
void led_setError();
void led_setIdle();
void led_setCuring();

void led_off();

void led_init();


void led_update();

void LedTask(void *);

#endif
