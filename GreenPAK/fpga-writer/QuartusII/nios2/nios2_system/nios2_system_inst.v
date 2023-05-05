	nios2_system u0 (
		.clk_clk                                 (<connected-to-clk_clk>),                                 //                              clk.clk
		.i2c_master_sda_in                       (<connected-to-i2c_master_sda_in>),                       //                       i2c_master.sda_in
		.i2c_master_scl_in                       (<connected-to-i2c_master_scl_in>),                       //                                 .scl_in
		.i2c_master_sda_oe                       (<connected-to-i2c_master_sda_oe>),                       //                                 .sda_oe
		.i2c_master_scl_oe                       (<connected-to-i2c_master_scl_oe>),                       //                                 .scl_oe
		.pio_dipsw_external_connection_export    (<connected-to-pio_dipsw_external_connection_export>),    //    pio_dipsw_external_connection.export
		.pio_led_external_connection_export      (<connected-to-pio_led_external_connection_export>),      //      pio_led_external_connection.export
		.pio_scroll_y_external_connection_export (<connected-to-pio_scroll_y_external_connection_export>), // pio_scroll_y_external_connection.export
		.reset_reset_n                           (<connected-to-reset_reset_n>),                           //                            reset.reset_n
		.textram_address                         (<connected-to-textram_address>),                         //                          textram.address
		.textram_chipselect                      (<connected-to-textram_chipselect>),                      //                                 .chipselect
		.textram_clken                           (<connected-to-textram_clken>),                           //                                 .clken
		.textram_write                           (<connected-to-textram_write>),                           //                                 .write
		.textram_readdata                        (<connected-to-textram_readdata>),                        //                                 .readdata
		.textram_writedata                       (<connected-to-textram_writedata>)                        //                                 .writedata
	);

