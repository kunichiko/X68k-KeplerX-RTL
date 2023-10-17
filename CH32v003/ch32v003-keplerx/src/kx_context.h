#ifndef __KX_CONTEXT_H
#define __KX_CONTEXT_H

#include <stdint.h>

//#define DEBUG 1

typedef struct {
    // i2c
    uint8_t *i2c_registers;
    // buzzer
    uint8_t buzzer_req; // 1 = request, 0 = no request
    uint8_t buzzer_ack; // 1 = ack, 0 = no ack
    uint8_t buzzer_note; // 0 = no note, 1 = C, 2 = D, 3 = E, 4 = F, 5 = G, 6 = A, 7 = B, upto 16
    uint8_t buzzer_length; // 0 = 1/16, 1 = 1/8, 2 = 1/4, 3 = 1/2, 4 = 1, 5 = 2, 6 = 4, 7 = 8
    //
    uint8_t status_led_color;
    uint8_t status_led_brightness;    
    uint8_t status_led_blinking;
} kx_context_t;

void setRGB(uint16_t GPIO_Pin, int r, int g, int b);

#endif
