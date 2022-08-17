library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.STD_LOGIC_ARITH.all;
use IEEE.STD_LOGIC_UNSIGNED.all;

entity X68KeplerX is
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
		pGPIO_2 : inout std_logic_vector(12 downto 0);
		pGPIO_2_IN : in std_logic_vector(2 downto 0);

		-- //////////// GPIO_0, GPIO_0 connect to GPIO Default //////////
		pGPIO0 : inout std_logic_vector(33 downto 0);
		pGPIO0_IN : in std_logic_vector(1 downto 0);

		-- //////////// GPIO_1, GPIO_1 connect to GPIO Default //////////
		pGPIO1 : inout std_logic_vector(33 downto 0);
		pGPIO1_IN : in std_logic_vector(1 downto 0)
	);
end X68KeplerX;

architecture rtl of X68KeplerX is

	signal clk10m : std_logic;
	signal srstn : std_logic;

	signal pllrst : std_logic;
	signal plllock : std_logic;
	signal clk25m : std_logic;
	signal clksnd : std_logic;
	signal clki2s : std_logic;

	component mainpll is
		port (
			areset : in std_logic := '0';
			inclk0 : in std_logic := '0';
			c0 : out std_logic;
			c1 : out std_logic;
			c2 : out std_logic;
			locked : out std_logic
		);
	end component;

	signal led_counter_25m : std_logic_vector(23 downto 0);
	signal led_counter_10m : std_logic_vector(23 downto 0);

	-- X68000 Bus Signals
	signal i_as : std_logic;
	signal i_lds : std_logic;
	signal i_uds : std_logic;
	signal i_rw : std_logic;
	signal i_sdata : std_logic_vector(15 downto 0);
	signal o_dtack : std_logic;
	signal o_sdata : std_logic_vector(15 downto 0);
	type BusState_t is(
	BS_IDLE,
	BS_S_ABIN_U,
	BS_S_ABIN_U2,
	BS_S_ABIN_U_Z,
	BS_S_ABIN_L,
	BS_S_ABIN_L2,
	BS_S_ABIN_L_Z,
	BS_S_DBIN,
	BS_S_DBIN_F,
	BS_S_DBOUT_P,
	BS_S_DBOUT,
	BS_S_DBOUT_F,
	BS_M_ABOUT_U,
	BS_M_ABOUT_L,
	BS_M_DBIN,
	BS_M_DBOUT
	);
	signal bus_state : BusState_t;
	signal bus_mode : std_logic_vector(3 downto 0);

	signal as_d : std_logic;
	signal as_dd : std_logic;
	signal addr : std_logic_vector(23 downto 0);
	signal reg0 : std_logic_vector(15 downto 0);
