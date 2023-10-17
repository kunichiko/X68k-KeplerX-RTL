#ifndef __KX_WM8804_H__
#define __KX_WM8804_H__

#include <stdio.h>
#include <stdint.h>
#include "ch32v003fun.h"
#include "kx_context.h"

void kx_wm8804_init()
{
}

void kx_wm8804_poll(uint32_t systick, kx_context_t *context)
{
    if (GPIOD->INDR & GPIO_Pin_2) // WM8804 INT
    {
        context->i2c_registers[0x02] |= 0x80;
    }
    else
    {
        context->i2c_registers[0x02] &= ~(0x80);        
    }
}

#endif // __KX_WM8804_H__