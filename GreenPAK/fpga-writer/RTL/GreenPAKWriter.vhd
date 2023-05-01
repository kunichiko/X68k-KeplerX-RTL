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
		pGPIO0_09 : inout std_logic;
		pGPIO0_04 : inout std_logic;
		pGPIO0_01 : inout std_logic;
		pGPIO0_00 : inout std_logic;
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
			reset_reset_n : in std_logic := 'X'; -- reset_n
			pio_dipsw_external_connection_export : in std_logic_vector(3 downto 0) := (others => 'X'); -- export
			pio_led_external_connection_export : out std_logic_vector(7 downto 0) -- export
		);
	end component nios2_system;

	signal sys_rstn : std_logic;
	signal nios2_dipsw : std_logic_vector(3 downto 0);
	signal nios2_led : std_logic_vector(7 downto 0);

	signal led_counter_50m : std_logic_vector(23 downto 0);

begin

	u0 : component nios2_system port map(
		clk_clk => pClk50M, --                           clk.clk
		reset_reset_n => sys_rstn, --                         reset.reset_n
		pio_dipsw_external_connection_export => nios2_dipsw, -- pio_dipsw_external_connection.export
		pio_led_external_connection_export => nios2_led --   pio_led_external_connection.export
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

	
end rtl;