begin

	pllrst <= not srstn;
	mainpll_inst : mainpll port map(
		areset => pllrst,
		inclk0 => pClk50M,
		c0 => clk25m,
		c1 => clksnd,
		c2 => clki2s,
		locked => plllock
	);

	clk10m <= pGPIO1_IN(0);
	srstn <= pGPIO1_IN(1);

	pLED(7) <= led_counter_25m(23);
	pLED(6) <= led_counter_25m(22);
	pLED(5) <= led_counter_25m(21);
	pLED(4) <= led_counter_25m(20);
	pLED(3) <= led_counter_10m(23);
	pLED(2) <= led_counter_10m(22);
	pLED(1) <= led_counter_10m(21);
	pLED(0) <= led_counter_10m(20);

	process (clk25m, srstn)begin
		if (srstn = '0') then
			led_counter_25m <= (others => '0');
		elsif (clk25m' event and clk25m = '1') then
			led_counter_25m <= led_counter_25m + 1;
		end if;
	end process;

	process (clk10m, srstn)begin
		if (srstn = '0') then
			led_counter_10m <= (others => '0');
		elsif (clk10m' event and clk10m = '1') then
			led_counter_10m <= led_counter_10m + 1;
		end if;
	end process;

	-- X68000 Bus Access
	i_as <= pGPIO0(21);
	i_lds <= pGPIO0(22);
	i_uds <= pGPIO0(23);
	i_rw <= pGPIO0(24);

	pGPIO0(27) <= 'Z' when o_dtack = '1' else '0';

	bus_mode <=
		"0000" when bus_state = BS_IDLE else
		"0010" when bus_state = BS_S_ABIN_U else
		"0010" when bus_state = BS_S_ABIN_U2 else
		"0000" when bus_state = BS_S_ABIN_U_Z else
		"0011" when bus_state = BS_S_ABIN_L else
		"0011" when bus_state = BS_S_ABIN_L2 else
		"0000" when bus_state = BS_S_ABIN_L_Z else
		"0100" when bus_state = BS_S_DBIN else
		"0000" when bus_state = BS_S_DBIN_F else
		"0000" when bus_state = BS_S_DBOUT_P else
		"0101" when bus_state = BS_S_DBOUT else
		"0101" when bus_state = BS_S_DBOUT_F else
		"0000";
	pGPIO0(15) <= bus_mode(0);
	pGPIO0(14) <= bus_mode(1);
	pGPIO0(13) <= bus_mode(2);
	pGPIO0(12) <= bus_mode(3);

	i_sdata <= pGPIO1(21 downto 6);
	pGPIO1(21 downto 6) <=
	o_sdata when bus_state = BS_S_DBOUT else
	o_sdata when bus_state = BS_S_DBOUT_F else
	(others => 'Z');

	process (clk25m, srstn)begin
		if (srstn = '0') then
			bus_state <= BS_IDLE;
			addr <= (others => '0');
			o_dtack <= '1';
			as_d <= '1';
			as_dd <= '1';
		elsif (clk25m' event and clk25m = '1') then
			as_d <= i_as;
			as_dd <= as_d;
			o_dtack <= '1';

			case bus_state is
				when BS_IDLE =>
					if (as_dd = '1' and as_d = '0') then
						-- falling edge
						bus_state <= BS_S_ABIN_U;
					end if;
				when BS_S_ABIN_U =>
					bus_state <= BS_S_ABIN_U2;
				when BS_S_ABIN_U2 =>
					bus_state <= BS_S_ABIN_U_Z;
					addr(23 downto 16) <= i_sdata(7 downto 0);
				when BS_S_ABIN_U_Z =>
					bus_state <= BS_S_ABIN_L;
				when BS_S_ABIN_L =>
					bus_state <= BS_S_ABIN_L2;
				when BS_S_ABIN_L2 =>
					bus_state <= BS_S_ABIN_L_Z;
					addr(15 downto 0) <= i_sdata(15 downto 1) & "0";
				when BS_S_ABIN_L_Z =>

					if (addr(23 downto 12) = x"ec1") then
						if (i_rw = '0') then
							bus_state <= BS_S_DBIN;
						else
							bus_state <= BS_S_DBOUT_P;
						end if;
					else
						bus_state <= BS_IDLE;
					end if;

					-- write cycle
				when BS_S_DBIN =>
					bus_state <= BS_S_DBIN_F;
					reg0 <= i_sdata;
					o_dtack <= '0';
				when BS_S_DBIN_F =>
					o_dtack <= '0';
					if (as_d = '1') then
						bus_state <= BS_IDLE;
					end if;

					-- read cycle
				when BS_S_DBOUT_P =>
					bus_state <= BS_S_DBOUT;
					o_sdata <= reg0;
				when BS_S_DBOUT =>
					o_dtack <= '0';
					bus_state <= BS_S_DBOUT_F;
				when BS_S_DBOUT_F =>
					o_dtack <= '0';
					if (as_d = '1') then
						bus_state <= BS_IDLE;
					end if;

					-- other
				when others =>
					bus_state <= BS_IDLE;
					o_dtack <= '1';
			end case;
		end if;
	end process;

end rtl;