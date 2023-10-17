#ifndef __KX_BUZZER_H
#define __KX_BUZZER_H

#include <stdint.h>
#include "ch32v003fun.h"
#include "kx_context.h"

typedef enum
{
    KX_BUZZER_STATE_FLAG_IDLE = 0,
    KX_BUZZER_STATE_FLAG_PLAYING = 1,
    KX_BUZZER_STATE_FLAG_STOPPED = 2
} _kx_buzzer_state_t;

struct _kx_buzzer_context
{
    _kx_buzzer_state_t state;
    _kx_buzzer_state_t last_state;
    uint32_t start_tick;
    uint32_t last_tick;
    uint8_t flag;
} kx_buzzer_context;

float note_freq[] = {0.0,                                                           //
                     130.813, 146.832, 164.814, 174.614, 195.998, 220.000, 246.942, //
                     261.626, 293.665, 329.628, 349.228, 391.995, 440.000, 493.883, 523.251};

void kx_buzzer_init()
{
    kx_buzzer_context.state = KX_BUZZER_STATE_FLAG_IDLE;
}

void kx_buzzer_poll(uint32_t systick, kx_context_t *context)
{
#ifdef DEBUG
    if (kx_buzzer_context.state != kx_buzzer_context.last_state)
    {
        kx_buzzer_context.last_state = kx_buzzer_context.state;
        printf("kx_buzzer_poll: %d\n", kx_buzzer_context.state);
    }
#endif

    switch (kx_buzzer_context.state)
    {
    case KX_BUZZER_STATE_FLAG_IDLE:
        if (context->buzzer_req)
        {
            kx_buzzer_context.state = KX_BUZZER_STATE_FLAG_PLAYING;
            kx_buzzer_context.start_tick = systick;
            kx_buzzer_context.last_tick = systick;
            kx_buzzer_context.flag = 0;
        }
        break;
    case KX_BUZZER_STATE_FLAG_PLAYING:
        if (!context->buzzer_req)
        {
            kx_buzzer_context.state = KX_BUZZER_STATE_FLAG_STOPPED;
            break;
        }
        if (systick - kx_buzzer_context.start_tick > ((40 << context->buzzer_length) * DELAY_MS_TIME))
        {
            kx_buzzer_context.state = KX_BUZZER_STATE_FLAG_STOPPED;
            break;
        }
        int hz = note_freq[context->buzzer_note];
        uint32_t interval = 1000000 / hz / 2 * DELAY_US_TIME;
        if (systick - kx_buzzer_context.last_tick > interval)
        {
            kx_buzzer_context.last_tick = systick;
            if (kx_buzzer_context.flag)
            {
                GPIOC->BSHR = GPIO_Pin_0;
            }
            else
            {
                GPIOC->BCR = GPIO_Pin_0;
            }
            kx_buzzer_context.flag = !kx_buzzer_context.flag;
            break;
        }
        break;
    case KX_BUZZER_STATE_FLAG_STOPPED:
        context->buzzer_ack = 1;
        if (!context->buzzer_req)
        {
            context->buzzer_ack = 0;
            kx_buzzer_context.state = KX_BUZZER_STATE_FLAG_IDLE;
        }
        break;
    }
}

#endif
