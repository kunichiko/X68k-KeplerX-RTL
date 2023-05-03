library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.STD_LOGIC_ARITH.all;
use IEEE.STD_LOGIC_UNSIGNED.all;
use work.I2C_pkg.all;

entity GreenPAKWriter is
	port (
		pClk50M : in std_logic;

		-- //////////// LED //////////
		pLED : out std_logic_vector(7 downto 0);

		-- //////////// KEY //////////
		pKEY : in std_logic_vector(1 downto 0);

		-- //////////// SW //////////
		pSW : in std_logic_vector(3 downto 0);

		-- //////////// SDRAM //////////
		pDRAM_ADDR : out std_logic_vector(12 downto 0);
		pDRAM_BA : out std_logic_vector(1 downto 0);
		pDRAM_CAS_N : out std_logic;
		pDRAM_CKE : out std_logic;
		pDRAM_CLK : out std_logic;
		pDRAM_CS_N : out std_logic;
		pDRAM_DQ : inout std_logic_vector(15 downto 0);
		pDRAM_DQM : out std_logic_vector(1 downto 0);
		pDRAM_RAS_N : out std_logic;
		pDRAM_WE_N : out std_logic;

		-- //////////// EPCS //////////
		pEPCS_ASDO : out std_logic;
		pEPCS_DATA0 : in std_logic;
		pEPCS_DCLK : out std_logic;
		pEPCS_NCSO : out std_logic;

		-- //////////// Accelerometer and EEPROM //////////
		pG_SENSOR_CS_N : out std_logic;
		pG_SENSOR_INT : in std_logic;
		pI2C_SCLK : out std_logic;
		pI2C_SDAT : in std_logic;

		-- //////////// ADC //////////
		pADC_CS_N : out std_logic;
		pADC_SADDR : out std_logic;
		pADC_SCLK : out std_logic;
		pADC_SDAT : in std_logic;

		-- //////////// 2x13 GPIO Header //////////
		pGPIO2 : inout std_logic_vector(12 downto 0);
		pGPIO2_IN : in std_logic_vector(2 downto 0);

		-- //////////// GPIO_0, GPIO_0 connect to GPIO Default //////////
		pGPIO0 : inout std_logic_vector(33 downto 12);
		pGPIO0_09 : inout std_logic; -- I2C SDA (master)
		pGPIO0_04 : inout std_logic; -- I2C SCL (master)
		pGPIO0_01 : inout std_logic; -- I2C SDA (slave)
		pGPIO0_00 : inout std_logic; -- I2C SCL (slave)
		pGPIO0_IN : in std_logic_vector(1 downto 0);
		pGPIO0_HDMI_CLK : out std_logic; -- GPIO0(10,11)
		pGPIO0_HDMI_DATA0 : out std_logic; -- GPIO0(7,8)
		pGPIO0_HDMI_DATA1 : out std_logic; -- GPIO0(5,6)
		pGPIO0_HDMI_DATA2 : out std_logic; -- GPIO0(3,2)

		-- //////////// GPIO_1, GPIO_1 connect to GPIO Default //////////
		pGPIO1 : inout std_logic_vector(33 downto 0);
		pGPIO1_IN : in std_logic_vector(1 downto 0)
	);
end GreenPAKWriter;

