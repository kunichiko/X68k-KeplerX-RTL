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

begin
end rtl;
