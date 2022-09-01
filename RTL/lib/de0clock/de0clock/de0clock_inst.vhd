	component de0clock is
		port (
			ref_clk_clk        : in  std_logic := 'X'; -- clk
			ref_reset_reset    : in  std_logic := 'X'; -- reset
			sys_clk_clk        : out std_logic;        -- clk
			sdram_clk_clk      : out std_logic;        -- clk
			reset_source_reset : out std_logic         -- reset
		);
	end component de0clock;

	u0 : component de0clock
		port map (
			ref_clk_clk        => CONNECTED_TO_ref_clk_clk,        --      ref_clk.clk
			ref_reset_reset    => CONNECTED_TO_ref_reset_reset,    --    ref_reset.reset
			sys_clk_clk        => CONNECTED_TO_sys_clk_clk,        --      sys_clk.clk
			sdram_clk_clk      => CONNECTED_TO_sdram_clk_clk,      --    sdram_clk.clk
			reset_source_reset => CONNECTED_TO_reset_source_reset  -- reset_source.reset
		);

