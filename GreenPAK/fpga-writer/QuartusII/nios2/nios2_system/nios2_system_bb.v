
module nios2_system (
	clk_clk,
	i2c_master_sda_in,
	i2c_master_scl_in,
	i2c_master_sda_oe,
	i2c_master_scl_oe,
	pio_dipsw_external_connection_export,
	pio_led_external_connection_export,
	pio_scroll_y_external_connection_export,
	reset_reset_n,
	textram_address,
	textram_chipselect,
	textram_clken,
	textram_write,
	textram_readdata,
	textram_writedata);	

	input		clk_clk;
	input		i2c_master_sda_in;
	input		i2c_master_scl_in;
	output		i2c_master_sda_oe;
	output		i2c_master_scl_oe;
	input	[3:0]	pio_dipsw_external_connection_export;
	output	[7:0]	pio_led_external_connection_export;
	output	[7:0]	pio_scroll_y_external_connection_export;
	input		reset_reset_n;
	input	[12:0]	textram_address;
	input		textram_chipselect;
	input		textram_clken;
	input		textram_write;
	output	[7:0]	textram_readdata;
	input	[7:0]	textram_writedata;
endmodule
