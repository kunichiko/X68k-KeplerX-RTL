
module nios2_system (
	clk_clk,
	i2c_master_sda_in,
	i2c_master_scl_in,
	i2c_master_sda_oe,
	i2c_master_scl_oe,
	i2c_slave_conduit_data_in,
	i2c_slave_conduit_clk_in,
	i2c_slave_conduit_data_oe,
	i2c_slave_conduit_clk_oe,
	pio_dipsw_external_connection_export,
	pio_led_external_connection_export,
	reset_reset_n);	

	input		clk_clk;
	input		i2c_master_sda_in;
	input		i2c_master_scl_in;
	output		i2c_master_sda_oe;
	output		i2c_master_scl_oe;
	input		i2c_slave_conduit_data_in;
	input		i2c_slave_conduit_clk_in;
	output		i2c_slave_conduit_data_oe;
	output		i2c_slave_conduit_clk_oe;
	input	[3:0]	pio_dipsw_external_connection_export;
	output	[7:0]	pio_led_external_connection_export;
	input		reset_reset_n;
endmodule
