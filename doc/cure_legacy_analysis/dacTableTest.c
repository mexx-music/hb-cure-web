#include <stdint.h>
#include <math.h>
#include <stdio.h>

#define WaveForm_Sine 0x00
#define WaveForm_Triangle 0x01
#define WaveForm_Rectangular 0x02
#define WaveForm_SawTooth 0x03

#define numDDS 2

int TopValueBits=5;


volatile uint32_t Accumulators[numDDS];
volatile uint32_t Increments[numDDS];
double Amplitudes[numDDS];
int intFrequency=100e3;

uint8_t WaveTable[numDDS][8];

int main() {
    int i=0;
    Amplitudes[0]=1.0;
    Amplitudes[1]=1.0;

    int WaveType=WaveForm_SawTooth;

    const int TopValue=(1<<TopValueBits);
    const double WaveFormAmplitude=(double)((TopValue/2)-1);
    const int WaveFormOffset=TopValue/2;

    if (WaveType==WaveForm_Sine) {
        for (int j=0;j<TopValue;j++) {
            WaveTable[i][j]=(int8_t)WaveFormOffset+(int8_t)(Amplitudes[i]*WaveFormAmplitude*sin(2.0*M_PI*(double)j/(double)TopValue));
        }
    } else if (WaveType==WaveForm_Triangle) {
        for (int j=0;j<TopValue/4;j++) {
            WaveTable[i][j]=(int8_t)WaveFormOffset+ (int8_t)(Amplitudes[i]*WaveFormAmplitude * (0.0+4.0*(double)j/(double)TopValue));
        }

        for (int j=TopValue/4;j<3*(TopValue/4);j++) {
            WaveTable[i][j]=(int8_t)WaveFormOffset+ (int8_t)(Amplitudes[i]*WaveFormAmplitude * (1.0-4.0*(double)(j-TopValue/4)/(double)TopValue));
        }

        for (int j=3*(TopValue/4);j<TopValue;j++) {
            WaveTable[i][j]=(int8_t)WaveFormOffset+ (int8_t)(Amplitudes[i]*WaveFormAmplitude * (-1.0+4.0*(double)(j-3*(TopValue/4))/(double)TopValue));
        }
    } else if (WaveType==WaveForm_Rectangular) {
        for (int j=0;j<TopValue;j++) {
            WaveTable[i][j]=(int8_t)WaveFormOffset+(int8_t)(Amplitudes[i]*WaveFormAmplitude* ( (j<TopValue/2)?1.0:-1.0) );
        }
    } else if (WaveType==WaveForm_SawTooth) {
        for (int j=0;j<(1<<TopValueBits);j++) {
            WaveTable[i][j]=(int8_t)WaveFormOffset+(int8_t)(Amplitudes[i]*WaveFormAmplitude* ( -1.0+2.0*(double)j/(double)TopValue) );
        }
    } else {
        //todo: report problem!
    }

    for (int j=0;j<(1<<TopValueBits);j++) {
        printf("%d\t%d\n", j, WaveTable[i][j]);
    }

    return 0;
}
