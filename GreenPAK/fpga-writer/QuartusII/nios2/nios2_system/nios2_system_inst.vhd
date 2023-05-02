	component nios2_system is
		port (
			clk_clk                              : in  std_logic                     := 'X';             -- clk
			i2c_master_sda_in                    : in  std_logic                     := 'X';             -- sda_in
			i2c_master_scl_in                    : in  std_logic                     := 'X';             -- scl_in
			i2c_master_sda_oe                    : out std_logic;                                        -- sda_oe
			i2c_master_scl_oe                    : out std_logic;                                        -- scl_oe
			i2c_slave_conduit_data_in            : in  std_logic                     := 'X';             -- conduit_data_in
			i2c_slave_conduit_clk_in             : in  std_logic                     := 'X';             -- conduit_clk_in
			i2c_slave_conduit_data_oe            : out std_logic;                                        -- conduit_data_oe
			i2c_slave_conduit_clk_oe             : out std_logic;                                        -- conduit_clk_oe
			pio_dipsw_external_connection_export : in  std_logic_vector(3 downto 0)  := (others => 'X'); -- export
			pio_led_external_connection_export   : out std_logic_vector(7 downto 0);                     -- export
			reset_reset_n                        : in  std_logic                     := 'X';             -- reset_n
			textram_address                      : in  std_logic_vector(12 downto 0) := (others => 'X'); -- address
			textram_chipselect                   : in  std_logic                     := 'X';             -- chipselect
			textram_clken                        : in  std_logic                     := 'X';             -- clken
			textram_write                        : in  std_logic                     := 'X';             -- write
			textram_readdata                     : out std_logic_vector(7 downto 0);                     -- readdata
			textram_writedata                    : in  std_logic_vector(7 downto 0)  := (others => 'X')  -- writedata
		);
	end component nios2_system;

	u0 : component nios2_system
		port map (
			clk_clk                              => CONNECTED_TO_clk_clk,                              --                           clk.clk
			i2c_master_sda_in                    => CONNECTED_TO_i2c_master_sda_in,                    --                    i2c_master.sda_in
			i2c_master_scl_in                    => CONNECTED_TO_i2c_master_scl_in,                    --                              .scl_in
			i2c_master_sda_oe                    => CONNECTED_TO_i2c_master_sda_oe,                    --                              .sda_oe
			i2c_master_scl_oe                    => CONNECTED_TO_i2c_master_scl_oe,                    --                              .scl_oe
			i2c_slave_conduit_data_in            => CONNECTED_TO_i2c_slave_conduit_data_in,            --                     i2c_slave.conduit_data_in
			i2c_slave_conduit_clk_in             => CONNECTED_TO_i2c_slave_conduit_clk_in,             --                              .conduit_clk_in
			i2c_slave_conduit_data_oe            => CONNECTED_TO_i2c_slave_conduit_data_oe,            --                              .conduit_data_oe
			i2c_slave_conduit_clk_oe             => CONNECTED_TO_i2c_slave_conduit_clk_oe,             --                              .conduit_clk_oe
			pio_dipsw_external_connection_export => CONNECTED_TO_pio_dipsw_external_connection_export, -- pio_dipsw_external_connection.export
			pio_led_external_connection_export   => CONNECTED_TO_pio_led_external_connection_export,   --   pio_led_external_connection.export
			reset_reset_n                        => CONNECTED_TO_reset_reset_n,                        --                         reset.reset_n
			textram_address                      => CONNECTED_TO_textram_address,                      --                       textram.address
			textram_chipselect                   => CONNECTED_TO_textram_chipselect,                   --                              .chipselect
			textram_clken                        => CONNECTED_TO_textram_clken,                        --                              .clken
			textram_write                        => CONNECTED_TO_textram_write,                        --                              .write
			textram_readdata                     => CONNECTED_TO_textram_readdata,                     --                              .readdata
			textram_writedata                    => CONNECTED_TO_textram_writedata                     --                              .writedata
		);

