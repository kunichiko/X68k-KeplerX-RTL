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
			clk_clk                              : in  std_logic                    := 'X';             -- clk
			pio_dipsw_external_connection_export : in  std_logic_vector(3 downto 0) := (others => 'X'); -- export
			pio_led_external_connection_export   : out std_logic_vector(7 downto 0);                    -- export
			reset_reset_n                        : in  std_logic                    := 'X';             -- reset_n
			i2c_master_sda_in                    : in  std_logic                    := 'X';             -- sda_in
			i2c_master_scl_in                    : in  std_logic                    := 'X';             -- scl_in
			i2c_master_sda_oe                    : out std_logic;                                       -- sda_oe
			i2c_master_scl_oe                    : out std_logic;                                       -- scl_oe
			i2c_slave_conduit_data_in            : in  std_logic                    := 'X';             -- conduit_data_in
			i2c_slave_conduit_clk_in             : in  std_logic                    := 'X';             -- conduit_clk_in
			i2c_slave_conduit_data_oe            : out std_logic;                                       -- conduit_data_oe
			i2c_slave_conduit_clk_oe             : out std_logic                                        -- conduit_clk_oe
		);
	end component nios2_system;

	signal sys_rstn : std_logic;
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

	signal led_counter_50m : std_logic_vector(23 downto 0);

begin

	u0 : component nios2_system
		port map (
			clk_clk                              => pClk50M,                              --                           clk.clk
			pio_dipsw_external_connection_export => nios2_dipsw, -- pio_dipsw_external_connection.export
			pio_led_external_connection_export   => nios2_led,   --   pio_led_external_connection.export
			reset_reset_n                        => sys_rstn,                        --                         reset.reset_n
			i2c_master_sda_in                    => nios2_i2c_master_sda_in,                    --                    i2c_master.sda_in
			i2c_master_scl_in                    => nios2_i2c_master_scl_in,                    --                              .scl_in
			i2c_master_sda_oe                    => nios2_i2c_master_sda_oe,                    --                              .sda_oe
			i2c_master_scl_oe                    => nios2_i2c_master_scl_oe,                    --                              .scl_oe
			i2c_slave_conduit_data_in            => nios2_i2c_slave_sda_in,            --                     i2c_slave.conduit_data_in
			i2c_slave_conduit_clk_in             => nios2_i2c_slave_scl_in,             --                              .conduit_clk_in
			i2c_slave_conduit_data_oe            => nios2_i2c_slave_sda_oe,            --                              .conduit_data_oe
			i2c_slave_conduit_clk_oe             => nios2_i2c_slave_scl_oe              --                              .conduit_clk_oe
		);


	nios2_dipsw <= pKEY(1) & pSW(2 downto 0);
	pLED(6 downto 0) <= nios2_led(6 downto 0);
	pLED(7) <= led_counter_50m(23);

	sys_rstn <= pKEY(0);

	process (pClk50M, sys_rstn)
	begin
		if (sys_rstn = '0') then
			led_counter_50m <= (others => '0');
		elsif (pClk50M' event and pClk50M = '1') then
			led_counter_50m <= led_counter_50m + 1;
		end if;
	end process;

	pGPIO0_09 <= '0' when nios2_i2c_master_sda_oe = '1' else 'Z';
	nios2_i2c_master_sda_in <= pGPIO0_09;
	pGPIO0_04 <= '0' when nios2_i2c_master_scl_oe = '1' else 'Z';
	nios2_i2c_master_scl_in <= pGPIO0_04;

	pGPIO0_01 <= '0' when nios2_i2c_slave_sda_oe = '1' else 'Z';
	nios2_i2c_slave_sda_in <= pGPIO0_01;
	pGPIO0_00 <= '0' when nios2_i2c_slave_scl_oe = '1' else 'Z';
	nios2_i2c_slave_scl_in <= pGPIO0_00;
	
end rtl;