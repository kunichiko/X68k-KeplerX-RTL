#ifndef __KX_MMC_H
#define __KX_MMC_H

#include <stdint.h>
#include "ch32v003fun.h"
#include "kx_context.h"

typedef enum
{
    KX_MMC_STATE_FLAG_INIT = 0,
    KX_MMC_STATE_FLAG_ATTACHING = 1,
    KX_MMC_STATE_FLAG_ATTACHED = 2,
    KX_MMC_STATE_FLAG_READY = 3, // while CS is active
    KX_MMC_STATE_FLAG_DETACHING = 4,
    KX_MMC_STATE_FLAG_DETACHED = 5
} _kx_mmc_state_t;

struct _kx_mmc_context
{
    _kx_mmc_state_t state;
    _kx_mmc_state_t last_state;
    uint32_t access_start_tick;
    uint32_t access_last_tick;
    uint32_t access_flag;
    uint8_t sound_count;
} kx_mmc_state;

const uint8_t _kx_mmc_attaching_sound[] = {1 + 7, 3 + 7, 5 + 7};
const uint8_t _kx_mmc_detaching_sound[] = {5 + 7, 3 + 7, 1 + 7};

void kx_mmc_init()
{
    kx_mmc_state.state = KX_MMC_STATE_FLAG_INIT;
}

void kx_mmc_poll(uint32_t systick, kx_context_t *context)
{
#ifdef DEBUG
    if (kx_mmc_state.state != kx_mmc_state.last_state)
    {
        kx_mmc_state.last_state = kx_mmc_state.state;
        printf("kx_mmc_poll: %d\n", kx_mmc_state.state);
    }
#endif
    if (GPIOD->INDR & GPIO_Pin_4) // mmc det_n
    {
        context->i2c_registers[2] |= 0x01;
    }
    else
    {
        context->i2c_registers[2] &= ~(0x01);
    }
    if (GPIOD->INDR & GPIO_Pin_3) // mmc cs_n
    {
        context->i2c_registers[2] |= 0x02;
    }
    else
    {
        context->i2c_registers[2] &= ~(0x02);
    }

    switch (kx_mmc_state.state)
    {
    case KX_MMC_STATE_FLAG_INIT:
        if (GPIOD->INDR & GPIO_Pin_4)
        {
            setRGB(GPIO_Pin_5, 0x0f, 0, 0);
            kx_mmc_state.state = KX_MMC_STATE_FLAG_DETACHED;
        }
        else
        {
            setRGB(GPIO_Pin_5, 0x0c, 0x0f, 0);
            kx_mmc_state.state = KX_MMC_STATE_FLAG_ATTACHED;
        }
        break;
    case KX_MMC_STATE_FLAG_ATTACHING:
        if (!context->buzzer_req && !context->buzzer_ack)
        {
            context->buzzer_note = _kx_mmc_attaching_sound[kx_mmc_state.sound_count];
            context->buzzer_length = 1;
            context->buzzer_req = 1;
            kx_mmc_state.sound_count++;
            break;
        }
        if (context->buzzer_ack)
        {
            context->buzzer_req = 0;
            if (kx_mmc_state.sound_count == 3)
            {
                setRGB(GPIO_Pin_5, 0x0c, 0x0f, 0);
                kx_mmc_state.state = KX_MMC_STATE_FLAG_ATTACHED;
                break;
            }
        }
        break;
    case KX_MMC_STATE_FLAG_ATTACHED:
        GPIOD->BCR = GPIO_Pin_7; // assert MMC_n
        if (GPIOD->INDR & GPIO_Pin_4)
        {
            kx_mmc_state.state = KX_MMC_STATE_FLAG_DETACHING;
            kx_mmc_state.sound_count = 0;
            break;
        }
        if (!(GPIOD->INDR & GPIO_Pin_3)) // MMC CS_n
        {
            setRGB(GPIO_Pin_5, 0, 0x0f, 0);
            kx_mmc_state.state = KX_MMC_STATE_FLAG_READY;
            break;
        }
        break;
    case KX_MMC_STATE_FLAG_READY:
        GPIOD->BCR = GPIO_Pin_7; // assert MMC_n
        if (GPIOD->INDR & GPIO_Pin_4)
        {
            kx_mmc_state.state = KX_MMC_STATE_FLAG_DETACHING;
            kx_mmc_state.sound_count = 0;
            break;
        }
        if ((GPIOD->INDR & GPIO_Pin_3)) // MMC CS_n
        {
            setRGB(GPIO_Pin_5, 0x0c, 0x0f, 0);
            kx_mmc_state.state = KX_MMC_STATE_FLAG_ATTACHED;
            break;
        }
        break;
        /*    case KX_MMC_STATE_FLAG_ACCESSING:
                if (systick - kx_mmc_state.access_start_tick > (501 * DELAY_MS_TIME))
                {
                    kx_mmc_state.state = KX_MMC_STATE_FLAG_ATTACHED;
                    break;
                }
                if (systick - kx_mmc_state.access_last_tick > (100 * DELAY_MS_TIME))
                {
                    kx_mmc_state.access_last_tick = systick;
                    if (kx_mmc_state.access_flag)
                    {
                        setRGB(GPIO_Pin_5, 0, 0x0f, 0);
                    }
                    else
                    {
                        setRGB(GPIO_Pin_5, 0, 0, 0);
                    }
                    kx_mmc_state.access_flag = !kx_mmc_state.access_flag;
                    break;
                }
                break;*/
    case KX_MMC_STATE_FLAG_DETACHING:
        if (!context->buzzer_req && !context->buzzer_ack)
        {
            context->buzzer_note = _kx_mmc_detaching_sound[kx_mmc_state.sound_count];
            context->buzzer_length = 1;
            context->buzzer_req = 1;
            kx_mmc_state.sound_count++;
            break;
        }
        if (context->buzzer_ack)
        {
            context->buzzer_req = 0;
            if (kx_mmc_state.sound_count == 3)
            {
                setRGB(GPIO_Pin_5, 0x0f, 0, 0);
                kx_mmc_state.state = KX_MMC_STATE_FLAG_DETACHED;
                break;
            }
        }
        break;
    case KX_MMC_STATE_FLAG_DETACHED:
        GPIOD->BSHR = GPIO_Pin_7; // deassert MMC_n
        if (!(GPIOD->INDR & GPIO_Pin_4))
        {
            kx_mmc_state.state = KX_MMC_STATE_FLAG_ATTACHING;
            kx_mmc_state.sound_count = 0;
        }
        break;
    }
}
#endif