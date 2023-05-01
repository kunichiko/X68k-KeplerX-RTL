#include "sys/alt_stdio.h"
#include "system.h"

int main()
{
    alt_printf("Hello from Nios II !!");
    while(1)
  {
      int reg;
      reg = *(volatile unsigned char *) PIO_DIPSW_BASE;
      *(volatile unsigned char *) PIO_LED_BASE = reg;
  }
   return (0);
}
