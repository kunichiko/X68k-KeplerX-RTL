#include "ch32v003fun.h"
#include "ch32v003_GPIO_branchless.h"
#include "../examples/i2c_slave/i2c_slave.h"
#include <stdio.h>

#include "kx_context.h"
#include "kx_buzzer.h"
#include "kx_mmc.h"
#include "kx_status_led.h"
#include "kx_wm8804.h"

// The I2C slave library uses a one byte address so you can extend the size of this array up to 256 registers
// note that the register set is modified by interrupts, to prevent the compiler from accidently optimizing stuff
// away make sure to declare the register array volatile

volatile uint8_t i2c_registers[32] = {
    'K', 'X', //
    0x00,     // Status (bit0:MMC_DET_n, bit1:MMC_CS_n, bit7:WM8804_INT_n)
    0xff,     // Status LED color
    0x10,     // Status LED brightness
    0x00,     // Status LED blinking
    0x00,     // Reserved
    0x00,     // Reserved
    0,0,0,0,0,0,0,0, // Reserved
    0,0,0,0,0,0,0,0, // Reserved
    0,0,0,0,0,0,0,0  // Reserved   
};

void sendBits(uint16_t GPIO_Pin, int bits)
{
    for (int i = 0; i < 8; i++)
    {

        if ((bits & 0x80) == 0)
        {
            // High 300nsec
            GPIOD->BSHR = GPIO_Pin;
            asm volatile("nop; nop; nop; nop; nop; nop; nop; nop; nop; nop; nop; nop;");
            // Low 600nsec
            GPIOD->BCR = GPIO_Pin;
            asm volatile("nop; nop; nop; nop; nop; nop; nop; nop; nop; nop; nop; nop; nop; nop; nop; nop; nop;nop; nop; nop; nop;");
        }
        else
        {
            // High 600nsec
            // GPIO_WriteBit(GPIOD, GPIO_Pin_6, Bit_SET);
            GPIOD->BSHR = GPIO_Pin;
            asm volatile("nop; nop; nop; nop; nop; nop; nop; nop; nop; nop; nop; nop; nop;nop; nop; nop; nop;nop; nop; nop; nop;");
            // Low 300nsec
            GPIOD->BCR = GPIO_Pin;
            asm volatile("nop; nop; nop; nop; nop; nop; nop; nop;nop; nop; nop; nop;");
        }
        asm volatile("nop; nop; nop; nop;");
        bits <<= 1;
    }
}

int32_t setRGB_last_tick = 0;

void setRGB(uint16_t GPIO_Pin, int r, int g, int b)
{
    // Wait 300us for Treset of WS2812B
    while (SysTick->CNT - setRGB_last_tick < 300 * DELAY_US_TIME)
    {
    }
    // NVIC_DisableIRQ(I2C1_EV_IRQn);
    // NVIC_DisableIRQ(I2C1_ER_IRQn);

    sendBits(GPIO_Pin, g);
    sendBits(GPIO_Pin, r);
    sendBits(GPIO_Pin, b);

    //  NVIC_EnableIRQ(I2C1_EV_IRQn);
    //  NVIC_EnableIRQ(I2C1_ER_IRQn);
    setRGB_last_tick = SysTick->CNT;
}

int main()
{
    SystemInit();

    // Enable GPIOs
    RCC->APB2PCENR |= RCC_APB2Periph_GPIOD | RCC_APB2Periph_GPIOC;

    // GPIO C0 Push-Pull (Buzzer)
    GPIOC->CFGLR &= ~(0xf << (4 * 0));
    GPIOC->CFGLR |= (GPIO_Speed_50MHz | GPIO_CNF_OUT_PP) << (4 * 0);
    GPIOC->BCR = GPIO_Pin_0;

    // GPIO D7 Push-Pull (Enable MMC_n)
    GPIOD->CFGLR &= ~(0xf << (4 * 7));
    GPIOD->CFGLR |= (GPIO_Speed_50MHz | GPIO_CNF_OUT_PP) << (4 * 7);
    GPIOD->BSHR = GPIO_Pin_7;

    // GPIO D6 Push-Pull (Kepler X Status LED)
    GPIOD->CFGLR &= ~(0xf << (4 * 6));
    GPIOD->CFGLR |= (GPIO_Speed_50MHz | GPIO_CNF_OUT_PP) << (4 * 6);

    // GPIO D5 Push-Pull (MMC Access LED)
    GPIOD->CFGLR &= ~(0xf << (4 * 5));
    GPIOD->CFGLR |= (GPIO_Speed_50MHz | GPIO_CNF_OUT_PP) << (4 * 5);

    // GPIO D4 Floating (MMC DET_n)
    GPIOD->CFGLR &= ~(0xf << (4 * 4));
    GPIOD->CFGLR |= (GPIO_Speed_In | GPIO_CNF_IN_FLOATING) << (4 * 4);

    // GPIO D3 Floating (MMC CS_n)
    GPIOD->CFGLR &= ~(0xf << (4 * 3));
    GPIOD->CFGLR |= (GPIO_Speed_In | GPIO_CNF_IN_FLOATING) << (4 * 3);

    // GPIO D2 Floating (WM8804 INT_n)
    GPIOD->CFGLR &= ~(0xf << (4 * 2));
    GPIOD->CFGLR |= (GPIO_Speed_In | GPIO_CNF_IN_FLOATING) << (4 * 2);

    // Wait
    Delay_Ms(500);

    // I2C
    SetupI2CSlave(0x70, i2c_registers, sizeof(i2c_registers));

    uint32_t systick;
    kx_context_t kx_context;
    kx_context.i2c_registers = (uint8_t *)i2c_registers;
    kx_context.buzzer_req = 0;
    kx_context.buzzer_ack = 0;
    kx_context.buzzer_note = 0;
    kx_context.buzzer_length = 0;
    kx_context.status_led_color = 0;
    kx_context.status_led_brightness = 0;

    kx_buzzer_init();
    kx_mmc_init();
    kx_status_led_init();
    kx_wm8804_init();

    uint32_t last_debug_dump_tick = 0;
    while (1)
    {
        #ifdef DEBUG
        if(SysTick->CNT - last_debug_dump_tick > 1000 * DELAY_MS_TIME)
        {
            last_debug_dump_tick = SysTick->CNT;
            printf("i2c_registers: ");
            for(int i = 0; i < sizeof(i2c_registers); i++)
            {
                printf("%02x ", i2c_registers[i]);
            }
            printf("\n");
        }
        #endif
        // I2C
        i2c_registers[0] = 'K'; // 0x4b
        i2c_registers[1] = 'X'; // 0x58
        //
        kx_context.status_led_color = i2c_registers[3];
        kx_context.status_led_brightness = i2c_registers[4];
        kx_context.status_led_blinking = i2c_registers[5];

        // Delay_Us(10);
        systick = SysTick->CNT;
        kx_buzzer_poll(systick, &kx_context);
        systick = SysTick->CNT;
        kx_mmc_poll(systick, &kx_context);
        systick = SysTick->CNT;
        kx_status_led_poll(systick, &kx_context);
        systick = SysTick->CNT;
        kx_wm8804_poll(systick, &kx_context);
    }
}
