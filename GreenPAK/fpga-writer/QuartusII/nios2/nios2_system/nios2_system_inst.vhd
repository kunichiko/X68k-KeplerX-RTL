	component nios2_system is
		port (
			clk_clk                              : in  std_logic                    := 'X';             -- clk
			pio_dipsw_external_connection_export : in  std_logic_vector(3 downto 0) := (others => 'X'); -- export
			pio_led_external_connection_export   : out std_logic_vector(7 downto 0);                    -- export
			reset_reset_n                        : in  std_logic                    := 'X'              -- reset_n
		);
	end component nios2_system;

	u0 : component nios2_system
		port map (
			clk_clk                              => CONNECTED_TO_clk_clk,                              --                           clk.clk
			pio_dipsw_external_connection_export => CONNECTED_TO_pio_dipsw_external_connection_export, -- pio_dipsw_external_connection.export
			pio_led_external_connection_export   => CONNECTED_TO_pio_led_external_connection_export,   --   pio_led_external_connection.export
			reset_reset_n                        => CONNECTED_TO_reset_reset_n                         --                         reset.reset_n
		);

