	de0clock u0 (
		.ref_clk_clk        (<connected-to-ref_clk_clk>),        //      ref_clk.clk
		.ref_reset_reset    (<connected-to-ref_reset_reset>),    //    ref_reset.reset
		.sys_clk_clk        (<connected-to-sys_clk_clk>),        //      sys_clk.clk
		.sdram_clk_clk      (<connected-to-sdram_clk_clk>),      //    sdram_clk.clk
		.reset_source_reset (<connected-to-reset_source_reset>)  // reset_source.reset
	);

