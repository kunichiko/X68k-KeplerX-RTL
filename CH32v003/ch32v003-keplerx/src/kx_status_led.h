#ifndef __KX_STATUS_LED_H__
#define __KX_STATUS_LED_H__

#include <stdio.h>
#include <stdint.h>
#include "ch32v003fun.h"
#include "kx_context.h"

typedef enum
{
    KX_STATUS_LED_IDLE = 0,
    KX_STATUS_LED_UPDATING,
} _kx_status_led_state_t;

struct kx_status_led_context
{
    _kx_status_led_state_t state;
    _kx_status_led_state_t last_state;
    uint8_t last_color;
    uint8_t last_brightness;
    uint8_t last_blinking;
    uint32_t last_tick;
    uint32_t r, g, b;
    uint8_t flag;
} kx_status_led_context;

void kx_status_led_init(void)
{
    kx_status_led_context.state = KX_STATUS_LED_IDLE;
}

void kx_status_led_poll(uint32_t tick, kx_context_t *context)
{
#ifdef DEBUG
    if (kx_status_led_context.last_state != kx_status_led_context.state)
    {
        printf("kx_status_led_context.state = %d\r\n", kx_status_led_context.state);
        kx_status_led_context.last_state = kx_status_led_context.state;
    }
#endif
    context->status_led_color = context->i2c_registers[0x03];
    context->status_led_brightness = context->i2c_registers[0x04];
    context->status_led_blinking = context->i2c_registers[0x05];

    switch (kx_status_led_context.state)
    {
    case KX_STATUS_LED_IDLE:
        if (kx_status_led_context.last_color != context->status_led_color ||           //
            kx_status_led_context.last_brightness != context->status_led_brightness || //
            kx_status_led_context.last_blinking != context->status_led_blinking)
        {
            kx_status_led_context.last_color = context->status_led_color;
            kx_status_led_context.last_brightness = context->status_led_brightness;
            kx_status_led_context.last_blinking = context->status_led_blinking;
            kx_status_led_context.state = KX_STATUS_LED_UPDATING;
            break;
        }
        switch ((kx_status_led_context.last_blinking & 0xf0) >> 4)
        {
        case 0: // no blinking
            break;
        case 1: // blinking normal
            if (tick - kx_status_led_context.last_tick > (1000 / ((kx_status_led_context.last_blinking & 0x0f) + 1)) * DELAY_MS_TIME)
            {
                if (kx_status_led_context.flag)
                {
                    setRGB(GPIO_Pin_6, 0, 0, 0);
                }
                else
                {
                    setRGB(GPIO_Pin_6, kx_status_led_context.r, kx_status_led_context.g, kx_status_led_context.b);
                }
                kx_status_led_context.last_tick = tick;
                kx_status_led_context.flag ^= 1;
            }
            break;
        }
        break;
    case KX_STATUS_LED_UPDATING:
        kx_status_led_context.r = (kx_status_led_context.last_color & 0xe0) << 0;
        kx_status_led_context.g = (kx_status_led_context.last_color & 0x1c) << 3;
        kx_status_led_context.b = (kx_status_led_context.last_color & 0x03) << 6;
        //
        kx_status_led_context.r *= kx_status_led_context.last_brightness;
        kx_status_led_context.g *= kx_status_led_context.last_brightness;
        kx_status_led_context.b *= kx_status_led_context.last_brightness;
        //
        kx_status_led_context.r >>= 8;
        kx_status_led_context.g >>= 8;
        kx_status_led_context.b >>= 8;
        setRGB(GPIO_Pin_6, kx_status_led_context.r, kx_status_led_context.g, kx_status_led_context.b);
        kx_status_led_context.state = KX_STATUS_LED_IDLE;
        break;
    }
}

#endif