architecture rtl of GreenPAKWriter is

	constant sysclk_freq : integer := 25000;
	component nios2_system is
		port (
			clk_clk : in std_logic := 'X'; -- clk
			pio_dipsw_external_connection_export : in std_logic_vector(3 downto 0) := (others => 'X'); -- export
			pio_led_external_connection_export : out std_logic_vector(7 downto 0); -- export
			reset_reset_n : in std_logic := 'X'; -- reset_n
			i2c_master_sda_in : in std_logic := 'X'; -- sda_in
			i2c_master_scl_in : in std_logic := 'X'; -- scl_in
			i2c_master_sda_oe : out std_logic; -- sda_oe
			i2c_master_scl_oe : out std_logic; -- scl_oe
			i2c_slave_conduit_data_in : in std_logic := 'X'; -- conduit_data_in
			i2c_slave_conduit_clk_in : in std_logic := 'X'; -- conduit_clk_in
			i2c_slave_conduit_data_oe : out std_logic; -- conduit_data_oe
			i2c_slave_conduit_clk_oe : out std_logic; -- conduit_clk_oe
			textram_address : in std_logic_vector(12 downto 0) := (others => 'X'); -- address
			textram_chipselect : in std_logic := 'X'; -- chipselect
			textram_clken : in std_logic := 'X'; -- clken
			textram_write : in std_logic := 'X'; -- write
			textram_readdata : out std_logic_vector(7 downto 0); -- readdata
			textram_writedata : in std_logic_vector(7 downto 0) := (others => 'X'); -- writedata
			pio_scroll_y_external_connection_export : out std_logic_vector(7 downto 0) := (others => 'X') -- export
		);
	end component nios2_system;

	signal sys_clk : std_logic;
	signal sys_rstn : std_logic;

	signal pllrst : std_logic;
	signal plllock_dvi : std_logic;

	signal nios2_dipsw : std_logic_vector(3 downto 0);
	signal nios2_led : std_logic_vector(7 downto 0);

	signal nios2_i2c_master_sda_in : std_logic;
	signal nios2_i2c_master_scl_in : std_logic;
	signal nios2_i2c_master_sda_oe : std_logic;
	signal nios2_i2c_master_scl_oe : std_logic;

	signal nios2_i2c_slave_sda_in : std_logic;
	signal nios2_i2c_slave_scl_in : std_logic;
	signal nios2_i2c_slave_sda_oe : std_logic;
	signal nios2_i2c_slave_scl_oe : std_logic;

	signal nios2_textram_address : std_logic_vector(12 downto 0);
	signal nios2_textram_chipselect : std_logic;
	signal nios2_textram_clken : std_logic;
	signal nios2_textram_write : std_logic;
	signal nios2_textram_readdata : std_logic_vector(7 downto 0);
	signal nios2_textram_writedata : std_logic_vector(7 downto 0);
	signal nios2_scroll_y : std_logic_vector(7 downto 0);

	signal led_counter_50m : std_logic_vector(23 downto 0);

	--
	-- HDMI
	--
	type audio_sample_word_t is array (1 downto 0) of std_logic_vector(15 downto 0);

	component plldvi is
		port (
			areset : in std_logic := '0';
			inclk0 : in std_logic := '0';
			c0 : out std_logic; -- DVI  : 27MHz
			c1 : out std_logic; -- DVIx5: 153MHz
			c2 : out std_logic; -- sys_clk : 54MHz
			locked : out std_logic
		);
	end component;

	component hdmi
		generic (
			VIDEO_ID_CODE : integer := 1;
			BIT_WIDTH : integer := 10;
			BIT_HEIGHT : integer := 10;
			VIDEO_REFRESH_RATE : real := 59.94;
			AUDIO_RATE : integer := 48000;
			AUDIO_BIT_WIDTH : integer := 16;
			VENDOR_NAME : std_logic_vector(63 downto 0);
			PRODUCT_DESCRIPTION : std_logic_vector(127 downto 0)
		);
		port (
			clk_pixel_x5 : in std_logic;
			clk_pixel : in std_logic;
			clk_audio : in std_logic;
			reset : in std_logic;
			rgb : in std_logic_vector(23 downto 0);
			audio_sample_word : in audio_sample_word_t;

			tmds : out std_logic_vector(2 downto 0);
			tmds_clock : out std_logic;

			cx : out std_logic_vector(BIT_WIDTH - 1 downto 0);
			cy : out std_logic_vector(BIT_HEIGHT - 1 downto 0);

			frame_width : out std_logic_vector(BIT_WIDTH - 1 downto 0);
			frame_height : out std_logic_vector(BIT_HEIGHT - 1 downto 0);
			screen_width : out std_logic_vector(BIT_WIDTH - 1 downto 0);
			screen_height : out std_logic_vector(BIT_HEIGHT - 1 downto 0)
		);
	end component;

	component console is
		generic (
			BIT_WIDTH : integer := 12;
			BIT_HEIGHT : integer := 11;
			FONT_WIDTH : integer := 8;
			FONT_HEIGHT : integer := 16
		);
		port (
			clk_pixel : in std_logic;
			codepoint : in std_logic_vector(7 downto 0);
			charattr : in std_logic_vector(7 downto 0);
			cx : in std_logic_vector(BIT_WIDTH - 1 downto 0);
			cy : in std_logic_vector(BIT_HEIGHT - 1 downto 0);
			rgb : out std_logic_vector(23 downto 0)
		);
	end component;

	signal hdmi_clk : std_logic; -- 27MHz
	signal hdmi_clk_x5 : std_logic; -- 135MHz
	signal hdmi_rst : std_logic;
	signal hdmi_rgb : std_logic_vector(23 downto 0);
	signal hdmi_tmds : std_logic_vector(2 downto 0);
	signal hdmi_tmdsclk : std_logic;
	signal hdmi_cx : std_logic_vector(9 downto 0);
	signal hdmi_cy : std_logic_vector(9 downto 0);
	signal hdmi_cx_d : std_logic_vector(9 downto 0);
	signal hdmi_cy_d : std_logic_vector(9 downto 0);

	signal hdmi_test_r : std_logic_vector(7 downto 0);
	signal hdmi_test_g : std_logic_vector(7 downto 0);
	signal hdmi_test_b : std_logic_vector(7 downto 0);

	signal console_char : std_logic_vector(7 downto 0);
