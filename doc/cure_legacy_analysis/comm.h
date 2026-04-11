#include "stdint.h"

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/queue.h"
#include "freertos/semphr.h"

#include "esp_partition.h"
#include "esp_ota_ops.h"

#ifndef __COMM_H__
#define __COMM_H__

void CommStringParserStateMachine(char c);

extern uint8_t RxQueueBuffer[1024];
void CommRxTask(void *);

extern QueueHandle_t RxQueueHandle;
extern StaticQueue_t RxQueue;

void invalidateCommStatemachine();
bool isCurebaseUnlocked();

extern SemaphoreHandle_t CommMutex;


extern esp_partition_t const *PartitionInfoRunning;
extern esp_partition_t const *PartitionInfoBooting;
extern esp_partition_t const *PartitionInfoOTA;

#endif
