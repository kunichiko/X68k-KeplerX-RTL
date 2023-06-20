## Generated SDC file "X68KeplerX.sdc"

## Copyright (C) 2021  Intel Corporation. All rights reserved.
## Your use of Intel Corporation's design tools, logic functions 
## and other software and tools, and any partner logic 
## functions, and any output files from any of the foregoing 
## (including device programming or simulation files), and any 
## associated documentation or information are expressly subject 
## to the terms and conditions of the Intel Program License 
## Subscription Agreement, the Intel Quartus Prime License Agreement,
## the Intel FPGA IP License Agreement, or other applicable license
## agreement, including, without limitation, that your use is for
## the sole purpose of programming logic devices manufactured by
## Intel and sold by Intel or its authorized distributors.  Please
## refer to the applicable agreement for further details, at
## https://fpgasoftware.intel.com/eula.


## VENDOR  "Altera"
## PROGRAM "Quartus Prime"
## VERSION "Version 21.1.0 Build 842 10/21/2021 Patches 0.07std SJ Lite Edition"

## DATE    "Mon May  8 01:22:41 2023"

##
## DEVICE  "EP4CE22F17C6"
##


#**************************************************************
# Time Information
#**************************************************************

set_time_format -unit ns -decimal_places 3



#**************************************************************
# Create Clock
#**************************************************************

create_clock -name {pClk50M} -period 20.000 -waveform { 0.000 10.000 } [get_ports {pClk50M}]
create_clock -name {pGPIO1_IN[0]} -period 80.000 -waveform { 0.000 40.000 } [get_ports {pGPIO1_IN[0]}]
create_clock -name {pGPIO1_IN[1]} -period 40.000 -waveform { 0.000 20.000 } [get_ports {pGPIO1_IN[1]}]
create_clock -name {em3802:midi|rxframe:rxunit|DONE} -period 10000.000 -waveform { 0.000 5000.000 } 
create_clock -name {i2s_encoder:I2S_enc|i2s_lrck} -period 10000.000 -waveform { 0.000 5000.000 } 


#**************************************************************
# Create Generated Clock
#**************************************************************

create_generated_clock -name {pllmain_inst|altpll_component|auto_generated|pll1|clk[0]} -source [get_pins {pllmain_inst|altpll_component|auto_generated|pll1|inclk[0]}] -duty_cycle 50/1 -multiply_by 2 -master_clock {pClk50M} [get_pins {pllmain_inst|altpll_component|auto_generated|pll1|clk[0]}] 
create_generated_clock -name {pllmain_inst|altpll_component|auto_generated|pll1|clk[1]} -source [get_pins {pllmain_inst|altpll_component|auto_generated|pll1|inclk[0]}] -duty_cycle 50/1 -multiply_by 2 -phase 180.000 -master_clock {pClk50M} [get_pins {pllmain_inst|altpll_component|auto_generated|pll1|clk[1]}] 
create_generated_clock -name {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]} -source [get_pins {pllmain_inst|altpll_component|auto_generated|pll1|inclk[0]}] -duty_cycle 50/1 -multiply_by 8 -divide_by 25 -master_clock {pClk50M} [get_pins {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]}] 
create_generated_clock -name {pllmain_inst|altpll_component|auto_generated|pll1|clk[4]} -source [get_pins {pllmain_inst|altpll_component|auto_generated|pll1|inclk[0]}] -duty_cycle 50/1 -multiply_by 4 -divide_by 25 -master_clock {pClk50M} [get_pins {pllmain_inst|altpll_component|auto_generated|pll1|clk[4]}] 
create_generated_clock -name {plldvi_inst|altpll_component|auto_generated|pll1|clk[0]} -source [get_pins {plldvi_inst|altpll_component|auto_generated|pll1|inclk[0]}] -duty_cycle 50/1 -multiply_by 27 -divide_by 50 -master_clock {pClk50M} [get_pins {plldvi_inst|altpll_component|auto_generated|pll1|clk[0]}] 
create_generated_clock -name {plldvi_inst|altpll_component|auto_generated|pll1|clk[1]} -source [get_pins {plldvi_inst|altpll_component|auto_generated|pll1|inclk[0]}] -duty_cycle 50/1 -multiply_by 27 -divide_by 10 -master_clock {pClk50M} [get_pins {plldvi_inst|altpll_component|auto_generated|pll1|clk[1]}] 
create_generated_clock -name {pllpcm48k_inst|altpll_component|auto_generated|pll1|clk[0]} -source [get_pins {pllpcm48k_inst|altpll_component|auto_generated|pll1|inclk[0]}] -duty_cycle 50/1 -multiply_by 1 -divide_by 4 -master_clock {pGPIO1_IN[1]} [get_pins {pllpcm48k_inst|altpll_component|auto_generated|pll1|clk[0]}] 
create_generated_clock -name {pllpcm48k_inst|altpll_component|auto_generated|pll1|clk[1]} -source [get_pins {pllpcm48k_inst|altpll_component|auto_generated|pll1|inclk[0]}] -duty_cycle 50/1 -multiply_by 1 -divide_by 8 -master_clock {pGPIO1_IN[1]} [get_pins {pllpcm48k_inst|altpll_component|auto_generated|pll1|clk[1]}] 
create_generated_clock -name {pllpcm44k1_inst|altpll_component|auto_generated|pll1|clk[0]} -source [get_pins {pllpcm44k1_inst|altpll_component|auto_generated|pll1|inclk[0]}] -duty_cycle 50/1 -multiply_by 17 -divide_by 74 -master_clock {pGPIO1_IN[1]} [get_pins {pllpcm44k1_inst|altpll_component|auto_generated|pll1|clk[0]}] 


