
module nios2_system (
	clk_clk,
	pio_dipsw_external_connection_export,
	pio_led_external_connection_export,
	reset_reset_n);	

	input		clk_clk;
	input	[3:0]	pio_dipsw_external_connection_export;
	output	[7:0]	pio_led_external_connection_export;
	input		reset_reset_n;
endmodule
