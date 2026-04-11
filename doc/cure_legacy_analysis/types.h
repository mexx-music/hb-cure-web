#ifndef _CureFirmeware_Types_h
#define _CureFirmeware_Types_h

#ifdef __cplusplus
extern "C" {
#endif

//0 => CureBase
//1 => CureClip

typedef enum {
    CureDeviceType_CureBase=0,
    CureDeviceType_CureClip=1,
    CureDeviceType_VetClip=2,
} CureDeviceType_t;

#ifdef __cplusplus
}
#endif


#endif