#**************************************************************
# Set Clock Latency
#**************************************************************



#**************************************************************
# Set Clock Uncertainty
#**************************************************************

set_clock_uncertainty -rise_from [get_clocks {pllpcm44k1_inst|altpll_component|auto_generated|pll1|clk[0]}] -rise_to [get_clocks {pllpcm44k1_inst|altpll_component|auto_generated|pll1|clk[0]}]  0.020  
set_clock_uncertainty -rise_from [get_clocks {pllpcm44k1_inst|altpll_component|auto_generated|pll1|clk[0]}] -fall_to [get_clocks {pllpcm44k1_inst|altpll_component|auto_generated|pll1|clk[0]}]  0.020  
set_clock_uncertainty -rise_from [get_clocks {pllpcm44k1_inst|altpll_component|auto_generated|pll1|clk[0]}] -rise_to [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]}] -setup 0.160  
set_clock_uncertainty -rise_from [get_clocks {pllpcm44k1_inst|altpll_component|auto_generated|pll1|clk[0]}] -rise_to [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]}] -hold 0.150  
set_clock_uncertainty -rise_from [get_clocks {pllpcm44k1_inst|altpll_component|auto_generated|pll1|clk[0]}] -fall_to [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]}] -setup 0.160  
set_clock_uncertainty -rise_from [get_clocks {pllpcm44k1_inst|altpll_component|auto_generated|pll1|clk[0]}] -fall_to [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]}] -hold 0.150  
set_clock_uncertainty -fall_from [get_clocks {pllpcm44k1_inst|altpll_component|auto_generated|pll1|clk[0]}] -rise_to [get_clocks {pllpcm44k1_inst|altpll_component|auto_generated|pll1|clk[0]}]  0.020  
set_clock_uncertainty -fall_from [get_clocks {pllpcm44k1_inst|altpll_component|auto_generated|pll1|clk[0]}] -fall_to [get_clocks {pllpcm44k1_inst|altpll_component|auto_generated|pll1|clk[0]}]  0.020  
set_clock_uncertainty -fall_from [get_clocks {pllpcm44k1_inst|altpll_component|auto_generated|pll1|clk[0]}] -rise_to [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]}] -setup 0.160  
set_clock_uncertainty -fall_from [get_clocks {pllpcm44k1_inst|altpll_component|auto_generated|pll1|clk[0]}] -rise_to [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]}] -hold 0.150  
set_clock_uncertainty -fall_from [get_clocks {pllpcm44k1_inst|altpll_component|auto_generated|pll1|clk[0]}] -fall_to [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]}] -setup 0.160  
set_clock_uncertainty -fall_from [get_clocks {pllpcm44k1_inst|altpll_component|auto_generated|pll1|clk[0]}] -fall_to [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]}] -hold 0.150  
set_clock_uncertainty -rise_from [get_clocks {pllpcm48k_inst|altpll_component|auto_generated|pll1|clk[1]}] -rise_to [get_clocks {pllpcm48k_inst|altpll_component|auto_generated|pll1|clk[1]}]  0.020  
set_clock_uncertainty -rise_from [get_clocks {pllpcm48k_inst|altpll_component|auto_generated|pll1|clk[1]}] -fall_to [get_clocks {pllpcm48k_inst|altpll_component|auto_generated|pll1|clk[1]}]  0.020  
set_clock_uncertainty -rise_from [get_clocks {pllpcm48k_inst|altpll_component|auto_generated|pll1|clk[1]}] -rise_to [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]}] -setup 0.160  
set_clock_uncertainty -rise_from [get_clocks {pllpcm48k_inst|altpll_component|auto_generated|pll1|clk[1]}] -rise_to [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]}] -hold 0.150  
set_clock_uncertainty -rise_from [get_clocks {pllpcm48k_inst|altpll_component|auto_generated|pll1|clk[1]}] -fall_to [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]}] -setup 0.160  
set_clock_uncertainty -rise_from [get_clocks {pllpcm48k_inst|altpll_component|auto_generated|pll1|clk[1]}] -fall_to [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]}] -hold 0.150  
set_clock_uncertainty -fall_from [get_clocks {pllpcm48k_inst|altpll_component|auto_generated|pll1|clk[1]}] -rise_to [get_clocks {pllpcm48k_inst|altpll_component|auto_generated|pll1|clk[1]}]  0.020  
set_clock_uncertainty -fall_from [get_clocks {pllpcm48k_inst|altpll_component|auto_generated|pll1|clk[1]}] -fall_to [get_clocks {pllpcm48k_inst|altpll_component|auto_generated|pll1|clk[1]}]  0.020  
set_clock_uncertainty -fall_from [get_clocks {pllpcm48k_inst|altpll_component|auto_generated|pll1|clk[1]}] -rise_to [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]}] -setup 0.160  
set_clock_uncertainty -fall_from [get_clocks {pllpcm48k_inst|altpll_component|auto_generated|pll1|clk[1]}] -rise_to [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]}] -hold 0.150  
set_clock_uncertainty -fall_from [get_clocks {pllpcm48k_inst|altpll_component|auto_generated|pll1|clk[1]}] -fall_to [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]}] -setup 0.160  
set_clock_uncertainty -fall_from [get_clocks {pllpcm48k_inst|altpll_component|auto_generated|pll1|clk[1]}] -fall_to [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]}] -hold 0.150  
set_clock_uncertainty -rise_from [get_clocks {pllpcm48k_inst|altpll_component|auto_generated|pll1|clk[0]}] -rise_to [get_clocks {pllpcm48k_inst|altpll_component|auto_generated|pll1|clk[0]}]  0.020  
set_clock_uncertainty -rise_from [get_clocks {pllpcm48k_inst|altpll_component|auto_generated|pll1|clk[0]}] -fall_to [get_clocks {pllpcm48k_inst|altpll_component|auto_generated|pll1|clk[0]}]  0.020  
set_clock_uncertainty -rise_from [get_clocks {pllpcm48k_inst|altpll_component|auto_generated|pll1|clk[0]}] -rise_to [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]}] -setup 0.160  
set_clock_uncertainty -rise_from [get_clocks {pllpcm48k_inst|altpll_component|auto_generated|pll1|clk[0]}] -rise_to [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]}] -hold 0.150  
set_clock_uncertainty -rise_from [get_clocks {pllpcm48k_inst|altpll_component|auto_generated|pll1|clk[0]}] -fall_to [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]}] -setup 0.160  
set_clock_uncertainty -rise_from [get_clocks {pllpcm48k_inst|altpll_component|auto_generated|pll1|clk[0]}] -fall_to [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]}] -hold 0.150  
set_clock_uncertainty -fall_from [get_clocks {pllpcm48k_inst|altpll_component|auto_generated|pll1|clk[0]}] -rise_to [get_clocks {pllpcm48k_inst|altpll_component|auto_generated|pll1|clk[0]}]  0.020  
set_clock_uncertainty -fall_from [get_clocks {pllpcm48k_inst|altpll_component|auto_generated|pll1|clk[0]}] -fall_to [get_clocks {pllpcm48k_inst|altpll_component|auto_generated|pll1|clk[0]}]  0.020  
set_clock_uncertainty -fall_from [get_clocks {pllpcm48k_inst|altpll_component|auto_generated|pll1|clk[0]}] -rise_to [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]}] -setup 0.160  
set_clock_uncertainty -fall_from [get_clocks {pllpcm48k_inst|altpll_component|auto_generated|pll1|clk[0]}] -rise_to [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]}] -hold 0.150  
set_clock_uncertainty -fall_from [get_clocks {pllpcm48k_inst|altpll_component|auto_generated|pll1|clk[0]}] -fall_to [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]}] -setup 0.160  
set_clock_uncertainty -fall_from [get_clocks {pllpcm48k_inst|altpll_component|auto_generated|pll1|clk[0]}] -fall_to [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]}] -hold 0.150  
set_clock_uncertainty -rise_from [get_clocks {plldvi_inst|altpll_component|auto_generated|pll1|clk[1]}] -rise_to [get_clocks {plldvi_inst|altpll_component|auto_generated|pll1|clk[1]}]  0.020  
set_clock_uncertainty -rise_from [get_clocks {plldvi_inst|altpll_component|auto_generated|pll1|clk[1]}] -fall_to [get_clocks {plldvi_inst|altpll_component|auto_generated|pll1|clk[1]}]  0.020  
set_clock_uncertainty -fall_from [get_clocks {plldvi_inst|altpll_component|auto_generated|pll1|clk[1]}] -rise_to [get_clocks {plldvi_inst|altpll_component|auto_generated|pll1|clk[1]}]  0.020  
set_clock_uncertainty -fall_from [get_clocks {plldvi_inst|altpll_component|auto_generated|pll1|clk[1]}] -fall_to [get_clocks {plldvi_inst|altpll_component|auto_generated|pll1|clk[1]}]  0.020  
set_clock_uncertainty -rise_from [get_clocks {plldvi_inst|altpll_component|auto_generated|pll1|clk[0]}] -rise_to [get_clocks {plldvi_inst|altpll_component|auto_generated|pll1|clk[1]}]  0.020  
set_clock_uncertainty -rise_from [get_clocks {plldvi_inst|altpll_component|auto_generated|pll1|clk[0]}] -fall_to [get_clocks {plldvi_inst|altpll_component|auto_generated|pll1|clk[1]}]  0.020  
set_clock_uncertainty -rise_from [get_clocks {plldvi_inst|altpll_component|auto_generated|pll1|clk[0]}] -rise_to [get_clocks {plldvi_inst|altpll_component|auto_generated|pll1|clk[0]}]  0.020  
set_clock_uncertainty -rise_from [get_clocks {plldvi_inst|altpll_component|auto_generated|pll1|clk[0]}] -fall_to [get_clocks {plldvi_inst|altpll_component|auto_generated|pll1|clk[0]}]  0.020  
set_clock_uncertainty -fall_from [get_clocks {plldvi_inst|altpll_component|auto_generated|pll1|clk[0]}] -rise_to [get_clocks {plldvi_inst|altpll_component|auto_generated|pll1|clk[1]}]  0.020  
set_clock_uncertainty -fall_from [get_clocks {plldvi_inst|altpll_component|auto_generated|pll1|clk[0]}] -fall_to [get_clocks {plldvi_inst|altpll_component|auto_generated|pll1|clk[1]}]  0.020  
set_clock_uncertainty -fall_from [get_clocks {plldvi_inst|altpll_component|auto_generated|pll1|clk[0]}] -rise_to [get_clocks {plldvi_inst|altpll_component|auto_generated|pll1|clk[0]}]  0.020  
set_clock_uncertainty -fall_from [get_clocks {plldvi_inst|altpll_component|auto_generated|pll1|clk[0]}] -fall_to [get_clocks {plldvi_inst|altpll_component|auto_generated|pll1|clk[0]}]  0.020  
set_clock_uncertainty -rise_from [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[4]}] -rise_to [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[4]}]  0.020  
set_clock_uncertainty -rise_from [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[4]}] -fall_to [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[4]}]  0.020  
set_clock_uncertainty -rise_from [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[4]}] -rise_to [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]}]  0.020  
set_clock_uncertainty -rise_from [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[4]}] -fall_to [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]}]  0.020  
set_clock_uncertainty -fall_from [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[4]}] -rise_to [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[4]}]  0.020  
set_clock_uncertainty -fall_from [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[4]}] -fall_to [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[4]}]  0.020  
set_clock_uncertainty -fall_from [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[4]}] -rise_to [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]}]  0.020  
set_clock_uncertainty -fall_from [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[4]}] -fall_to [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]}]  0.020  
set_clock_uncertainty -rise_from [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]}] -rise_to [get_clocks {pllpcm48k_inst|altpll_component|auto_generated|pll1|clk[1]}] -setup 0.150  
set_clock_uncertainty -rise_from [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]}] -rise_to [get_clocks {pllpcm48k_inst|altpll_component|auto_generated|pll1|clk[1]}] -hold 0.160  
set_clock_uncertainty -rise_from [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]}] -fall_to [get_clocks {pllpcm48k_inst|altpll_component|auto_generated|pll1|clk[1]}] -setup 0.150  
set_clock_uncertainty -rise_from [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]}] -fall_to [get_clocks {pllpcm48k_inst|altpll_component|auto_generated|pll1|clk[1]}] -hold 0.160  
set_clock_uncertainty -rise_from [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]}] -rise_to [get_clocks {plldvi_inst|altpll_component|auto_generated|pll1|clk[0]}]  0.160  
set_clock_uncertainty -rise_from [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]}] -fall_to [get_clocks {plldvi_inst|altpll_component|auto_generated|pll1|clk[0]}]  0.160  
set_clock_uncertainty -rise_from [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]}] -rise_to [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]}]  0.020  
set_clock_uncertainty -rise_from [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]}] -fall_to [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]}]  0.020  
set_clock_uncertainty -rise_from [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]}] -rise_to [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[0]}]  0.020  
set_clock_uncertainty -rise_from [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]}] -fall_to [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[0]}]  0.020  
set_clock_uncertainty -fall_from [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]}] -rise_to [get_clocks {pllpcm48k_inst|altpll_component|auto_generated|pll1|clk[1]}] -setup 0.150  
set_clock_uncertainty -fall_from [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]}] -rise_to [get_clocks {pllpcm48k_inst|altpll_component|auto_generated|pll1|clk[1]}] -hold 0.160  
set_clock_uncertainty -fall_from [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]}] -fall_to [get_clocks {pllpcm48k_inst|altpll_component|auto_generated|pll1|clk[1]}] -setup 0.150  
set_clock_uncertainty -fall_from [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]}] -fall_to [get_clocks {pllpcm48k_inst|altpll_component|auto_generated|pll1|clk[1]}] -hold 0.160  
set_clock_uncertainty -fall_from [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]}] -rise_to [get_clocks {plldvi_inst|altpll_component|auto_generated|pll1|clk[0]}]  0.160  
set_clock_uncertainty -fall_from [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]}] -fall_to [get_clocks {plldvi_inst|altpll_component|auto_generated|pll1|clk[0]}]  0.160  
set_clock_uncertainty -fall_from [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]}] -rise_to [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]}]  0.020  
set_clock_uncertainty -fall_from [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]}] -fall_to [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]}]  0.020  
set_clock_uncertainty -fall_from [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]}] -rise_to [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[0]}]  0.020  
set_clock_uncertainty -fall_from [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]}] -fall_to [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[0]}]  0.020  
set_clock_uncertainty -rise_from [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[0]}] -rise_to [get_clocks {plldvi_inst|altpll_component|auto_generated|pll1|clk[0]}]  0.160  
set_clock_uncertainty -rise_from [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[0]}] -fall_to [get_clocks {plldvi_inst|altpll_component|auto_generated|pll1|clk[0]}]  0.160  
set_clock_uncertainty -rise_from [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[0]}] -rise_to [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]}]  0.020  
set_clock_uncertainty -rise_from [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[0]}] -fall_to [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]}]  0.020  
set_clock_uncertainty -rise_from [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[0]}] -rise_to [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[0]}]  0.020  
set_clock_uncertainty -rise_from [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[0]}] -fall_to [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[0]}]  0.020  
set_clock_uncertainty -fall_from [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[0]}] -rise_to [get_clocks {plldvi_inst|altpll_component|auto_generated|pll1|clk[0]}]  0.160  
set_clock_uncertainty -fall_from [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[0]}] -fall_to [get_clocks {plldvi_inst|altpll_component|auto_generated|pll1|clk[0]}]  0.160  
set_clock_uncertainty -fall_from [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[0]}] -rise_to [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]}]  0.020  
set_clock_uncertainty -fall_from [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[0]}] -fall_to [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[3]}]  0.020  
set_clock_uncertainty -fall_from [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[0]}] -rise_to [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[0]}]  0.020  
set_clock_uncertainty -fall_from [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[0]}] -fall_to [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[0]}]  0.020  
set_clock_uncertainty -rise_from [get_clocks {pGPIO1_IN[0]}] -rise_to [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[0]}] -setup 0.080  
set_clock_uncertainty -rise_from [get_clocks {pGPIO1_IN[0]}] -rise_to [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[0]}] -hold 0.110  
set_clock_uncertainty -rise_from [get_clocks {pGPIO1_IN[0]}] -fall_to [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[0]}] -setup 0.080  
set_clock_uncertainty -rise_from [get_clocks {pGPIO1_IN[0]}] -fall_to [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[0]}] -hold 0.110  
set_clock_uncertainty -fall_from [get_clocks {pGPIO1_IN[0]}] -rise_to [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[0]}] -setup 0.080  
set_clock_uncertainty -fall_from [get_clocks {pGPIO1_IN[0]}] -rise_to [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[0]}] -hold 0.110  
set_clock_uncertainty -fall_from [get_clocks {pGPIO1_IN[0]}] -fall_to [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[0]}] -setup 0.080  
set_clock_uncertainty -fall_from [get_clocks {pGPIO1_IN[0]}] -fall_to [get_clocks {pllmain_inst|altpll_component|auto_generated|pll1|clk[0]}] -hold 0.110  


#**************************************************************
# Set Input Delay
#**************************************************************



#**************************************************************
# Set Output Delay
#**************************************************************



#**************************************************************
# Set Clock Groups
#**************************************************************



#**************************************************************
# Set False Path
#**************************************************************



#**************************************************************
# Set Multicycle Path
#**************************************************************



#**************************************************************
# Set Maximum Delay
#**************************************************************



#**************************************************************
# Set Minimum Delay
#**************************************************************



#**************************************************************
# Set Input Transition
#**************************************************************

