SOURCES =  X68KeplerX_pkg.vhd lib/i2c/I2C_pkg.vhd \
	X68KeplerX.vhd ym2151/OPM_IKAOPM.vhd \
	adpcm/e6258.vhd adpcm/calcadpcm.vhd \
  	peripheral/e8255.vhd \
	mercury/eMercury.vhd mercury/opna_adpcm_rom.vhd \
	midi/em3802.vhd midi/midi_ctrl.vhd \
	lib/i2s/i2s_encoder.vhd lib/i2s/i2s_decoder.vhd \
	lib/addsat/addsat.vhd lib/addsat/addsat_16.vhd lib/datfifo.vhd lib/txframe.vhd lib/rxframe.vhd lib/sftclk.vhd \
	lib/i2c/I2CIF.vhd lib/i2c/I2C_MUX.vhd lib/i2c/I2C_MUX_PROXY.vhd \
	lib/wm8804/wm8804.vhd \
	lib/greenpak_eeprom/greenpak_eeprom.vhd lib/greenpak_eeprom/ram_8x256.vhd \
	lib/crc16_ccitt.vhd \
	exmemory/exmemory.vhd \
	submodules/spi-fpga/rtl/spi_slave.vhd
