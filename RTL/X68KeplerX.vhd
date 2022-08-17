LIBRARY	IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.STD_LOGIC_ARITH.ALL;
USE IEEE.STD_LOGIC_UNSIGNED.ALL;

entity X68KeplerX is
port(
	pClk50M		    :in std_logic;

	-- //////////// LED //////////
	pLED		    :out std_logic_vector(7 downto 0);

	-- //////////// KEY //////////
	pKEY		    :in std_logic_vector(1 downto 0);

	-- //////////// SW //////////
	pSW             :in std_logic_vector(3 downto 0);

	-- //////////// SDRAM //////////
	pDRAM_ADDR      :out std_logic_vector(12 downto 0);
	pDRAM_BA        :out std_logic_vector(1 downto 0);
	pDRAM_CAS_N     :out std_logic;
	pDRAM_CKE       :out std_logic;
	pDRAM_CLK       :out std_logic;
	pDRAM_CS_N      :out std_logic;
	pDRAM_DQ        :inout std_logic_vector(15 downto 0);
	pDRAM_DQM       :out std_logic_vector(1 downto 0);
	pDRAM_RAS_N     :out std_logic;
	pDRAM_WE_N      :out std_logic;

	-- //////////// EPCS //////////
	pEPCS_ASDO      :out std_logic;
	pEPCS_DATA0     :in std_logic;
	pEPCS_DCLK      :out std_logic;
	pEPCS_NCSO      :out std_logic;

	-- //////////// Accelerometer and EEPROM //////////
	pG_SENSOR_CS_N  :out std_logic;
	pG_SENSOR_INT   :in std_logic;
	pI2C_SCLK       :out std_logic;
	pI2C_SDAT       :in std_logic;

	-- //////////// ADC //////////
	pADC_CS_N       :out std_logic;
	pADC_SADDR      :out std_logic;
	pADC_SCLK       :out std_logic;
	pADC_SDAT       :in std_logic;

	-- //////////// 2x13 GPIO Header //////////
	pGPIO_2         :inout std_logic_vector(12 downto 0);
	pGPIO_2_IN      :in std_logic_vector(2 downto 0);

	-- //////////// GPIO_0, GPIO_0 connect to GPIO Default //////////
	pGPIO0          :inout std_logic_vector(33 downto 0);
	pGPIO0_IN       :in std_logic_vector(1 downto 0);

	-- //////////// GPIO_1, GPIO_1 connect to GPIO Default //////////
	pGPIO1          :inout std_logic_vector(33 downto 0);
	pGPIO1_IN       :in std_logic_vector(1 downto 0)
);
end X68KeplerX;

architecture rtl of X68KeplerX is

signal	clk10m	:std_logic;
signal	srstn		:std_logic;

signal   pllrst   :std_logic;
signal   plllock  :std_logic;
signal   clk25m	:std_logic;
signal   clksnd   :std_logic;
signal   clki2s   :std_logic;

component mainpll is
	PORT
	(
		areset		: IN STD_LOGIC  := '0';
		inclk0		: IN STD_LOGIC  := '0';
		c0		: OUT STD_LOGIC ;
		c1		: OUT STD_LOGIC ;
		c2		: OUT STD_LOGIC ;
		locked		: OUT STD_LOGIC 
	);
end component;

signal	led_counter_25m:std_logic_vector(23 downto 0);
signal	led_counter_10m:std_logic_vector(23 downto 0);

begin

	pllrst<=not srstn;
   mainpll_inst : mainpll PORT MAP (
		areset	 => pllrst,
		inclk0	 => pClk50M,
		c0	 => clk25m,
		c1	 => clksnd,
		c2	 => clki2s,
		locked	 => plllock
	);

	clk10m <= pGPIO0_IN(0);
	srstn	 <= pGPIO0_IN(1);

	pLED(7) <= led_counter_25m(23);
	pLED(6) <= led_counter_25m(22);
	pLED(5) <= led_counter_25m(21);
	pLED(4) <= led_counter_25m(20);
	pLED(3) <= led_counter_10m(23);
	pLED(2) <= led_counter_10m(22);
	pLED(1) <= led_counter_10m(21);
	pLED(0) <= led_counter_10m(20);
	
	process(clk25m,srstn)begin
		if(srstn='0')then
			led_counter_25m <= (others=>'0');
		elsif(clk25m' event and clk25m='1')then
		    led_counter_25m <= led_counter_25m + 1;
		end if;
	end process;

	process(clk10m,srstn)begin
		if(srstn='0')then
			led_counter_10m <= (others=>'0');
		elsif(clk10m' event and clk10m='1')then
		    led_counter_10m <= led_counter_10m + 1;
		end if;
	end process;

end rtl;