begin

	plldvi_inst : plldvi port map(
		areset => pllrst,
		inclk0 => pClk50M,
		c0 => hdmi_clk, -- 27MHz
		c1 => hdmi_clk_x5, -- 135MHz
		c2 => sys_clk, -- 54MHz
		locked => plllock_dvi
	);

	sys_rstn <= pKEY(0) and plllock_dvi;

	u0 : component nios2_system port map(
		clk_clk => sys_clk, --                           clk.clk
		pio_dipsw_external_connection_export => nios2_dipsw, -- pio_dipsw_external_connection.export
		pio_led_external_connection_export => nios2_led, --   pio_led_external_connection.export
		reset_reset_n => sys_rstn, --                         reset.reset_n
		i2c_master_sda_in => nios2_i2c_master_sda_in, --                    i2c_master.sda_in
		i2c_master_scl_in => nios2_i2c_master_scl_in, --                              .scl_in
		i2c_master_sda_oe => nios2_i2c_master_sda_oe, --                              .sda_oe
		i2c_master_scl_oe => nios2_i2c_master_scl_oe, --                              .scl_oe
		i2c_slave_conduit_data_in => nios2_i2c_slave_sda_in, --                     i2c_slave.conduit_data_in
		i2c_slave_conduit_clk_in => nios2_i2c_slave_scl_in, --                              .conduit_clk_in
		i2c_slave_conduit_data_oe => nios2_i2c_slave_sda_oe, --                              .conduit_data_oe
		i2c_slave_conduit_clk_oe => nios2_i2c_slave_scl_oe, --                              .conduit_clk_oe
		textram_address => nios2_textram_address, --                       textram.address
		textram_chipselect => nios2_textram_chipselect, --                              .chipselect
		textram_clken => nios2_textram_clken, --                              .clken
		textram_write => nios2_textram_write, --                              .write
		textram_readdata => nios2_textram_readdata, --                              .readdata
		textram_writedata => nios2_textram_writedata,
		pio_scroll_y_external_connection_export => nios2_scroll_y
	);

	nios2_dipsw <= pKEY(1) & pSW(2 downto 0);
	pLED(6 downto 0) <= nios2_led(6 downto 0);
	pLED(7) <= led_counter_50m(23);
	process (sys_clk, sys_rstn)
	begin
		if (sys_rstn = '0') then
			led_counter_50m <= (others => '0');
		elsif (sys_clk' event and sys_clk = '1') then
			led_counter_50m <= led_counter_50m + 1;
		end if;
	end process;

	pGPIO0_09 <=
		'0' when nios2_i2c_master_sda_oe = '1' else
		'0' when nios2_i2c_slave_sda_oe = '1' else
		'Z';
	nios2_i2c_master_sda_in <= pGPIO0_09;
	nios2_i2c_slave_sda_in <= pGPIO0_09;

	pGPIO0_04 <=
		'0' when nios2_i2c_master_scl_oe = '1' else
		'0' when nios2_i2c_slave_sda_oe = '1' else
		'Z';
	nios2_i2c_master_scl_in <= pGPIO0_04;
	nios2_i2c_slave_scl_in <= pGPIO0_04;

	--
	-- DVI output
	--

	hdmi0 : hdmi
	generic map(
		VIDEO_ID_CODE => 17,
		BIT_WIDTH => 10,
		BIT_HEIGHT => 10,
		VIDEO_REFRESH_RATE => 50.0,
		AUDIO_RATE => 48000,
		AUDIO_BIT_WIDTH => 16,
		VENDOR_NAME => x"4B756E692E000000", -- "Kuni."
		PRODUCT_DESCRIPTION => x"4B65706C65702D580000000000000000" -- "Kepler-X"
	)
	port map(
		clk_pixel_x5 => hdmi_clk_x5,
		clk_pixel => hdmi_clk,
		clk_audio => '0',
		reset => hdmi_rst,
		rgb => hdmi_rgb,
		audio_sample_word => (others => (others => '0')),

		tmds => hdmi_tmds,
		tmds_clock => hdmi_tmdsclk,

		cx => hdmi_cx,
		cy => hdmi_cy,

		frame_width => open,
		frame_height => open,
		screen_width => open,
		screen_height => open
	);

	pllrst <= '0';
	hdmi_rst <= not sys_rstn;

	pGPIO0_HDMI_CLK <= hdmi_tmdsclk;
	pGPIO0_HDMI_DATA0 <= hdmi_tmds(0);
	pGPIO0_HDMI_DATA1 <= hdmi_tmds(1);
	pGPIO0_HDMI_DATA2 <= hdmi_tmds(2);

	console0 : console
	generic map(
		BIT_WIDTH => 10,
		BIT_HEIGHT => 10,
		FONT_WIDTH => 8,
		FONT_HEIGHT => 16
	)
	port map(
		clk_pixel => hdmi_clk,
		codepoint => console_char,
		charattr => "0" & "001" & "1111", -- blink & bgcolor & fgcolor
		cx => hdmi_cx,
		cy => hdmi_cy,
		rgb => hdmi_rgb
	);

	nios2_textram_clken <= '1';
	nios2_textram_chipselect <= '1';

	process (sys_clk, sys_rstn)
		variable texty : std_logic_vector(5 downto 0);
	begin
		if (sys_rstn = '0') then
			nios2_textram_address <= (others => '0');
			console_char <= x"20";
		elsif (sys_clk' event and sys_clk = '1') then
			hdmi_cx_d <= hdmi_cx;
			hdmi_cy_d <= hdmi_cy;

			texty := hdmi_cy_d(9 downto 4) + nios2_scroll_y(5 downto 0);
			nios2_textram_address <= texty & hdmi_cx_d(9 downto 3);
			if (hdmi_cx_d(2 downto 0) = "111") then
				if (hdmi_cx_d(9 downto 3) < 88) then
					console_char <= nios2_textram_readdata;
				else
					console_char <= x"20";
				end if;
			end if;
		end if;
	end process;

end rtl;