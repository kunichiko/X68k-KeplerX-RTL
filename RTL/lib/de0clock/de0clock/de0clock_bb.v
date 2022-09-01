
module de0clock (
	ref_clk_clk,
	ref_reset_reset,
	sys_clk_clk,
	sdram_clk_clk,
	reset_source_reset);	

	input		ref_clk_clk;
	input		ref_reset_reset;
	output		sys_clk_clk;
	output		sdram_clk_clk;
	output		reset_source_reset;
endmodule
