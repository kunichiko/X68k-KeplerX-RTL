library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.STD_LOGIC_ARITH.all;
use IEEE.STD_LOGIC_UNSIGNED.all;
use work.X68KeplerX_pkg.all;
use work.I2C_pkg.all;

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
end X68KeplerX;

architecture rtl of X68KeplerX is
	-- version 1.3.3
	constant firm_version_major : std_logic_vector(3 downto 0) := conv_std_logic_vector(1, 4);
	constant firm_version_minor : std_logic_vector(3 downto 0) := conv_std_logic_vector(3, 4);
	constant firm_version_patch : std_logic_vector(3 downto 0) := conv_std_logic_vector(3, 4);
	--constant firm_version_release : std_logic := '0'; -- beta
	constant firm_version_release : std_logic := '1'; -- release
	constant sysclk_freq : integer := 100000;

	-- initializer
	signal safe_mode_level : std_logic_vector(1 downto 0);
	signal ini_rstn : std_logic;
	signal ini_rst_counter : std_logic_vector(9 downto 0); -- 
	signal ini_power_on : std_logic;
	signal ini_rst_btn_counter : std_logic_vector(2 downto 0);
	signal x68rstn_d : std_logic;
	signal x68rstn_dd : std_logic;

	signal sec_counter_50m : std_logic_vector(26 downto 0); -- 50MHzで1秒を数えるカウンタ
	signal pClk24M576 : std_logic;
	signal pcm_clk_24M576 : std_logic;

	signal x68clk10m : std_logic;
	signal x68clk10m_d : std_logic;
	signal x68clk10m_dd : std_logic;
	signal x68rstn : std_logic;

	signal pllrst : std_logic;
	signal plllock_main : std_logic;
	signal plllock_pcm48k : std_logic;
	signal plllock_pcm44k1 : std_logic;
	signal plllock_dvi : std_logic;

	signal sys_clk : std_logic;
	signal sys_rstn : std_logic;

	signal mem_clk : std_logic;

	component pllmain is
		port (
			areset : in std_logic := '0';
			inclk0 : in std_logic := '0';
			c0 : out std_logic; -- SDRAM: 100MHz 
			c1 : out std_logic; -- SDRAM: 100MHz + 180°
			c2 : out std_logic; -- SYS  : 25MHz
			c3 : out std_logic; -- SOUND: 32MHz
			c4 : out std_logic; -- PCM  : 8MHz
			locked : out std_logic
		);
	end component;

	component pllpcm48k is
		port (
			areset : in std_logic := '0';
			inclk0 : in std_logic := '0';
			c0 : out std_logic; -- 24.576MHz
			c1 : out std_logic; -- 6.144MHz
			c2 : out std_logic; -- 3.072MHz
			locked : out std_logic
		);
	end component;

	component pllpcm44k1 is
		port (
			areset : in std_logic := '0';
			inclk0 : in std_logic := '0';
			c0 : out std_logic; -- 5.6448MHz
			locked : out std_logic
		);
	end component;

	component plldvi is
		port (
			areset : in std_logic := '0';
			inclk0 : in std_logic := '0';
			c0 : out std_logic; -- DVI  : 27MHz
			c1 : out std_logic; -- DVIx5: 153MHz
			locked : out std_logic
		);
	end component;

	signal sys_counter_100m : std_logic_vector(23 downto 0);
	signal sys_counter_10m : std_logic_vector(23 downto 0);

	--
	-- Sound
	--
	signal snd_clk : std_logic; -- internal sound operation clock (16MHz)
	signal snd_pcmL, snd_pcmR : std_logic_vector(15 downto 0);

	-- util
	component addsat
		generic (
			datwidth : integer := 16
		);
		port (
			snd_clk : std_logic;

			INA : in std_logic_vector(datwidth - 1 downto 0);
			INB : in std_logic_vector(datwidth - 1 downto 0);

			VOLA : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
			VOLB : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute

			OUTQ : out std_logic_vector(datwidth - 1 downto 0);
			OFLOW : out std_logic;
			UFLOW : out std_logic
		);
	end component;
	component addsat_16
		generic (
			datwidth : integer := 16
		);
		port (
			snd_clk : std_logic;
			rst_n : std_logic;

			in0 : in std_logic_vector(datwidth - 1 downto 0);
			vol0 : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
			mute0 : in std_logic;

			in1 : in std_logic_vector(datwidth - 1 downto 0);
			vol1 : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
			mute1 : in std_logic;

			in2 : in std_logic_vector(datwidth - 1 downto 0);
			vol2 : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
			mute2 : in std_logic;

			in3 : in std_logic_vector(datwidth - 1 downto 0);
			vol3 : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
			mute3 : in std_logic;

			in4 : in std_logic_vector(datwidth - 1 downto 0);
			vol4 : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
			mute4 : in std_logic;

			in5 : in std_logic_vector(datwidth - 1 downto 0);
			vol5 : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
			mute5 : in std_logic;

			in6 : in std_logic_vector(datwidth - 1 downto 0);
			vol6 : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
			mute6 : in std_logic;

			in7 : in std_logic_vector(datwidth - 1 downto 0);
			vol7 : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
			mute7 : in std_logic;

			in8 : in std_logic_vector(datwidth - 1 downto 0);
			vol8 : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
			mute8 : in std_logic;

			in9 : in std_logic_vector(datwidth - 1 downto 0);
			vol9 : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
			mute9 : in std_logic;

			inA : in std_logic_vector(datwidth - 1 downto 0);
			volA : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
			muteA : in std_logic;

			inB : in std_logic_vector(datwidth - 1 downto 0);
			volB : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
			muteB : in std_logic;

			inC : in std_logic_vector(datwidth - 1 downto 0);
			volC : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
			muteC : in std_logic;

			inD : in std_logic_vector(datwidth - 1 downto 0);
			volD : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
			muteD : in std_logic;

			inE : in std_logic_vector(datwidth - 1 downto 0);
			volE : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
			muteE : in std_logic;

			inF : in std_logic_vector(datwidth - 1 downto 0);
			volF : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
			muteF : in std_logic;

			outq : out std_logic_vector(datwidth - 1 downto 0)
		);
	end component;

	-- FM Sound
	constant YM2151_MODULE : string(1 to 6) := "IKAOPM";
	--constant YM2151_MODULE : string(1 to 6) := "JT51__";
	--constant YM2151_MODULE : string(1 to 6) := "______";

	component OPM_IKAOPM
		port (
			sys_clk : in std_logic;
			sys_rstn : in std_logic;
			req : in std_logic;
			ack : out std_logic;

			rw : in std_logic;
			addr : in std_logic;
			idata : in std_logic_vector(7 downto 0);
			odata : out std_logic_vector(7 downto 0);

			irqn : out std_logic;

			-- specific i/o
			snd_clk : in std_logic;
			pcmL : out std_logic_vector(15 downto 0);
			pcmR : out std_logic_vector(15 downto 0);

			CT1 : out std_logic;
			CT2 : out std_logic

		);
	end component;

	component OPM_jT51
		port (
			sys_clk : in std_logic;
			sys_rstn : in std_logic;
			req : in std_logic;
			ack : out std_logic;

			rw : in std_logic;
			addr : in std_logic;
			idata : in std_logic_vector(7 downto 0);
			odata : out std_logic_vector(7 downto 0);

			irqn : out std_logic;

			-- specific i/o
			snd_clk : in std_logic;
			pcmL : out std_logic_vector(15 downto 0);
			pcmR : out std_logic_vector(15 downto 0);

			CT1 : out std_logic;
			CT2 : out std_logic

		);
	end component;

	constant ENABLE_REAL_YM2151 : integer := 0; -- 1: enable, 0: disable

	component OPM_YM2151
		port (
			sys_clk : in std_logic;
			sys_rstn : in std_logic;
			req : in std_logic;
			ack : out std_logic;

			rw : in std_logic;
			addr : in std_logic;
			idata : in std_logic_vector(7 downto 0);
			odata : out std_logic_vector(7 downto 0);

			irqn : out std_logic;

			-- specific i/o
			snd_clk : in std_logic;
			pcmL : out std_logic_vector(15 downto 0);
			pcmR : out std_logic_vector(15 downto 0);

			CT1 : out std_logic;
			CT2 : out std_logic;

			-- external connection
			OPM_IC_n : out std_logic;
			OPM_PHYM : out std_logic;
			OPM_PHY1 : in std_logic;
			OPM_WR_n : out std_logic;
			OPM_A0 : out std_logic;
			OPM_DATA : out std_logic_vector(7 downto 0);
			OPM_SH1 : in std_logic;
			OPM_SH2 : in std_logic;
			OPM_SDATA : in std_logic
		);
	end component;

	signal opm_req : std_logic;
	signal opm_ack : std_logic;
	signal opm_idata : std_logic_vector(7 downto 0);
	signal opm_odata : std_logic_vector(7 downto 0);

	signal opm_pcmLi : std_logic_vector(15 downto 0);
	signal opm_pcmRi : std_logic_vector(15 downto 0);
	signal opm_pcmL : std_logic_vector(15 downto 0);
	signal opm_pcmR : std_logic_vector(15 downto 0);

	-- for real YM2151
	signal opm_OPM_IC_n : std_logic;
	signal opm_OPM_PhYM : std_logic;
	signal opm_OPM_PhY1 : std_logic;
	signal opm_OPM_WR_n : std_logic;
	signal opm_OPM_A0 : std_logic;
	signal opm_OPM_DATA : std_logic_vector(7 downto 0);
	signal opm_OPM_SH1 : std_logic;
	signal opm_OPM_SH2 : std_logic;
	signal opm_OPM_SDATA : std_logic;
	signal opm_YM2151_pcmLi : std_logic_vector(15 downto 0);
	signal opm_YM2151_pcmRi : std_logic_vector(15 downto 0);
	signal opm_YM2151_pcmL : std_logic_vector(15 downto 0);
	signal opm_YM2151_pcmR : std_logic_vector(15 downto 0);

	-- ADPCM
	component e6258
		port (
			sys_clk : in std_logic;
			sys_rstn : in std_logic;
			req : in std_logic;
			ack : out std_logic;

			rw : in std_logic;
			addr : in std_logic;
			idata : in std_logic_vector(7 downto 0);
			odata : out std_logic_vector(7 downto 0);

			drq : out std_logic;

			-- specific i/o
			clkdiv : in std_logic_vector(1 downto 0);
			sft : in std_logic;
			adpcm_datemp : out std_logic;
			adpcm_datover : out std_logic;

			snd_clk : in std_logic;
			pcm : out std_logic_vector(11 downto 0)
		);
	end component;

	signal adpcm_req : std_logic;
	signal adpcm_ack : std_logic;
	signal adpcm_idata : std_logic_vector(7 downto 0);
	signal adpcm_clkdiv : std_logic_vector(1 downto 0);
	signal adpcm_clkdiv_count : integer range 0 to 7;
	signal adpcm_clkmode : std_logic;
	signal adpcm_sft : std_logic;
	signal adpcm_pcmRaw : std_logic_vector(11 downto 0);
	signal adpcm_pcmL : std_logic_vector(15 downto 0);
	signal adpcm_pcmR : std_logic_vector(15 downto 0);
	signal adpcm_enL : std_logic;
	signal adpcm_enR : std_logic;
	signal adpcm_datemp : std_logic;
	signal adpcm_datover : std_logic;

	--
	-- i2s sound (to WM8804 and PCM5102)
	--

	component i2s_encoder
		port (
			snd_clk : in std_logic;
			snd_pcmL : in std_logic_vector(31 downto 0);
			snd_pcmR : in std_logic_vector(31 downto 0);

			i2s_data : out std_logic;
			i2s_lrck : out std_logic;

			i2s_bclk : in std_logic; -- I2S BCK (Bit Clock) 3.072MHz (=48kHz * 64)
			bclk_pcmL : out std_logic_vector(31 downto 0); -- I2S BCLK synchronized pcm
			bclk_pcmR : out std_logic_vector(31 downto 0); -- I2S BCLK synchronized pcm

			rstn : in std_logic
		);
	end component;

	signal i2s_mclk : std_logic;
	signal i2s_bclk : std_logic; -- I2S BCLK
	signal i2s_lrck : std_logic; -- I2S LRCK
	signal i2s_data_out : std_logic;
	signal i2s_data_in : std_logic; -- from WM8804
	signal i2s_dtct : std_logic;

	signal i2s_sndL, i2s_sndR : std_logic_vector(31 downto 0);
	signal i2s_pcmL_spdif, i2s_pcmR_spdif : std_logic_vector(31 downto 0);
	signal spdifin_pcmL, spdifin_pcmR : std_logic_vector(15 downto 0);
	signal bclk_pcmL, bclk_pcmR : std_logic_vector(31 downto 0);

	component i2s_decoder
		port (
			snd_clk : in std_logic;

			i2s_data : in std_logic;
			i2s_lrck : in std_logic;
			i2s_bclk : in std_logic; -- I2S BCLK (Bit Clock) 3.072MHz (=48kHz * 64)

			detected : out std_logic;

			snd_pcmL : out std_logic_vector(31 downto 0);
			snd_pcmR : out std_logic_vector(31 downto 0);

			rstn : in std_logic
		);
	end component;

	signal i2s_bclk_pi : std_logic; -- I2S BCLK from RaspberryPi
	signal i2s_lrck_pi : std_logic; -- I2S LRCK from RaspberryPi
	signal i2s_data_pi : std_logic; -- I2S DATA from RaspberryPi
	signal i2s_dtct_pi : std_logic;
	signal i2s_pcmL_pi, i2s_pcmR_pi : std_logic_vector(31 downto 0);
	signal raspi_pcmL, raspi_pcmR : std_logic_vector(15 downto 0);

	--
	-- I2C
	--

	-- Define the number of I2C device drivers  
	constant NUM_DRIVERS : integer := 3;

	component I2CIF
		port (
			DATIN : in std_logic_vector(I2CDAT_WIDTH - 1 downto 0); --tx data in
			DATOUT : out std_logic_vector(I2CDAT_WIDTH - 1 downto 0); --rx data out
			WRn : in std_logic; --write
			RDn : in std_logic; --read

			TXEMP : out std_logic; --tx buffer empty
			RXED : out std_logic; --rx buffered
			NOACK : out std_logic; --no ack
			COLL : out std_logic; --collision detect
			NX_READ : in std_logic; --next data is read
			RESTART : in std_logic; --make re-start condition
			START : in std_logic; --make start condition
			FINISH : in std_logic; --next data is final(make stop condition)
			F_FINISH : in std_logic; --next data is final(make stop condition)
			INIT : in std_logic;

			--	INTn :out	std_logic;

			SDAIN : in std_logic;
			SDAOUT : out std_logic;
			SCLIN : in std_logic;
			SCLOUT : out std_logic;

			SFT : in std_logic;
			clk : in std_logic;
			rstn : in std_logic
		);
	end component;

	component SFTCLK
		generic (
			SYS_CLK : integer := sysclk_freq;
			OUT_CLK : integer := 800;
			selWIDTH : integer := 2
		);
		port (
			sel : in std_logic_vector(selWIDTH - 1 downto 0);
			SFT : out std_logic;

			clk : in std_logic;
			rstn : in std_logic
		);
	end component;

	component I2C_MUX is
		generic (
			NUM_DRIVERS : integer := 2
		);
		port (
			-- I2C
			TXOUT : out std_logic_vector(7 downto 0); --tx data in
			RXIN : in std_logic_vector(7 downto 0); --rx data out
			WRn : out std_logic; --write
			RDn : out std_logic; --read

			TXEMP : in std_logic; --tx buffer empty
			RXED : in std_logic; --rx buffered
			NOACK : in std_logic; --no ack
			COLL : in std_logic; --collision detect
			NX_READ : out std_logic; --next data is read
			RESTART : out std_logic; --make re-start condition
			START : out std_logic; --make start condition
			FINISH : out std_logic; --next data is final(make stop condition)
			F_FINISH : out std_logic; --next data is final(make stop condition by force)
			INIT : out std_logic;

			-- for Driver
			DATIN_PXY : in i2cdat_array(NUM_DRIVERS - 1 downto 0); --tx data in
			DATOUT_PXY : out i2cdat_array(NUM_DRIVERS - 1 downto 0); --rx data out
			WRn_PXY : in std_logic_vector(NUM_DRIVERS - 1 downto 0); --write
			RDn_PXY : in std_logic_vector(NUM_DRIVERS - 1 downto 0); --read

			TXEMP_PXY : out std_logic_vector(NUM_DRIVERS - 1 downto 0); --tx buffer empty
			RXED_PXY : out std_logic_vector(NUM_DRIVERS - 1 downto 0); --rx buffered
			NOACK_PXY : out std_logic_vector(NUM_DRIVERS - 1 downto 0); --no ack
			COLL_PXY : out std_logic_vector(NUM_DRIVERS - 1 downto 0); --collision detect
			NX_READ_PXY : in std_logic_vector(NUM_DRIVERS - 1 downto 0); --next data is read
			RESTART_PXY : in std_logic_vector(NUM_DRIVERS - 1 downto 0); --make re-start condition
			START_PXY : in std_logic_vector(NUM_DRIVERS - 1 downto 0); --make start condition
			FINISH_PXY : in std_logic_vector(NUM_DRIVERS - 1 downto 0); --next data is final(make stop condition)
			F_FINISH_PXY : in std_logic_vector(NUM_DRIVERS - 1 downto 0); --next data is final(make stop condition)
			INIT_PXY : in std_logic_vector(NUM_DRIVERS - 1 downto 0);

			clk : in std_logic;
			rstn : in std_logic
		);
	end component;

	signal SDAIN, SDAOUT : std_logic;
	signal SCLIN, SCLOUT : std_logic;
	signal I2CCLKEN : std_logic;

	signal I2C_TXDAT : std_logic_vector(7 downto 0); --tx data in
	signal I2C_RXDAT : std_logic_vector(7 downto 0); --rx data out
	signal I2C_WRn : std_logic; --write
	signal I2C_RDn : std_logic; --read
	signal I2C_TXEMP : std_logic; --tx buffer empty
	signal I2C_RXED : std_logic; --rx buffered
	signal I2C_NOACK : std_logic; --no ack
	signal I2C_COLL : std_logic; --collision detect
	signal I2C_NX_READ : std_logic; --next data is read
	signal I2C_RESTART : std_logic; --make re-start condition
	signal I2C_START : std_logic; --make start condition
	signal I2C_FINISH : std_logic; --next data is final(make stop condition)
	signal I2C_F_FINISH : std_logic; --next data is final(make stop condition)
	signal I2C_INIT : std_logic;

	component GreenPAK_EEPROM is
		port (
			-- Host interface
			addr : in std_logic_vector(7 downto 0);
			data_in : in std_logic_vector(7 downto 0);
			data_out : out std_logic_vector(7 downto 0);
			we : in std_logic := '1';

			ready : out std_logic;
			crc_error : out std_logic;

			save_req : in std_logic;
			save_ack : out std_logic;

			-- I2C interface
			TXOUT : out std_logic_vector(7 downto 0); --tx data
			RXIN : in std_logic_vector(7 downto 0); --rx data
			WRn : out std_logic; --write
			RDn : out std_logic; --read

			TXEMP : in std_logic; --tx buffer empty
			RXED : in std_logic; --rx buffered
			NOACK : in std_logic; --no ack
			COLL : in std_logic; --collision detect
			NX_READ : out std_logic; --next data is read
			RESTART : out std_logic; --make re-start condition
			START : out std_logic; --make start condition
			FINISH : out std_logic; --next data is final(make stop condition)
			F_FINISH : out std_logic; --next data is final(make stop condition) (force stop)
			INIT : out std_logic;

			clk : in std_logic;
			rstn : in std_logic
		);
	end component;

	signal gpeeprom_addr : std_logic_vector(7 downto 0);
	signal gpeeprom_data_in : std_logic_vector(7 downto 0);
	signal gpeeprom_data_out : std_logic_vector(7 downto 0);
	signal gpeeprom_we : std_logic;

	signal gpeeprom_ready : std_logic;
	signal gpeeprom_ready_d : std_logic;
	signal gpeeprom_crc_error : std_logic;
	signal gpeeprom_save_req : std_logic;
	signal gpeeprom_save_ack : std_logic;

	signal gpeeprom_data_word : std_logic_vector(15 downto 0);

	signal gpeeprom_restore_counter : std_logic_vector(6 downto 0);
	signal gpeeprom_restore_state : std_logic_vector(2 downto 0);

	component wm8804 is
		port (
			TXOUT : out std_logic_vector(7 downto 0); --tx data in
			RXIN : in std_logic_vector(7 downto 0); --rx data out
			WRn : out std_logic; --write
			RDn : out std_logic; --read

			TXEMP : in std_logic; --tx buffer empty
			RXED : in std_logic; --rx buffered
			NOACK : in std_logic; --no ack
			COLL : in std_logic; --collision detect
			NX_READ : out std_logic; --next data is read
			RESTART : out std_logic; --make re-start condition
			START : out std_logic; --make start condition
			FINISH : out std_logic; --next data is final(make stop condition)
			F_FINISH : out std_logic; --next data is final(make stop condition)
			INIT : out std_logic;

			clk : in std_logic;
			rstn : in std_logic
		);
	end component;

	signal wm8804_rstn : std_logic;

	-- MUX I2C signals
	signal I2C_TXDAT_PXY : i2cdat_array(NUM_DRIVERS - 1 downto 0); --tx data in
	signal I2C_RXDAT_PXY : i2cdat_array(NUM_DRIVERS - 1 downto 0); --rx data out
	signal I2C_WRn_PXY : std_logic_vector(NUM_DRIVERS - 1 downto 0); --write
	signal I2C_RDn_PXY : std_logic_vector(NUM_DRIVERS - 1 downto 0); --read
	signal I2C_TXEMP_PXY : std_logic_vector(NUM_DRIVERS - 1 downto 0); --tx buffer empty
	signal I2C_RXED_PXY : std_logic_vector(NUM_DRIVERS - 1 downto 0); --rx buffered
	signal I2C_NOACK_PXY : std_logic_vector(NUM_DRIVERS - 1 downto 0); --no ack
	signal I2C_COLL_PXY : std_logic_vector(NUM_DRIVERS - 1 downto 0); --collision detect
	signal I2C_NX_READ_PXY : std_logic_vector(NUM_DRIVERS - 1 downto 0); --next data is read
	signal I2C_RESTART_PXY : std_logic_vector(NUM_DRIVERS - 1 downto 0); --make re-start condition
	signal I2C_START_PXY : std_logic_vector(NUM_DRIVERS - 1 downto 0); --make start condition
	signal I2C_FINISH_PXY : std_logic_vector(NUM_DRIVERS - 1 downto 0); --next data is final(make stop condition)
	signal I2C_F_FINISH_PXY : std_logic_vector(NUM_DRIVERS - 1 downto 0); --next data is final(make stop condition)
	signal I2C_INIT_PXY : std_logic_vector(NUM_DRIVERS - 1 downto 0);

	--
	-- ppi
	--
	component e8255
		generic (
			deflogic : std_logic := '0'
		);
		port (
			sys_clk : in std_logic;
			sys_rstn : in std_logic;
			req : in std_logic;
			ack : out std_logic;

			rw : in std_logic;
			addr : in std_logic_vector(1 downto 0);
			idata : in std_logic_vector(7 downto 0);
			odata : out std_logic_vector(7 downto 0);

			-- 
			PAi : in std_logic_vector(7 downto 0);
			PAo : out std_logic_vector(7 downto 0);
			PAoe : out std_logic;
			PBi : in std_logic_vector(7 downto 0);
			PBo : out std_logic_vector(7 downto 0);
			PBoe : out std_logic;
			PCHi : in std_logic_vector(3 downto 0);
			PCHo : out std_logic_vector(3 downto 0);
			PCHoe : out std_logic;
			PCLi : in std_logic_vector(3 downto 0);
			PCLo : out std_logic_vector(3 downto 0);
			PCLoe : out std_logic
		);
	end component;

	signal ppi1_req : std_logic;
	signal ppi1_ack : std_logic;
	signal ppi1_idata : std_logic_vector(7 downto 0);
	signal ppi1_odata : std_logic_vector(7 downto 0);
	signal ppi1_pai : std_logic_vector(7 downto 0);
	signal ppi1_pao : std_logic_vector(7 downto 0);
	signal ppi1_paoe : std_logic;
	signal ppi1_pbi : std_logic_vector(7 downto 0);
	signal ppi1_pbo : std_logic_vector(7 downto 0);
	signal ppi1_pboe : std_logic;
	signal ppi1_pchi : std_logic_vector(3 downto 0);
	signal ppi1_pcho : std_logic_vector(3 downto 0);
	signal ppi1_pchoe : std_logic;
	signal ppi1_pcli : std_logic_vector(3 downto 0);
	signal ppi1_pclo : std_logic_vector(3 downto 0);
	signal ppi1_pcloe : std_logic;

	signal ppi2_req : std_logic;
	signal ppi2_ack : std_logic;
	signal ppi2_idata : std_logic_vector(7 downto 0);
	signal ppi2_odata : std_logic_vector(7 downto 0);
	signal ppi2_pai : std_logic_vector(7 downto 0);
	signal ppi2_pao : std_logic_vector(7 downto 0);
	signal ppi2_paoe : std_logic;
	signal ppi2_pbi : std_logic_vector(7 downto 0);
	signal ppi2_pbo : std_logic_vector(7 downto 0);
	signal ppi2_pboe : std_logic;
	signal ppi2_pchi : std_logic_vector(3 downto 0);
	signal ppi2_pcho : std_logic_vector(3 downto 0);
	signal ppi2_pchoe : std_logic;
	signal ppi2_pcli : std_logic_vector(3 downto 0);
	signal ppi2_pclo : std_logic_vector(3 downto 0);
	signal ppi2_pcloe : std_logic;

	--
	-- HDMI
	--
	type audio_sample_word_t is array (1 downto 0) of std_logic_vector(15 downto 0);

	subtype rawchar is std_logic_vector(7 downto 0);
	type rawstring is array(natural range <>) of rawchar;

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

	signal hdmi_clk : std_logic; -- 27MHz
	signal hdmi_clk_x5 : std_logic; -- 135MHz
	signal hdmi_rst : std_logic;
	signal hdmi_rgb : std_logic_vector(23 downto 0);
	signal hdmi_pcm : audio_sample_word_t;
	signal hdmi_pcmclk : std_logic;
	signal hdmi_tmds : std_logic_vector(2 downto 0);
	signal hdmi_tmdsclk : std_logic;
	signal hdmi_cx : std_logic_vector(9 downto 0);
	signal hdmi_cx_d : std_logic_vector(9 downto 0);
	signal hdmi_cy : std_logic_vector(9 downto 0);
	signal hdmi_cy_d : std_logic_vector(9 downto 0);

	signal hdmi_r : std_logic_vector(7 downto 0);
	signal hdmi_g : std_logic_vector(7 downto 0);
	signal hdmi_b : std_logic_vector(7 downto 0);
	signal hdmi_adpcm_datemp : std_logic;
	signal hdmi_adpcm_datover : std_logic;

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

	signal console_rgb : std_logic_vector(23 downto 0);
	signal console_char : std_logic_vector(7 downto 0);
	signal console_ram_addr : std_logic_vector(3 + 7 - 1 downto 0);
	signal console_ram_din : std_logic_vector(7 downto 0);
	signal console_ram_dout : std_logic_vector(7 downto 0);
	signal console_ram_we : std_logic;

	component console_textram is
		port (
			clk : in std_logic;
			address : in std_logic_vector(3 + 7 - 1 downto 0);
			din : in std_logic_vector(7 downto 0);
			dout : out std_logic_vector(7 downto 0);
			we : in std_logic
		);
	end component;

	--
	-- KeplerX's configuration registers
	--

	-- 
	signal keplerx_req : std_logic;
	signal keplerx_ack : std_logic;
	signal keplerx_odata : std_logic_vector(15 downto 0);
	constant keplerx_reg_count : integer := 16;
	type reg_type is array(0 to keplerx_reg_count - 1) of std_logic_vector(15 downto 0);
	signal keplerx_reg : reg_type;
	signal keplerx_reg_update_req : std_logic_vector(keplerx_reg_count - 1 downto 0);
	signal keplerx_reg_update_ack : std_logic_vector(keplerx_reg_count - 1 downto 0);

	type keplerx_reg_state_t is(
	KXR_IDLE,
	KXR_REG0, -- REG0の特殊処理
	KXR_EEPROM_WR_U0,
	KXR_EEPROM_WR_U1,
	KXR_EEPROM_WR_L0,
	KXR_EEPROM_WR_L1,
	KXR_EEPROM_RD_AU,
	KXR_EEPROM_RD_AL,
	KXR_EEPROM_RD_WAIT,
	KXR_EEPROM_RD_DU,
	KXR_EEPROM_RD_DL,
	KXR_ACK
	);
	signal keplerx_reg_state : keplerx_reg_state_t;
	signal areaset_req : std_logic;
	signal areaset_ack : std_logic;

	signal khz_counter : integer range 0 to sysclk_freq - 1;
	signal hz_counter : integer range 0 to 999; -- kHz to Hz
	signal tensec_counter : integer range 0 to 9; -- Hz to 0.1Hz

	signal x68_sysclk_counter : integer range 0 to 32767;
	signal x68_hsync_counter : integer range 0 to 65535;
	signal x68_vsync_counter : integer range 0 to 1023;

	signal x68_clk10m_d : std_logic;
	signal x68_clk10m_dd : std_logic;
	signal x68_hsync_d : std_logic;
	signal x68_hsync_dd : std_logic;
	signal x68_vsync_d : std_logic;
	signal x68_vsync_dd : std_logic;

	--
	-- eMercury Unit
	--
	component eMercury
		port (
			sys_clk : in std_logic;
			sys_rstn : in std_logic;
			req : in std_logic;
			ack : out std_logic;

			rw : in std_logic;
			addr : in std_logic_vector(7 downto 0);
			uds_n : in std_logic;
			lds_n : in std_logic;
			idata : in std_logic_vector(15 downto 0);
			odata : out std_logic_vector(15 downto 0);

			irq_n : out std_logic;
			int_vec : out std_logic_vector(7 downto 0);

			drq_n : out std_logic;
			dack_n : in std_logic;

			pcl_en : out std_logic;
			pcl : out std_logic;

			-- specific i/o
			snd_clk : in std_logic;
			pcm_clk_6M144 : in std_logic; -- 48kHz * 2 * 64
			pcm_clk_5M6448 : in std_logic; -- 44.1kHz * 2 * 64
			pcm_clk_8M : in std_logic; -- 32kHz * 2 * 125
			pcm_pcmL : out pcm_type;
			pcm_pcmR : out pcm_type;
			--
			pcm_fmL0 : out pcm_type;
			pcm_fmR0 : out pcm_type;
			pcm_ssg0 : out pcm_type;
			pcm_rhythmL0 : out pcm_type;
			pcm_rhythmR0 : out pcm_type;
			pcm_fmL1 : out pcm_type;
			pcm_fmR1 : out pcm_type;
			pcm_ssg1 : out pcm_type;
			pcm_rhythmL1 : out pcm_type;
			pcm_rhythmR1 : out pcm_type;
			--
			pcm_extinL : in pcm_type; -- snd_clk に同期した外部PCM録音入力L
			pcm_extinR : in pcm_type -- snd_clk に同期した外部PCM録音入力R			
		);
	end component;

	signal pcm_clk_6M144 : std_logic; -- 48kHz * 2 * 64
	signal pcm_clk_5M6448 : std_logic; -- 44.1kHz * 2 * 64
	signal pcm_clk_8M : std_logic;
	signal mercury_req : std_logic;
	signal mercury_ack : std_logic;
	signal mercury_idata : std_logic_vector(15 downto 0);
	signal mercury_odata : std_logic_vector(15 downto 0);
	signal mercury_irq_n : std_logic;
	signal mercury_int_vec : std_logic_vector(7 downto 0);
	signal mercury_drq_n : std_logic;
	signal mercury_dack_n : std_logic;
	signal mercury_pcl_en : std_logic;
	signal mercury_pcl : std_logic;
	signal mercury_pcm_mixL : std_logic_vector(15 downto 0);
	signal mercury_pcm_mixR : std_logic_vector(15 downto 0);
	signal mercury_pcm_pcmL : std_logic_vector(15 downto 0);
	signal mercury_pcm_pcmR : std_logic_vector(15 downto 0);
	signal mercury_pcm_fmL0 : std_logic_vector(15 downto 0);
	signal mercury_pcm_fmR0 : std_logic_vector(15 downto 0);
	signal mercury_pcm_ssg0 : std_logic_vector(15 downto 0);
	signal mercury_pcm_rhythmL0 : std_logic_vector(15 downto 0);
	signal mercury_pcm_rhythmR0 : std_logic_vector(15 downto 0);
	signal mercury_pcm_fmL1 : std_logic_vector(15 downto 0);
	signal mercury_pcm_fmR1 : std_logic_vector(15 downto 0);
	signal mercury_pcm_ssg1 : std_logic_vector(15 downto 0);
	signal mercury_pcm_rhythmL1 : std_logic_vector(15 downto 0);
	signal mercury_pcm_rhythmR1 : std_logic_vector(15 downto 0);

	--
	-- MIDI I/F
	--
	component em3802
		generic (
			sysclk : integer := sysclk_freq;
			oscm : integer := 1000;
			oscf : integer := 614
		);
		port (
			sys_clk : in std_logic;
			sys_rstn : in std_logic;
			req : in std_logic;
			ack : out std_logic;

			rw : in std_logic;
			addr : in std_logic_vector(2 downto 0);
			idata : in std_logic_vector(7 downto 0);
			odata : out std_logic_vector(7 downto 0);

			irq_n : out std_logic;
			int_vec : out std_logic_vector(7 downto 0);

			RxD : in std_logic;
			TxD : out std_logic;
			RxF : in std_logic;
			TxF : out std_logic;
			SYNC : out std_logic;
			CLICK : out std_logic;
			GPOUT : out std_logic_vector(7 downto 0);
			GPIN : in std_logic_vector(7 downto 0);
			GPOE : out std_logic_vector(7 downto 0);

			-- flow control
			transmitting : out std_logic;
			suspend : in std_logic
		);
	end component;
	signal midi_req : std_logic;
	signal midi_ack : std_logic;
	signal midi_idata : std_logic_vector(7 downto 0);
	signal midi_odata : std_logic_vector(7 downto 0);
	signal midi_irq_n : std_logic;
	signal midi_int_vec : std_logic_vector(7 downto 0);
	signal midi_tx : std_logic;
	signal midi_rx : std_logic;
	signal midi_transmitting : std_logic;
	signal midi_suspend : std_logic;

	component midi_ctrl is
		generic (
			sysclk : integer := sysclk_freq
		);
		port (
			sys_clk : in std_logic;
			sys_rstn : in std_logic;
			req : in std_logic;
			ack : out std_logic;

			rw : in std_logic;
			--        addr : in std_logic_vector(2 downto 0);
			idata : in std_logic_vector(15 downto 0);
			odata : out std_logic_vector(15 downto 0);

			-- All notes off request
			all_notes_off_req : in std_logic;
			all_notes_off_ack : out std_logic;

			-- MIDI sources
			midi_source_1 : in std_logic; -- 3802の出力
			midi_source_1_active : in std_logic; -- 送信中は '1'
			midi_source_2 : in std_logic; -- 外部MIDI入力
			midi_source_2_active : in std_logic; -- 送信中は '1'
			midi_source_3 : in std_logic; -- 予備
			midi_source_3_active : in std_logic; -- 予備

			-- MIDI outputs
			midi_out_ext : out std_logic; -- 外部MIDI-OUTへの出力
			midi_out_mt32pi : out std_logic; -- mt32-piへの出力

			-- MIDI routing
			midi_routing_ext : in std_logic_vector(1 downto 0); --  ("00": None, "01": Source1, "10": Source2, "11": Source3)
			midi_routing_mt32pi : in std_logic_vector(1 downto 0); --  ("00": None, "01": Source1, "10": Source2, "11": Source3)

			sending_ctrl_msg : out std_logic -- MIDI コントロールメッセージ送信中は '1'
		);
	end component;
	signal mt32pi_req : std_logic;
	signal mt32pi_ack : std_logic;
	signal mt32pi_idata : std_logic_vector(15 downto 0);
	signal mt32pi_odata : std_logic_vector(15 downto 0);
	signal midi_all_notes_off_req : std_logic;
	signal midi_all_notes_off_ack : std_logic;
	signal midi_all_notes_off_req_finished : std_logic;
	signal midi_ext_tx : std_logic;
	signal midi_mt32pi_tx : std_logic;

	--
	-- Expansion Memory
	--
	component exmemory is
		generic (
			HADDR_WIDTH : integer := 24;
			SDRADDR_WIDTH : integer := 13;
			BANK_WIDTH : integer := 2;
			CLK_FREQUENCY : integer := 100
		);
		port (
			mem_clk : in std_logic;
			sys_rstn : in std_logic;
			req : in std_logic;
			ack : out std_logic;

			ref_lock_req : in std_logic;
			ref_lock_ack : out std_logic;

			rw : in std_logic;
			uds_n : in std_logic;
			lds_n : in std_logic;
			addr : in std_logic_vector(23 downto 0);
			idata : in std_logic_vector(15 downto 0);
			odata : out std_logic_vector(15 downto 0);
			odata_ready : out std_logic;

			-- SDRAM SIDE
			--sdram_clk : in std_logic;
			sdram_addr : out std_logic_vector(12 downto 0);
			sdram_bank_addr : out std_logic_vector(1 downto 0);
			sdram_idata : in std_logic_vector(15 downto 0);
			sdram_odata : out std_logic_vector(15 downto 0);
			sdram_odata_en : out std_logic;
			sdram_clock_enable : out std_logic;
			sdram_cs_n : out std_logic;
			sdram_ras_n : out std_logic;
			sdram_cas_n : out std_logic;
			sdram_we_n : out std_logic;
			sdram_data_mask_low : out std_logic;
			sdram_data_mask_high : out std_logic
		);
	end component;
	signal exmem_enabled : std_logic_vector(15 downto 0);
	signal exmem_watchdog : std_logic_vector(7 downto 0);
	signal exmem_req : std_logic;
	signal exmem_ack : std_logic;
	signal exmem_ack_d : std_logic;
	signal exmem_idata : std_logic_vector(15 downto 0);
	signal exmem_odata : std_logic_vector(15 downto 0);
	signal exmem_odata_ready : std_logic;

	signal exmem_ref_lock_req : std_logic;
	signal exmem_ref_lock_ack : std_logic;

	signal exmem_SDRAM_ADDR : std_logic_vector(12 downto 0);
	signal exmem_SDRAM_BA : std_logic_vector(1 downto 0);
	signal exmem_SDRAM_CAS_N : std_logic;
	signal exmem_SDRAM_CKE : std_logic;
	signal exmem_SDRAM_CS_N : std_logic;
	signal exmem_SDRAM_IDATA : std_logic_vector(15 downto 0);
	signal exmem_SDRAM_ODATA : std_logic_vector(15 downto 0);
	signal exmem_SDRAM_ODATA_EN : std_logic;
	signal exmem_SDRAM_DQM : std_logic_vector(1 downto 0);
	signal exmem_SDRAM_RAS_N : std_logic;
	signal exmem_SDRAM_WE_N : std_logic;

	--
	-- SPI Slave I/F for Raspberry-Pi
	--
	component SPI_SLAVE
		generic (
			WORD_SIZE : natural := 8 -- size of transfer word in bits, must be power of two
		);
		port (
			CLK : in std_logic; -- system clock
			RST : in std_logic; -- high active synchronous reset
			-- SPI SLAVE INTERFACE
			SCLK : in std_logic; -- SPI clock
			CS_N : in std_logic; -- SPI chip select, active in low
			MOSI : in std_logic; -- SPI serial data from master to slave
			MISO : out std_logic; -- SPI serial data from slave to master
			-- USER INTERFACE
			DIN : in std_logic_vector(WORD_SIZE - 1 downto 0); -- data for transmission to SPI master
			DIN_VLD : in std_logic; -- when DIN_VLD = 1, data for transmission are valid
			DIN_RDY : out std_logic; -- when DIN_RDY = 1, SPI slave is ready to accept valid data for transmission
			DOUT : out std_logic_vector(WORD_SIZE - 1 downto 0); -- received data from SPI master
			DOUT_VLD : out std_logic -- when DOUT_VLD = 1, received data are valid
		);
	end component;
	signal spi_rst : std_logic;
	signal spi_sclk : std_logic;
	signal spi_cs_n : std_logic;
	signal spi_cs_n_d : std_logic;
	signal spi_mosi : std_logic;
	signal spi_miso : std_logic;
	signal spi_din : std_logic_vector(7 downto 0);
	signal spi_din_vld : std_logic;
	signal spi_din_rdy : std_logic;
	signal spi_dout : std_logic_vector(7 downto 0);
	signal spi_dout_latch : std_logic_vector(7 downto 0);
	signal spi_dout_vld : std_logic;
	signal spi_dout_vld_d : std_logic;
	signal spi_dout_vld_dd : std_logic;
	--
	signal spi_command : std_logic_vector(7 downto 0);
	type spi_state_t is(
	SPI_IDLE, -- マスター(ラズパイ)からの書き込み待ち
	SPI_FIN,
	SPI_CMD_STATUS,
	SPI_CMD_BM_SETADDR_FC, -- 次にアクセスするアドレスのセット
	SPI_CMD_BM_SETADDR_24, -- 次にアクセスするアドレスのセット
	SPI_CMD_BM_SETADDR_16,
	SPI_CMD_BM_SETADDR_8,
	SPI_CMD_BM_GETDATA_16, -- 最後に読み込んだデータのゲット
	SPI_CMD_BM_GETDATA_8,
	SPI_CMD_BM_SETDATA_16, -- 次に書き込むデータのセット
	SPI_CMD_BM_SETDATA_8,
	SPI_CMD_BM_READ,
	SPI_CMD_BM_READ_WAIT,
	SPI_CMD_BM_WRITE,
	SPI_CMD_BM_WRITE_WAIT
	);
	signal spi_state : spi_state_t;
	signal spi_bm_fc : std_logic_vector(2 downto 0);
	signal spi_bm_addr : std_logic_vector(23 downto 0);
	signal spi_bm_odata : std_logic_vector(15 downto 0);
	signal spi_bm_idata : std_logic_vector(15 downto 0);

	--
	-- X68000 Bus Signals
	--
	type m68k_state_t is(
	M68K_S0,
	M68K_S1,
	M68K_S2,
	M68K_S3,
	M68K_S4,
	M68K_S5,
	M68K_S6,
	M68K_S7
	);
	signal m68k_state : m68k_state_t;

	signal i_as_n : std_logic;
	signal i_as_n_sft : std_logic_vector(2 downto 0);
	signal i_as_n_d : std_logic;
	signal i_as_n_dd : std_logic;
	signal i_lds_n : std_logic;
	signal i_lds_n_d : std_logic;
	signal i_uds_n : std_logic;
	signal i_uds_n_d : std_logic;
	signal i_rw : std_logic;
	signal i_rw_d : std_logic;
	signal i_bg_n : std_logic;
	signal i_bg_n_d : std_logic;
	signal i_sdata : std_logic_vector(15 downto 0);
	signal i_iack_n : std_logic;
	signal i_iack_n_edge : std_logic_vector(2 downto 0);
	signal o_dtack_n : std_logic;
	signal o_sdata : std_logic_vector(15 downto 0);
	signal o_irq_n : std_logic;
	signal o_drq_n : std_logic;
	signal irq_p1_edge : std_logic_vector(2 downto 0);
	signal irq_p1_n : std_logic;
	signal irq_p1_int_vec : std_logic_vector(7 downto 0);
	signal irq_p2_edge : std_logic_vector(2 downto 0);
	signal irq_p2_n : std_logic;
	signal irq_p2_int_vec : std_logic_vector(7 downto 0);
	signal irq_int_vec : std_logic_vector(7 downto 0);
	signal irq_invalid : std_logic;
	-- for bus master
	signal o_as_n : std_logic;
	signal o_lds_n : std_logic;
	signal o_uds_n : std_logic;
	signal i_dtack_n : std_logic;
	signal i_dtack_n_d : std_logic;
	signal i_dtack_n_dd : std_logic;
	signal i_dtack_n_ddd : std_logic;
	signal i_dtack_n_dddd : std_logic;
	signal i_dtack_n_ddddd : std_logic;
	signal o_rw : std_logic;
	signal o_br_n : std_logic;
	signal o_bgack_n : std_logic;
	type bus_state_t is(
	BS_IDLE,
	BS_S_ABIN_U,
	BS_S_ABIN_L,
	BS_S_EXMEM_FORK,
	BS_S_EXMEM_RD,
	BS_S_EXMEM_RD_FIN,
	BS_S_EXMEM_RD_FIN_2,
	BS_S_EXMEM_WR,
	BS_S_EXMEM_WR_FIN,
	BS_S_DBIN_P,
	BS_S_DBIN,
	BS_S_DBOUT,
	BS_S_FIN_WAIT,
	BS_S_FIN_RD,
	BS_S_FIN_RD_WAIT,
	BS_S_FIN,
	BS_S_INT,
	BS_S_IACK,
	BS_S_IACK2,
	BS_S_FAIL,
	BS_M_ABOUT_U,
	BS_M_ABOUT_L,
	BS_M_DBIN_WAIT, -- wait for data
	BS_M_DBIN, -- data in
	BS_M_DBOUT, -- data out
	BS_M_DBOUT_WAIT, -- wait for dtack
	BS_M_FIN_WAIT, -- wait for ack
	BS_M_FIN
	);
	signal bus_state : bus_state_t;
	signal bus_tick : std_logic_vector(5 downto 0);
	signal bus_tick_pause : std_logic;
	signal busmas_tick : std_logic_vector(5 downto 0);
	signal busmas_tick_pause : std_logic;
	signal bus_mode : std_logic_vector(3 downto 0);
	signal bus_readack_wait : std_logic_vector(1 downto 0);

	signal sys_fc : std_logic_vector(2 downto 0);
	signal sys_addr : std_logic_vector(23 downto 0);
	signal sys_idata : std_logic_vector(15 downto 0);
	signal sys_rw : std_logic;

	--
	-- busmaster access
	--
	signal busmas_req : std_logic;
	signal busmas_req_d : std_logic;
	signal busmas_ack : std_logic;
	signal busmas_ack_d : std_logic;
	signal busmas_fc : std_logic_vector(2 downto 0);
	signal busmas_addr : std_logic_vector(23 downto 0);
	signal busmas_rw : std_logic;
	signal busmas_uds_n : std_logic;
	signal busmas_lds_n : std_logic;
	signal busmas_odata : std_logic_vector(15 downto 0);
	signal busmas_idata : std_logic_vector(15 downto 0);
	signal busmas_counter : std_logic_vector(5 downto 0); -- for bus error timeout
	signal busmas_status_berr : std_logic;

	--
	-- debug
	--
	signal debug_as_count : std_logic_vector(10 downto 0);
	signal debug_as_n_sft : std_logic_vector(3 downto 0);
	signal debug_rw_d : std_logic;
	signal debug_invalid_addr : std_logic;
	signal debug_invalid_addr_latch : std_logic_vector(15 downto 0);

	--
	-- MI68 demo
	--
	type mem is array (0 to 15) of std_logic_vector(7 downto 0);
	constant CHAR_2 : mem := (
		0 => "00000000",
		1 => "00000000",
		2 => "00111100",
		3 => "01100110",
		4 => "01000010",
		5 => "01000010",
		6 => "00000110",
		7 => "00000100",
		8 => "00001100",
		9 => "00011000",
		10 => "00110000",
		11 => "01100000",
		12 => "01111110",
		13 => "00000000",
		14 => "00000000",
		15 => "00000000");

	constant CHAR_0 : mem := (
		0 => "00000000",
		1 => "00000000",
		2 => "00111100",
		3 => "01100110",
		4 => "01000010",
		5 => "01000010",
		6 => "01000010",
		7 => "01000010",
		8 => "01000010",
		9 => "01000010",
		10 => "01000010",
		11 => "01100110",
		12 => "00111100",
		13 => "00000000",
		14 => "00000000",
		15 => "00000000");

	signal mi68_bg : std_logic;

begin
	-- boot debug
	process (pClk50M, x68rstn) begin
		if (x68rstn = '0') then
			debug_as_count <= (others => '0');
			debug_rw_d <= '1';
			debug_as_n_sft <= (others => '1');
		elsif (pClk50M'event and pClk50M = '1') then
			debug_rw_d <= i_rw;
			debug_as_n_sft <= debug_as_n_sft(2 downto 0) & i_as_n;
			if (debug_as_n_sft = "1000" and debug_rw_d = '1') then --read access
				if (debug_as_count /= "11111111111") then
					debug_as_count <= debug_as_count + 1;
				end if;
			end if;
		end if;
	end process;

	-- 10MHz バスクロックのフリーランカウンタ
	process (x68clk10m)begin
		if (x68clk10m'event and x68clk10m = '1') then
			sys_counter_10m <= sys_counter_10m + 1;
		end if;
	end process;

	-- initializer
	-- 電源投入後、初回のリセット終了後に1回だけ実施するリセット処理を実現する
	-- ini_rstn 解除の前提として、
	-- 1. 本体の電源が投入されていること
	-- 2. Main PLLがロックしていること
	-- があるので、sys_clk は有効であるとみなして良い
	process (pClk50M, plllock_main) begin
		if (plllock_main = '0') then
			ini_power_on <= '0';
			ini_rst_counter <= (others => '0');
		elsif (pClk50M'event and pClk50M = '1') then
			if (sys_counter_10m(1) = '1') then
				-- 電源投入前にUSB Blaster経由でFPGAの電源が入ってしまうことがあるので、本体の電源が投入されたことをこれで検知している
				ini_power_on <= '1';
			end if;
			if (ini_rst_counter(6) = '0' and ini_power_on = '1') then
				ini_rst_counter <= ini_rst_counter + 1;
			end if;
		end if;
	end process;
	ini_rstn <= ini_rst_counter(6);

	--
	process (pClk50M, ini_rstn)
		variable led : std_logic;
	begin
		if (ini_rstn = '0') then
			x68rstn_d <= '1';
			x68rstn_dd <= '1';
			sec_counter_50m <= (others => '0');
			sec_counter_50m <= (others => '0');
			ini_rst_btn_counter <= (others => '0');
		elsif (pClk50M'event and pClk50M = '1') then
			x68rstn_d <= x68rstn;
			x68rstn_dd <= x68rstn_d;

			if (x68rstn_dd = '0' and x68rstn_d = '1') then
				if (sec_counter_50m(26 downto 24) = "000") then
					null; --チャタリング防止
				elsif (sec_counter_50m(26) = '0') then
					-- 前回のリセットから1秒以内にリセットボタンが押されていたらカウントアップ(最大7)
					if (ini_rst_btn_counter /= 7) then
						ini_rst_btn_counter <= ini_rst_btn_counter + 1;
					end if;
				else
					-- 初回リセット検知
					ini_rst_btn_counter <= (others => '0');
				end if;
				sec_counter_50m <= (others => '0');
			else
				if (sec_counter_50m(26) = '0') then
					sec_counter_50m <= sec_counter_50m + 1;
				else
					if (ini_rst_btn_counter < 4) then
						-- ４に到達しなかったら通常起動
						ini_rst_btn_counter <= (others => '0');
					elsif (ini_rst_btn_counter /= 7) then
						ini_rst_btn_counter <= "100";
					end if;
				end if;
			end if;

			led := sys_counter_10m(22);
			case ini_rst_btn_counter is
				when "000" =>
					-- 通常起動時
					pLED(7 downto 4) <= led & not led & led & not led;
				when "001" =>
					pLED(7 downto 4) <= "0001";
				when "010" =>
					pLED(7 downto 4) <= "0011";
				when "011" =>
					pLED(7 downto 4) <= "0111";
				when "100" =>
					pLED(7 downto 4) <= "1111";
				when "101" =>
					pLED(7 downto 4) <= "1110";
				when "110" =>
					pLED(7 downto 4) <= "1100";
				when "111" =>
					pLED(7 downto 4) <= led & led & led & led;
				when others =>
					pLED(7 downto 4) <= "0000";
			end case;
		end if;
	end process;

	safe_mode_level <=
		"01" when ini_rst_btn_counter = "100" else
		"10" when ini_rst_btn_counter = "111" else
		"00";

	pLED(3) <= '0';
	pLED(2) <= '0';
	pLED(1) <= '0';
	pLED(0) <= sys_counter_10m(23);

	-- Kepler-X のシステムリセット信号
	-- 電源投入後、PLLがロックして、EEPROMの設定の読み出しが完了するとシステム全体が動き出す
	-- その後、X68000側のリセットを押すと sys_rstnもアサートされるが、そのタイミングでは
	-- PLLはリセットされず、EEPROMの読み出しもされない
	-- なお DE0 Nanoの SW(3) が '1' の場合は EEPROMの設定を無視するので、その場合は読み出しの完了も待たず
	-- リセットを解除する（万が一I2Cのトラブルがあって読み込みが途中で止まった場合にそなえている)
	sys_rstn <= (pSW(3) or gpeeprom_ready) and plllock_main and x68rstn;

	-- 100MHz システムクロックのフリーランカウンタ
	process (sys_clk, sys_rstn)begin
		if (sys_rstn = '0') then
			sys_counter_100m <= (others => '0');
		elsif (sys_clk'event and sys_clk = '1') then
			sys_counter_100m <= sys_counter_100m + 1;
		end if;
	end process;
	--
	x68clk10m <= pGPIO1_IN(0);
	x68rstn <= pGPIO1(31);
	pGPIO1(31) <= 'Z';

	pllrst <= not x68rstn;
	pllmain_inst : pllmain port map(
		areset => '0', -- never reset after power on
		inclk0 => pClk50M,
		c0 => mem_clk, -- 100MHz
		c1 => pDRAM_CLK, -- 100MHz + 180°
		c2 => open, --sys_clk, -- 25MHz
		c3 => snd_clk, -- 16MHz
		c4 => pcm_clk_8M,
		locked => plllock_main
	);
	sys_clk <= mem_clk;

	pllpcm48k_inst : pllpcm48k port map(
		areset => pllrst,
		inclk0 => pClk24M576,
		c0 => pcm_clk_24M576, -- 24.576MHz
		c1 => pcm_clk_6M144, -- 24.576MHz / 4 = 6.144MHz
		c2 => i2s_bclk, -- 24.576MHz / 8 = 3.072MHz
		locked => plllock_pcm48k
	);

	pllpcm44k1_inst : pllpcm44k1 port map(
		areset => pllrst,
		inclk0 => pClk24M576,
		c0 => pcm_clk_5M6448, -- 22.5792MHz / 4
		locked => plllock_pcm44k1
	);

	plldvi_inst : plldvi port map(
		areset => pllrst,
		inclk0 => pClk50M,
		c0 => hdmi_clk, -- 27MHz
		c1 => hdmi_clk_x5, -- 135MHz
		locked => plllock_dvi
	);

	-- X68000 Bus Access
	i_as_n <= pGPIO0(21);
	i_lds_n <= pGPIO0(22);
	i_uds_n <= pGPIO0(23);
	i_rw <= pGPIO0(24);
	i_iack_n <= pGPIO1(4);
	pGPIO1(4) <= 'Z';
	i_bg_n <= pGPIO1(5);
	pGPIO1(5) <= 'Z';
	i_dtack_n <= pGPIO0(27);

	pGPIO0(27) <= 'Z' when o_dtack_n = '1' or i_as_n = '1' else '0';
	pGPIO0(28) <= 'Z' when o_drq_n = '1' else '0'; -- EXREQ
	pGPIO0(31) <= '1' when o_irq_n = '1' else '0'; -- IRQはスロットごとに分かれているので'Z'にしなくてよい。'Z'だとIRQのネゲートが遅く、変な割り込みがかかることがあるようなので'1'にしている
	pGPIO0(32) <= 'Z' when o_br_n = '1' else '0';
	pGPIO0(33) <= 'Z' when o_bgack_n = '1' else '0';
	pGPIO0(21) <= 'Z' when o_as_n = '1' else '0';
	pGPIO0(22) <= 'Z' when o_lds_n = '1' else '0';
	pGPIO0(23) <= 'Z' when o_uds_n = '1' else '0';
	pGPIO0(24) <= 'Z' when o_as_n = '1' else o_rw;

	o_drq_n <= mercury_drq_n;
	--o_drq <= mercury_pcl;

	process (mem_clk, sys_rstn)
	begin
		if (sys_rstn = '0') then
			o_irq_n <= '1';
			i_iack_n_edge <= (others => '1');
			irq_p1_edge <= (others => '1');
			irq_p1_n <= '1';
			irq_p1_int_vec <= (others => '0');
			irq_p2_edge <= (others => '1');
			irq_p2_n <= '1';
			irq_p2_int_vec <= (others => '0');
			irq_int_vec <= (others => '0');
			irq_invalid <= '0';
		elsif (mem_clk'event and mem_clk = '1') then
			o_irq_n <= irq_p1_n and irq_p2_n;

			i_iack_n_edge <= i_iack_n_edge(1 downto 0) & i_iack_n;

			irq_p1_edge <= irq_p1_edge(1 downto 0) & mercury_irq_n;
			irq_p2_edge <= irq_p2_edge(1 downto 0) & midi_irq_n;

			-- edge detection
			-- 割り込み要求がでっぱなしの場合でも2回以上の割り込みは発生させないようにしている
			-- ただし、割り込みが受け付けられる前にクリアされた場合は割り込み要求も解除する(間に合えば)
			if (irq_p1_edge(1) = '1') then
				irq_p1_n <= '1';
			else
				if (irq_p1_edge(2 downto 1) = "10") then
					irq_p1_n <= '0';
					irq_p1_int_vec <= mercury_int_vec;
				end if;
			end if;
			if (irq_p2_edge(1) = '1') then
				irq_p2_n <= '1';
			else
				if (irq_p2_edge(2 downto 1) = "10") then
					irq_p2_n <= '0';
					irq_p2_int_vec <= midi_int_vec;
				end if;
			end if;

			if (i_iack_n_edge(2 downto 1) = "10") then -- falling edge
				if (irq_p1_n = '0') then -- priority high
					irq_p1_n <= '1';
					irq_int_vec <= irq_p1_int_vec;
				elsif (irq_p2_n = '0') then
					irq_p2_n <= '1';
					irq_int_vec <= irq_p2_int_vec;
				else
					irq_invalid <= '1'; -- ありえないはずだが、もしここに落ちた場合は無視する
				end if;
			elsif (i_iack_n_edge(2 downto 1) = "01") then -- rising edge
				irq_invalid <= '0';
			end if;
		end if;
	end process;

	pGPIO0(15) <= bus_mode(0);
	pGPIO0(14) <= bus_mode(1);
	pGPIO0(13) <= bus_mode(2);
	pGPIO0(12) <= bus_mode(3);

	pGPIO1(21 downto 6) <=
	exmem_odata when sys_rw = '1' and (
	(bus_state = BS_S_EXMEM_RD_FIN and bus_tick > 13) or
	bus_state = BS_S_EXMEM_RD_FIN_2
	) else
	o_sdata when sys_rw = '1' and (
	--bus_state = BS_S_EXMEM_RD_FIN or
	--bus_state = BS_S_EXMEM_RD_FIN_2 or
	bus_state = BS_S_FIN_WAIT or
	bus_state = BS_S_FIN_RD or
	bus_state = BS_S_FIN_RD_WAIT or
	bus_state = BS_S_FIN
	) else
	o_sdata when bus_state = BS_S_IACK or bus_state = BS_S_IACK2 else
	o_sdata when bus_state = BS_M_ABOUT_U or bus_state = BS_M_ABOUT_L or bus_state = BS_M_DBOUT else
	(others => 'Z');

	process (mem_clk, sys_rstn)
		variable cs : std_logic;
		variable fin : std_logic;
		variable addr_block : std_logic_vector(3 downto 0);
		variable safe_delay : integer;
	begin
		if (sys_rstn = '0') then
			x68clk10m_d <= '0';
			x68clk10m_dd <= '0';
			m68k_state <= M68K_S0;
			sys_fc <= (others => '0');
			sys_addr <= (others => '0');
			bus_tick <= (others => '0');
			bus_tick_pause <= '0';
			busmas_tick <= (others => '0');
			busmas_tick_pause <= '0';
			--
			cs := '0';
			fin := '0';
			safe_delay := 0;
			addr_block := (others => '0');
			bus_state <= BS_IDLE;
			bus_mode <= "0000";
			bus_readack_wait <= (others => '0');
			sys_idata <= (others => '0');
			sys_rw <= '1';
			o_dtack_n <= '1';
			i_as_n_sft <= (others => '1');
			i_as_n_d <= '1';
			i_as_n_dd <= '1';
			i_rw_d <= '1';
			i_uds_n_d <= '1';
			i_lds_n_d <= '1';
			i_dtack_n_d <= '1';
			i_dtack_n_dd <= '1';
			i_dtack_n_ddd <= '1';
			i_dtack_n_dddd <= '1';
			i_dtack_n_ddddd <= '1';
			i_sdata <= (others => '0');
			exmem_req <= '0';
			exmem_ack_d <= '0';
			exmem_ref_lock_req <= '0';
			exmem_enabled <= (others => '0');
			exmem_idata <= (others => '0');
			keplerx_reg_update_req <= (others => '0');
			keplerx_req <= '0';
			areaset_req <= '0';
			opm_req <= '0';
			adpcm_req <= '0';
			ppi1_req <= '0';
			ppi2_req <= '0';
			mercury_req <= '0';

			-- busmaster access
			o_br_n <= '1';
			o_bgack_n <= '1';
			o_as_n <= '1';
			o_lds_n <= '1';
			o_uds_n <= '1';
			o_rw <= '1';
			busmas_req_d <= '0';
			busmas_ack <= '0';
			busmas_idata <= (others => '0');
			busmas_tick <= (others => '0');
			busmas_tick_pause <= '1';
		elsif (mem_clk'event and mem_clk = '1') then
			i_sdata <= pGPIO1(21 downto 6);
			x68clk10m_d <= x68clk10m;
			x68clk10m_dd <= x68clk10m_d;
			if ((bus_tick /= "011111") and (bus_tick /= "111111") and (bus_tick_pause = '0')) then
				bus_tick <= bus_tick + 1;
			end if;
			-- 立ち上がりエッジで ASがアサートされていなかったら、それはS0 or S2
			-- なので、今S1じゃないなら強制的にS0にする
			if (x68clk10m_dd = '0' and x68clk10m_d = '1' and i_as_n_d = '1' and m68k_state /= M68k_S1) then
				m68k_state <= M68K_S0;
			elsif (busmas_tick /= 0) then
				m68k_state <= M68K_S0;
			else
				case m68k_state is
					when M68K_S0 =>
						bus_mode <= "0000";
						if (x68clk10m_d = '0') then -- falling edge
							m68k_state <= M68K_S1;
							bus_tick <= (others => '0');
						end if;
					when M68K_S1 =>
						if (x68clk10m_d = '1') then -- rising edge
							m68k_state <= M68K_S2;
						end if;
					when M68K_S2 =>
						if (x68clk10m_d = '0') then -- falling edge
							-- ASがアサートされていないならS1に戻る
							-- ASがアサートされていたならバスサイクルは始まっている
							if (i_as_n_dd = '1') then -- Phantom XのRWの確定がASより遅れてくる問題に対応するため、ASを10nsec遅延させるため、ddを使う
								m68k_state <= M68K_S1;
								bus_tick <= (others => '0');
							else
								m68k_state <= M68K_S3;
							end if;
						end if;
					when M68K_S3 =>
						if (x68clk10m_d = '1') then -- rising edge
							m68k_state <= M68K_S4;
						end if;
					when M68K_S4 =>
						if (x68clk10m_dd = '1' and x68clk10m_d = '0') then -- falling edge
							-- S4の最後のエッジ(立ち下がり)でDTACKがアサートされていた時だけS5へ
							if (i_dtack_n_ddddd = '0') then
								m68k_state <= M68K_S5;
							end if;
						end if;
					when M68K_S5 =>
						if (x68clk10m_d = '1') then -- rising edge
							m68k_state <= M68K_S6;
							bus_tick <= "100000";
						end if;
					when M68K_S6 =>
						if (x68clk10m_d = '0') then -- falling edge
							m68k_state <= M68K_S7;
						end if;
					when M68K_S7 =>
						-- S0へのリセットは外部でやっているのでここでは何もしない
						null;
				end case;
			end if;

			-- ASがアサートされるよりも先にアドレスをラッチするために、10MHzのクロックのエッジを見て68000の
			-- ステート(S0-S7)を推測している
			-- S1に入ったタイミング(tick=0)でアドレスラッチを先出し、S2の終わりまでにASのアサートを
			-- 確認できなければS1からやり直す(tickが0に戻る)ことでそれを実現している
			if (exmem_enabled(15) = '0') then -- no-wait mode
				safe_delay := 0;
			else
				safe_delay := 2;
			end if;
			if (busmas_tick = 0) then
				if (bus_tick = 1 + safe_delay) then -- ★start
					-- S1の始まり(tick=0, 10MHzクロックの立ち下がりエッジ)でアドレスラッチをかける
					-- 遅延などもあるので、だいたいS1の終わり付近で確定するアドレスを捉えられる
					bus_mode <= "1000";
				elsif (bus_tick = 4 + safe_delay) then -- ★+3のタイミング。経験上これ以上は詰められない。
					-- 投機的に下位アドレスをラッチしに行く(ASがアサートされなければS1に戻ってやり直しになる)
					-- GreenPakの遅延があるので60nsec後くらい(tick=9,10あたり)で読めるようになる
					bus_mode <= "0001";
				elsif (bus_tick = 8 + safe_delay) then -- ★+7のタイミング。経験上これ以上は詰められない。
					-- GreenPakの遅延があるので、このタイミングでようやく上位アドレスが取り込める
					sys_fc(2 downto 0) <= i_sdata(10 downto 8);
					sys_addr(23 downto 16) <= i_sdata(7 downto 0);
					debug_invalid_addr_latch <= i_sdata(15 downto 1) & "0";
				elsif (bus_tick = 12 + safe_delay) then -- ★+11のタイミング。経験上これ以上は詰められない。
					-- GrenPakの遅延があるので、このタイミングで下位アドレスが取り込める
					sys_addr(15 downto 0) <= i_sdata(15 downto 1) & "0";
				end if;
			end if;
			-- debug
			if ((debug_as_count /= x"7ff") and ((debug_invalid_addr_latch(15 downto 11) /= 0) or (sys_fc = 0) or (sys_fc = 3) or (sys_fc = 4)) and (sys_addr(15 downto 0) = debug_invalid_addr_latch)) then
				debug_invalid_addr <= '1';
			else
				debug_invalid_addr <= '0';
			end if;

			--
			-- Phantom XのRWの確定がASより遅れてくる問題に対応するため、ASを10nsec遅延させる
			-- また、ASアサート中にパルスのノイズが入ることがあるので、1クロックのパルスを除去する
			i_as_n_sft <= i_as_n_sft(1 downto 0) & i_as_n;
			i_as_n_d <= i_as_n_sft(0) and i_as_n;
			i_as_n_dd <= i_as_n_d;
			i_rw_d <= i_rw;
			i_uds_n_d <= i_uds_n;
			i_lds_n_d <= i_lds_n;
			i_dtack_n_d <= i_dtack_n;
			i_dtack_n_dd <= i_dtack_n_d;
			i_dtack_n_ddd <= i_dtack_n_dd;
			i_dtack_n_dddd <= i_dtack_n_ddd;
			i_dtack_n_ddddd <= i_dtack_n_dddd;
			exmem_ack_d <= exmem_ack;
			bus_tick_pause <= '0';

			if (i_as_n_d = '1') then
				o_dtack_n <= '1';
			end if;

			-- busmaster request
			if ((busmas_tick /= "011111") and (busmas_tick /= "111111") and (busmas_tick_pause = '0')) then
				busmas_tick <= busmas_tick + 1;
			end if;
			busmas_req_d <= busmas_req;
			i_bg_n_d <= i_bg_n;
			if (busmas_req_d /= busmas_ack and o_bgack_n = '1') then
				-- バスマスタでアクセスしたくなったらとにかくバスリクエストを出す
				o_br_n <= '0';
			end if;

			--
			-- bus state machine
			--
			case bus_state is
				when BS_IDLE =>
					o_dtack_n <= '1';
					keplerx_req <= '0';
					areaset_req <= '0';
					opm_req <= '0';
					adpcm_req <= '0';
					ppi1_req <= '0';
					ppi2_req <= '0';
					mercury_req <= '0';
					exmem_req <= '0';
					exmem_idata <= (others => '0');
					exmem_enabled <= keplerx_reg(3);
					-- bus master
					busmas_tick <= (others => '0');
					busmas_tick_pause <= '1';
					o_bgack_n <= '1';
					o_as_n <= '1';
					o_uds_n <= '1';
					o_lds_n <= '1';
					if (o_br_n = '0' and i_bg_n_d = '0' and i_as_n_d = '1' and i_dtack_n_d = '1') then
						-- bus granted
						bus_mode <= "1000";
						o_bgack_n <= '0';
						o_br_n <= '1';
						bus_state <= BS_M_ABOUT_U;
						busmas_tick_pause <= '0';
					elsif (m68k_state = M68K_S2 and x68clk10m_d = '0' and i_as_n_dd = '0') then -- Phantom XのRWの確定がASより遅れてくる問題に対応するため、ASを10nsec遅延させるため、ddを使う
						-- S2の最後でASがアサートされてS3に入ったらバスアクセス開始
						bus_state <= BS_S_ABIN_U;
						-- 400nsecだと、早すぎることがある(リフレッシュサイクルのアクセスみたいなのを拾ってしまうことがある)
						-- 800nsecだと、PhantomXの起動時のメモリチェックで「メモリがない」とみなされてしまうことがある
						-- よって、500nsecにしている
						exmem_watchdog <= x"32"; -- 50 clocks @100MHz = 500nsec
					end if;

					if (m68k_state = M68K_S0) then
						exmem_ref_lock_req <= '0';
					elsif (m68k_state = M68K_S1) then
						exmem_ref_lock_req <= '1';
					elsif (m68k_state = M68K_S2 and x68clk10m_d = '0' and i_as_n_dd = '1') then -- Phantom XのRWの確定がASより遅れてくる問題に対応するため、ASを10nsec遅延させるため、ddを使う
						exmem_ref_lock_req <= '0';
					end if;

				when BS_S_ABIN_U =>
					sys_rw <= i_rw_d; -- Phantom Xだと RWが少し遅れて確定するので、ここで取り込み
					if (i_as_n_d = '1') then -- 自分以外が応答していたらIDLEに戻る
						bus_mode <= "0000";
						bus_state <= BS_IDLE;
					else
						if (bus_tick < 9 + safe_delay) then
							null;
						else
							case sys_fc is
								when "000" | "011" | "100" =>
									-- no defined
									bus_mode <= "0000";
									exmem_ref_lock_req <= '0';
									bus_state <= BS_IDLE;
								when "001" | "010" | "101" | "110" =>
									-- user access and supervisor access
									if (sys_addr(23 downto 20) >= x"1" and sys_addr(23 downto 20) < x"c" and keplerx_reg(4)(0) = '1') then -- exmem enable flag
										addr_block := sys_addr(23 downto 20); -- 0x1 to 0xc
										if (exmem_enabled(15) = '0' and exmem_enabled(CONV_INTEGER(addr_block)) = '1') then
											-- no-wait mode時はDTACK先出し
											if (exmem_ref_lock_ack = '1') then -- ロックは間に合うはずだが、念の為リフレッシュサイクルの時は先出しない
												o_dtack_n <= '0'; -- XVIの 16MHzモード時だと、ここで出してもノーウェイトにならないがこれ以上早められない(要対策)
											end if;
										end if;
										bus_state <= BS_S_EXMEM_FORK;
									else
										exmem_ref_lock_req <= '0';
										bus_state <= BS_S_ABIN_L;
									end if;
								when "111" =>
									exmem_ref_lock_req <= '0';
									bus_state <= BS_S_INT;
								when others =>
									bus_mode <= "0000";
									bus_state <= BS_IDLE;
							end case;
						end if;
					end if;
				when BS_S_ABIN_L =>
					if (i_as_n_d = '1') then -- 自分以外が応答していたらIDLEに戻る
						bus_mode <= "0000";
						bus_state <= BS_IDLE;
					else
						if (bus_tick < 13 + safe_delay) then
							null;
						else
							if (sys_rw = '1') then
								bus_mode <= "0101";
								bus_state <= BS_S_DBOUT;
							else
								-- ライト時のみDTACK先出し
								if (sys_addr(23 downto 8) = x"ecb0") then -- Kepler-X register
									o_dtack_n <= '0';
								elsif (sys_fc(2) = '1' and sys_addr(23 downto 4) = x"eafa0" and keplerx_reg(4)(1) = '1') then -- MIDI I/F
									o_dtack_n <= '0';
								elsif (sys_fc(2) = '1' and sys_addr(23 downto 3) = x"ecb10" & "0") and i_lds_n_d = '0' then -- PPI (8255) for JMMCSCSI
									o_dtack_n <= '0';
								elsif (sys_addr(23 downto 7) = x"ecc0" & "1" and keplerx_reg(4)(2) = '1') then -- Mercury Unit
									o_dtack_n <= '0';
								end if;
								bus_state <= BS_S_DBIN_P;
							end if;
						end if;
					end if;

					-- exmem access
				when BS_S_EXMEM_FORK =>
					if (keplerx_reg(4)(0) = '0') then -- 拡張メモリが無効なら終了
						exmem_req <= '0'; -- 投機的に実行していたリクエストを下げる
						bus_mode <= "0000";
						bus_state <= BS_IDLE;
					else
						addr_block := sys_addr(23 downto 20); -- 0x1 to 0xc
						if (exmem_enabled(CONV_INTEGER(addr_block)) = '1') then
							if (sys_rw = '1') then
								bus_state <= BS_S_EXMEM_RD;
								exmem_req <= '1';
								bus_mode <= "0101";
							else
								bus_state <= BS_S_EXMEM_WR;
							end if;
						else
							if ((exmem_enabled(0) = '0') or (sys_addr(23 downto 20) = x"1")) then
								-- メモリ自動認識無効時 or メモリブロックが 0x1xxxxxの時は何もしない
								exmem_req <= '0'; -- 投機的に実行していたリクエストを下げる
								bus_mode <= "0000";
								bus_state <= BS_IDLE;
							elsif (i_as_n_d = '1' or i_dtack_n_d = '0') then
								-- 自分以外の誰かが応答したら無視
								bus_mode <= "0000";
								bus_state <= BS_IDLE;
							else
								bus_tick_pause <= '1'; -- タイムアウト待ちの間停止させる
								if (exmem_watchdog = 0) then
									-- 一定時間内に誰も DTACKをアサートしなかったら自分が応答
									-- フラグを立てて、次回は自動応答
									exmem_enabled(CONV_INTEGER(addr_block)) <= '1';
									keplerx_reg_update_req(3) <= not keplerx_reg_update_req(3);
									if (sys_rw = '1') then
										exmem_req <= '1'; -- 投機的に実行(再実行)
									end if;
								else
									exmem_req <= '0'; -- 投機的に実行していたリクエストを一度下げる
									exmem_watchdog <= exmem_watchdog - 1;
								end if;
							end if;
						end if;
					end if;
					-- exmem read
				when BS_S_EXMEM_RD =>
					bus_mode <= "0101";
					bus_state <= BS_S_EXMEM_RD_FIN;
				when BS_S_EXMEM_RD_FIN =>
					if (bus_tick = x"11" and exmem_enabled(15) = '0') then -- no-wait mode
						bus_mode <= "0100"; -- latch return data
					end if;
					o_sdata <= exmem_odata;
					if exmem_odata_ready = '1' then
						if (addr_block /= x"1") then
							o_dtack_n <= '0'; -- 自動認識時やsafe_modeで遅延した時のためにここでもアサート
						end if;
						bus_mode <= "0100"; -- 自動認識時時やsafe_modeで遅延した時のためにここでも再設定
						exmem_req <= '0';
						bus_state <= BS_S_EXMEM_RD_FIN_2;
					end if;
				when BS_S_EXMEM_RD_FIN_2 =>
					exmem_ref_lock_req <= '0';
					if (i_as_n_d = '1') then
						bus_mode <= "0000";
						bus_state <= BS_IDLE;
					end if;
					-- exmem write
				when BS_S_EXMEM_WR =>
					if (addr_block /= x"1" and exmem_enabled(15) = '0') then -- no-wait mode
						o_dtack_n <= '0'; -- DTACK先出し
					end if;
					if (bus_tick < 15 + safe_delay) then
						-- 書き込みデータがバスに乗るまで待つ
						null;
					else
						bus_mode <= "0011";
						if (bus_tick < 15 + 9 + safe_delay) then
							-- 16374の切替完了を9クロック待つ
							null;
						else
							-- 取り込み完了
							exmem_idata <= i_sdata(15 downto 0);
							exmem_req <= '1';
							bus_mode <= "0010";
							if (addr_block /= x"1") then
								o_dtack_n <= '0'; -- DTACK先出し
							end if;
							bus_state <= BS_S_EXMEM_WR_FIN;
						end if;
					end if;
				when BS_S_EXMEM_WR_FIN =>
					exmem_ref_lock_req <= '0';
					if (i_as_n_d = '1') then
						exmem_req <= '0';
						bus_mode <= "0000";
						bus_state <= BS_IDLE;
					end if;

					-- write cycle
				when BS_S_DBIN_P =>
					if (i_as_n_d = '1') then -- 自分以外が応答していたらIDLEに戻る
						bus_mode <= "0000";
						bus_state <= BS_IDLE;
					else
						if (bus_tick < 15 + safe_delay) then
							-- 書き込みデータがバスに乗るまで待つ
							null;
						else
							bus_mode <= "0011";
							if (i_lds_n_d = '1' and i_uds_n_d = '1') then
								-- もう16374のラッチはかけてしまっているのだが、次のステートで UDS/LDS が確定している必要があるので
								-- もし確定していなかったらしばらく待つ (実際、ADPCMのアクセスなどで遅い場合がある)
								null;
							elsif (bus_tick < 15 + 9 + safe_delay) then
								-- 16374の切替完了を9クロック待つ
								null;
							else
								-- 取り込み完了
								sys_idata <= i_sdata(15 downto 0);
								bus_state <= BS_S_DBIN;
							end if;
						end if;
					end if;
				when BS_S_DBIN =>
					sys_idata <= i_sdata(15 downto 0);
					cs := '0';
					if (sys_addr(23 downto 8) = x"ecb0") then -- Kepler-X register
						keplerx_req <= '1';
						cs := '1';
						o_dtack_n <= '0';
					elsif (sys_addr(23 downto 8) = x"ecb1") then -- Kepler-X register (EEPROM)
						keplerx_req <= '1';
						cs := '1';
						o_dtack_n <= '0';
					elsif (sys_fc(2) = '1' and sys_addr(23 downto 12) = x"e86") then -- AREA set register
						areaset_req <= '1';
						cs := '1';
					elsif (sys_addr(23 downto 2) = x"e9000" & "00") then -- OPM (YM2151)
						opm_req <= '1';
						cs := '1';
					elsif (sys_addr(23 downto 2) = x"e9200" & "00") and i_lds_n_d = '0' then -- ADPCM (6258)
						adpcm_req <= '1';
						cs := '1';
					elsif (sys_fc(2) = '1' and sys_addr(23 downto 4) = x"eafa0" and keplerx_reg(4)(1) = '1') then -- MIDI I/F (Super Visor Only)
						midi_req <= '1';
						cs := '1';
						o_dtack_n <= '0';
					elsif (sys_fc(2) = '1' and sys_addr(23 downto 3) = x"e9a00" & "0") and i_lds_n_d = '0' then -- PPI (8255) (Super Visor Only)
						ppi1_req <= '1';
						cs := '1';
					elsif (sys_fc(2) = '1' and sys_addr(23 downto 3) = x"ecb10" & "0") and i_lds_n_d = '0' then -- PPI (8255) for JMMCSCSI
						ppi2_req <= '1';
						cs := '1';
						o_dtack_n <= '0';
					elsif (sys_addr(23 downto 7) = x"ecc0" & "1" and keplerx_reg(4)(2) = '1') then -- Mercury Unit
						-- 0xecc080〜0xecc0ff
						mercury_req <= '1';
						cs := '1';
					else
						cs := '0';
					end if;

					if cs = '1' then
						bus_state <= BS_S_FIN_WAIT;
					else
						bus_mode <= "0000";
						bus_state <= BS_IDLE;
					end if;

					-- interrup acknowledge cycle
				when BS_S_INT =>
					if (bus_tick < 15 + safe_delay) then -- sys_addr 確定まで待つ
						null;
					elsif (sys_addr(19 downto 16) = x"f") then -- interrupt acknowledge
						-- 割り込みレベル 4 or 2のときかつ、iackがアサートされている時
						if (i_iack_n_edge(1) = '0' and --
							(sys_addr(3 downto 1) = 4 or sys_addr(3 downto 1) = 2)) then
							if irq_invalid = '0' then -- 割り込み要求を出していない場合は無視
								-- Kepler Xの割り込み応答
								bus_mode <= "0101";
								bus_state <= BS_S_IACK;
							else
								-- 基本的にはありえないはずだが、起きたことがあるので念のため
								bus_mode <= "0000";
								bus_state <= BS_S_FAIL; -- FAILステートはロジアナでトリガーをかけるために入れている
							end if;
						else
							-- 本体側のMFPの割り込みなどが見えることがある
							bus_mode <= "0000";
							bus_state <= BS_IDLE;
						end if;
					else
						-- 基本的にはありえないはず
						bus_mode <= "0000";
						bus_state <= BS_S_FAIL; -- FAILステートはロジアナでトリガーをかけるために入れている
					end if;
				when BS_S_IACK =>
					o_sdata <= x"00" & irq_int_vec;
					bus_state <= BS_S_IACK2;
				when BS_S_IACK2 =>
					bus_state <= BS_S_FIN_RD;
				when BS_S_FAIL => -- for logic analyzer capture
					bus_state <= BS_IDLE;

					-- read cycle
				when BS_S_DBOUT =>
					cs := '0';
					if (sys_addr(23 downto 8) = x"ecb0") then -- Kepler-X register
						keplerx_req <= '1';
						cs := '1';
					elsif (sys_addr(23 downto 8) = x"ecb1") then -- Kepler-X register (EEPROM)
						keplerx_req <= '1';
						cs := '1';
					elsif (sys_addr(23 downto 2) = x"e9000" & "00") then -- OPM (YM2151)
						-- ignore read cycle
						opm_req <= '0';
						cs := '0';
					elsif (sys_addr(23 downto 2) = x"e9200" & "00") then -- ADPCM (6258)
						-- ignore read cycle
						adpcm_req <= '0';
						cs := '0';
					elsif (sys_fc(2) = '1' and sys_addr(23 downto 4) = x"eafa0" and keplerx_reg(4)(1) = '1') then -- MIDI I/F (Super Visor Only)
						midi_req <= '1';
						cs := '1';
					elsif (sys_fc(2) = '1' and sys_addr(23 downto 3) = x"e9a00" & "0") then -- PPI (8255) (Super Visor Only)
						-- ignore read cycle
						ppi1_req <= '0';
						cs := '0';
					elsif (sys_fc(2) = '1' and sys_addr(23 downto 3) = x"ecb10" & "0") then -- PPI (8255) for JMMCSCSI
						-- execb100〜0xecb107
						ppi2_req <= '1';
						cs := '1';
					elsif (sys_addr(23 downto 7) = x"ecc0" & "1" and keplerx_reg(4)(2) = '1') then -- Mercury Unit
						-- 0xecc080〜0xecc0ff
						mercury_req <= '1';
						cs := '1';
					else
						cs := '0';
					end if;

					if cs = '1' then
						bus_state <= BS_S_FIN_WAIT;
					else
						bus_mode <= "0000";
						bus_state <= BS_IDLE;
					end if;

					-- finish
				when BS_S_FIN_WAIT =>
					fin := '0';
					if keplerx_req = '1' then
						o_sdata <= keplerx_odata;
						if keplerx_ack = '1' then
							o_dtack_n <= '0';
							keplerx_req <= '0';
							fin := '1';
						end if;
					elsif areaset_req = '1' then
						-- write only
						o_sdata <= (others => '0');
						if areaset_ack = '1' then
							areaset_req <= '0';
							fin := '1';
						end if;
					elsif opm_req = '1' then
						-- write only
						o_sdata <= (others => '0');
						if opm_ack = '1' then
							opm_req <= '0';
							bus_mode <= "0000";
							bus_state <= BS_IDLE; -- ignore dtack
						end if;
					elsif adpcm_req = '1' then
						-- write only
						o_sdata <= (others => '0');
						if adpcm_ack = '1' then
							adpcm_req <= '0';
							bus_mode <= "0000";
							bus_state <= BS_IDLE; -- ignore dtack
						end if;
					elsif midi_req = '1' then
						o_sdata <= x"ff" & midi_odata;
						if midi_ack = '1' then
							midi_req <= '0';
							fin := '1';
						end if;
					elsif ppi1_req = '1' then
						-- write only
						o_sdata <= (others => '0');
						if ppi1_ack = '1' then
							ppi1_req <= '0';
							bus_mode <= "0000";
							bus_state <= BS_IDLE; -- ignore dtack
						end if;
					elsif ppi2_req = '1' then
						o_sdata <= x"00" & ppi2_odata;
						if ppi2_ack = '1' then
							ppi2_req <= '0';
							fin := '1';
						end if;
					elsif mercury_req = '1' then
						o_sdata <= mercury_odata;
						if mercury_ack = '1' then
							mercury_req <= '0';
							fin := '1';
						end if;
					else
						-- invalid state (no req was found)
						bus_mode <= "0000";
						bus_state <= BS_IDLE;
					end if;

					if fin = '1' then
						if (sys_rw = '0') then
							bus_state <= BS_S_FIN;
							o_dtack_n <= '0';
						else
							bus_state <= BS_S_FIN_RD;
						end if;
					end if;
				when BS_S_FIN_RD =>
					bus_mode <= "0100"; -- latch return data
					bus_readack_wait <= "11";
					bus_state <= BS_S_FIN_RD_WAIT;

				when BS_S_FIN_RD_WAIT =>
					-- 確実にデータがバスに乗ってから DTACK をアサートする
					if (bus_readack_wait = 0) then
						o_dtack_n <= '0';
						bus_state <= BS_S_FIN;
					else
						bus_readack_wait <= bus_readack_wait - 1;
					end if;

				when BS_S_FIN =>
					if (sys_rw = '1') then
						bus_mode <= "0100";
					else
						bus_mode <= "0010";
					end if;
					if (i_as_n_d = '1') then
						bus_mode <= "0000";
						o_dtack_n <= '1';
						bus_state <= BS_IDLE;
					end if;

					--
					-- bus master cyle
					--
				when BS_M_ABOUT_U =>
					if (busmas_tick < 2) then
						bus_mode <= "1000"; -- "0000"から"1001"に遷移するためのつなぎ
						o_sdata <= "00000" & --
							busmas_fc & -- FC2-0 : "101" is supervisor data
							busmas_addr(23 downto 16);
					elsif (busmas_tick < 4) then
						bus_mode <= "1001"; -- AB出力準備
					elsif (busmas_tick < 6) then
						bus_mode <= "1011"; -- AB出力(U)
					elsif (busmas_tick < 12) then
						null; -- 取り込まれるのを待つ
					else
						bus_state <= BS_M_ABOUT_L;
					end if;
				when BS_M_ABOUT_L =>
					if (busmas_tick < 14) then
						bus_mode <= "1111"; -- AB出力(L)
						o_sdata <= busmas_addr(15 downto 0);
					elsif (busmas_tick < 20) then
						null; -- 取り込まれるのを待つ
					else
						o_rw <= busmas_rw;
						if (busmas_rw = '1') then
							bus_state <= BS_M_DBIN_WAIT;
							busmas_counter <= (others => '1');
						else
							o_sdata <= busmas_odata;
							bus_state <= BS_M_DBOUT;
						end if;
					end if;
					-- read cycle
				when BS_M_DBIN_WAIT =>
					-- アドレスをアサートして、相手のDTACKを待つ
					bus_mode <= "1110";
					o_as_n <= '0';
					o_uds_n <= busmas_uds_n;
					o_lds_n <= busmas_lds_n;
					if (i_dtack_n_ddd = '0') then
						busmas_tick <= "100000";
						busmas_status_berr <= '0';
						bus_state <= BS_M_DBIN;
					else
						if (busmas_counter = 0) then
							-- bus error
							busmas_status_berr <= '1';
							bus_state <= BS_M_FIN_WAIT;
						else
							busmas_counter <= busmas_counter - 1;
						end if;
					end if;
				when BS_M_DBIN =>
					-- リードデータ取り込み
					if (busmas_tick < 32 + 5) then
						null;
					elsif (busmas_tick < 32 + 12) then
						bus_mode <= "1010"; -- DICK rise
					elsif (busmas_tick < 32 + 18) then
						null; -- 16374のラッチ待ち
					else
						busmas_idata <= i_sdata;
						bus_state <= BS_M_FIN_WAIT;
					end if;
					-- write cycle
				when BS_M_DBOUT =>
					if (busmas_tick < 20 + 5) then
						bus_mode <= "1101"; -- "1111"から"1100"に遷移するための中間状態
					elsif (busmas_tick < 20 + 7) then
						bus_mode <= "1100"; -- DOCK rise
					elsif (busmas_tick < 31) then
						null;
					else
						--このタイミングで16374に出力データが取り込まれるので、次のステートでAS,UDS,LDSをアサート
						bus_state <= BS_M_DBOUT_WAIT;
						busmas_counter <= (others => '1');
					end if;
				when BS_M_DBOUT_WAIT =>
					o_as_n <= '0';
					o_uds_n <= busmas_uds_n;
					o_lds_n <= busmas_lds_n;
					if (i_dtack_n_d = '0') then
						bus_state <= BS_M_FIN_WAIT;
						busmas_status_berr <= '0';
					else
						if (busmas_counter = 0) then
							-- bus error
							busmas_status_berr <= '1';
							bus_state <= BS_M_FIN_WAIT;
						else
							busmas_counter <= busmas_counter - 1;
						end if;
					end if;
				when BS_M_FIN_WAIT =>
					if (busmas_rw = '1') then
						bus_mode <= "1010";
					else
						bus_mode <= "1100";
					end if;
					o_as_n <= '1';
					o_uds_n <= '1';
					o_lds_n <= '1';
					busmas_ack <= '1';
					if (busmas_req = '0') then
						busmas_ack <= '0';
						bus_mode <= "1000";
						bus_state <= BS_M_FIN;
					end if;
				when BS_M_FIN =>
					busmas_tick_pause <= '1';
					o_br_n <= '1';
					o_as_n <= '1';
					o_uds_n <= '1';
					o_lds_n <= '1';
					if (i_as_n_d = '0' or i_dtack_n = '0') then
						null;
					else
						o_bgack_n <= '1';
						bus_mode <= "0000";
						bus_state <= BS_IDLE;
					end if;

					-- other
				when others =>
					bus_mode <= "0000";
					o_dtack_n <= '1';
			end case;
		end if;
	end process;

	--
	-- KeplerX registers
	--

	-- $ECB000
	-- REG0: ID
	--   bit 15-8 : x"4b" (ascii code of 'K')
	--   bit  7-0 : x"58" (ascii code of 'X')
	--
	--   REG0に、0x0000 → 0xffff → 0x4b58 の順に書き込むと、永続化可能な設定値の一部がEEPROMに書き込まれます。
	--   書き込み実施中は IDが 0x6b78 (小文字の'k''x') に変化します。ポーリングする際は、「0x4b58を書く」→「読み出す」を
	--   繰り返してください（読み込みだけでは変化しません）。
	--   なお、EEPROMの公称書き換え回数は1000回ほどと言われている(データシートは見つけられなかったがそういう紹介記事あり)ため、
	--   レジスタ書き換えの都度ではなく、ユーザーが明示的に実行した時のみ行うようにしてください。
	--   EEPROMへの書き換え総数はREG55($ECB06E)で読み出せます。
	--
	-- $ECB002
	-- REG1: Serial Number (read only)
	--   bit 15-12 : board version major
	--      0 : 零號機
	--      1 : 壱號機
	--      2 : 弍號機
	--   bit 11- 0 : serial number
	--     シリアル番号の振り方:
	--     0-999     : 開発用
	--     1000-4095 : 頒布用
	--     シリアル番号は、ボードメジャーバージョン(壱號機、弍號機など)単位(このレジスタ単位)でユニークとする
	--
	-- $ECB004
	-- REG2: Firmware Version (read only)
	--   bit 15-12 : firm version major (0-15)
	--   bit 11- 8 : firm version minor (0-15)
	--   bit  7- 4 : firm version patch (0-15)
	--   bit     3 : firm version release / beta ('1': release, '0': beta)
	--   bit  2- 0 : board version minor (REG1のメジャーバージョンに続くマイナーバージョン)
	--
	-- $ECB006
	-- REG3: Expansion Memory Enable flags ('1': enable, '0': disable)
	--   bit 15    : insert wait ('1': insert wait, '0': no-wait) (default value = DE0Nano DipSw(2))
	--   bit 14-12 : reserved
	--   bit 11- 2 : ext mem block enable flags (if bit0 is '1' these will be overridden) (default value = '0')
	--      bit 11 is for 0xbxxxxx block
	--      bit 10 is for 0xaxxxxx block
	--      bit  2 is for 0x2xxxxx block
	--   bit  1    : ext mem block enable flag for 0x1xxxxx block (default value = DE0Nano DipSw(1) )
	--   bit  0    : ext mem auto detect flag for 0x2xxxxx - 0xbxxxxx blocks (default value = DE0Nano DipSw(0))
	--
	-- $ECB008
	-- REG4: Peripheral Enable flags ('1': enable, '0': disable)
	--   bit 15    : EEPROM ignored ('1': ignore, '0': restore setting from EEPROM) (read only, default value = DE0Nano DipSw(3) or Safe mode)
	--   bit 14    : EEPROM CRC error ('1': error was detected, '0': OK)
	--   bit 13-12 : Safe mode ("00": Normal, "01": Soft, "10": Hard) (read only)
	--   bit 11- 3 : reserved
	--   bit  2    : Mercury Unit (default value = '1')
	--   bit  1    : MIDI I/F (default value = '1')
	--   bit  0    : Expansion Memory (defaul value = '1')
	--
	-- $ECB00A
	-- REG5: Sound Volume Adjust 1 (every 4 bits: (+7〜-7)/8, -8 is mute)
	--   bit 15-12 : S/PDIF in
	--   bit 11- 8 : mt32-pi
	--   bit  7- 4 : YM2151
	--   bit  3- 0 : ADPCM
	--
	-- $ECB00C
	-- REG6: Sound Volume Adjust 2 (every 4 bits: (+7〜-7)/8, -8 is mute)
	--   bit 15-12 : Mercury Unit OPNA RHYTHM
	--   bit 11- 8 : Mercury Unit OPNA FM
	--   bit  7- 4 : Mercury Unit OPNA SSG
	--   bit  3- 0 : Mercury Unit PCM
	--
	-- $ECB00E
	-- REG7: Sound Mute ('1' is mute)
	--   bit 15- 8 : reserved
	--   bit  7 : S/PDIF in
	--   bit  6 : mt32-pi
	--   bit  5 : YM2151
	--   bit  4 : ADPCM
	--   bit  3 : Mercury Unit OPNA RHYTHM
	--   bit  2 : Mercury Unit OPNA FM
	--   bit  1 : Mercury Unit OPNA SSG
	--   bit  0 : Mercury Unit PCM
	--
	-- $ECB010
	-- REG8: Sound Input Status (read only)
	--   bit 15-12 : S/PDIF external input detect (0: None, 1: 32kHz, 2: 44.1kHz, 3: 48kHz, 4: 96kHz) ※ 48kHz以外はまだサポート外 
	--   bit 11- 8 : mt32-pi input detect  (0: None, 1: 32kHz, 2: 44.1kHz, 3: 48kHz, 4: 96kHz) ※ 48kHz以外はまだサポート外
	--   bit  7- 0 : reserved (all 0)
	--   bit  1    : PLL lock (44.1kHz)
	--   bit  0    : PLL lock (48kHz)
	--
	-- $ECB012
	-- REG9: MIDI Routing
	--   bit 3-2 : mt32-pi input source ("00": None, "01": MIDI I/F board, "10": Ext-In, "11": Reserved) (default value = "01")
	--   bit 1-0 : External out source  ("00": None, "01": MIDI I/F board, "10": Ext-In, "11": Reserved) (default value = "01")
	--
	-- $ECB014
	-- REG10: mt32-pi control
	--   [WRITE]
	--      bit 15-12 : reserved
	--      bit 11- 8 : command (see https://github.com/dwhinham/mt32-pi/wiki/Custom-System-Exclusive-messages)
	--      bit  7- 0 : param
	--   [READ]
	--      bit 15    : busy
	--      bit 14- 0 : reserved
	--
	-- $ECB018
	-- REG12: System Clock Freq (kHz) (read only)
	--
	-- $ECB01A
	-- REG13: H Sync Freq (Hz) (read only)
	--
	-- $ECB01C
	-- REG14: V Sync Freq (0.1Hz) (read only)
	--
	-- $ECB01E
	-- REG15: AREA set register cache (for $e86000) (read only)
	--   
	-- $ECB06E
	-- REG55: EEPROM write counter (read only)
	--   bit 15- 0 : Number of EEPROM write (read only)
	--
	-- $ECB070-$ECB07F
	-- REG56-REG63: CRC value for EEPROM (read only)
	--   この領域にCRCの生の値が見えていますが、CRCエラーがあるかどうかは、REG4のbit14で判定してください
	--
	process (sys_clk, sys_rstn)
		variable reg_num : integer range 0 to keplerx_reg_count - 1;
		variable reg_num_b7 : integer range 0 to 127;
	begin
		if (sys_rstn = '0') then
			keplerx_ack <= '0';
			areaset_ack <= '0';
			keplerx_reg_state <= KXR_IDLE;
			keplerx_reg(0) <= x"0000";
			keplerx_reg(1) <= (others => '0'); -- board version, serial number
			keplerx_reg(2) <= firm_version_major & firm_version_minor & firm_version_patch & firm_version_release & "000"; -- firm version
			if (safe_mode_level = "00") then
				-- normal mode
				keplerx_reg(3) <= pSW(2) & "000" & "0000000000" & pSw(1) & pSw(0);
				keplerx_reg(4) <= pSW(3) & "0" & safe_mode_level & "0000" & "00000111";
			elsif (safe_mode_level = "01") then
				-- safe mode (soft)
				keplerx_reg(3) <= "1" & "000" & "0000000000" & pSw(1) & pSw(0); -- mem 1-clk wait
				keplerx_reg(4) <= "1" & "0" & safe_mode_level & "0000" & "00000111"; -- EEPROM ignored
			else
				-- safe mode (hard)
				keplerx_reg(3) <= "1" & "000" & "0000000000" & "0" & "0"; -- mem 1-clk wait, disable 1m-2m block, disable autodetect
				keplerx_reg(4) <= "1" & "0" & safe_mode_level & "0000" & "00000000"; -- EEPROM ignored
			end if;
			keplerx_reg(5) <= x"0000";
			keplerx_reg(6) <= x"000C";
			keplerx_reg(7) <= x"8000";
			keplerx_reg(8) <= (others => '0');
			keplerx_reg(9) <= x"0005"; -- midi routing
			keplerx_reg(10) <= (others => '0');
			keplerx_reg(11) <= (others => '0');
			keplerx_reg(12) <= (others => '0');
			keplerx_reg(13) <= (others => '0');
			keplerx_reg(14) <= (others => '0');
			keplerx_reg(15) <= (others => '1');
			keplerx_reg_update_ack <= (others => '0');
			--
			khz_counter <= sysclk_freq - 1;
			hz_counter <= 999;
			tensec_counter <= 9;
			--
			x68_sysclk_counter <= 0;
			x68_hsync_counter <= 0;
			x68_vsync_counter <= 0;
			--
			gpeeprom_save_req <= '0';
			gpeeprom_we <= '0';
			gpeeprom_ready_d <= '0';
			gpeeprom_restore_counter <= (others => '0');
			gpeeprom_restore_state <= (others => '0');
			--
			midi_all_notes_off_req_finished <= '0';
		elsif (sys_clk'event and sys_clk = '1') then
			gpeeprom_ready_d <= gpeeprom_ready;
			gpeeprom_we <= '0';
			keplerx_reg(4)(14) <= gpeeprom_crc_error;
			-- EEPROMからCRCエラー無く設定が読み出せたら、EEPROMの内容をレジスタに復元する
			if (gpeeprom_restore_counter = 0 and gpeeprom_ready = '1') then
				if (gpeeprom_crc_error = '0' and keplerx_reg(4)(15) = '0') then
					gpeeprom_restore_counter <= "0000001";
				else
					-- エラーもしくは Safe-mode時は、EEPROMの内容を読み出さない
					gpeeprom_restore_counter <= "1111111";
				end if;
			elsif (gpeeprom_restore_counter = "1111111") then
				-- 復元完了
				null;
			else
				-- 復元ループ
				case gpeeprom_restore_state is
					when "000" =>
						gpeeprom_addr <= gpeeprom_restore_counter & "0";
						gpeeprom_restore_state <= "001";
					when "001" =>
						gpeeprom_addr <= gpeeprom_restore_counter & "1";
						gpeeprom_restore_state <= "010";
					when "010" =>
						gpeeprom_restore_state <= "011";
					when "011" =>
						gpeeprom_data_word(15 downto 8) <= gpeeprom_data_out;
						gpeeprom_restore_state <= "100";
					when "100" =>
						gpeeprom_data_word(7 downto 0) <= gpeeprom_data_out;
						gpeeprom_restore_state <= "101";
					when "101" =>
						reg_num_b7 := conv_integer(gpeeprom_restore_counter);
						case reg_num_b7 is
							when 4 | 5 | 6 | 7 | 9 =>
								keplerx_reg(reg_num_b7) <= gpeeprom_data_word;
							when 121 => -- 0xf2, 0xf3  board version major & serial number
								keplerx_reg(1) <= gpeeprom_data_word;
							when 122 => -- 0xf4, 0xf5  board version minor
								keplerx_reg(2)(2 downto 0) <= gpeeprom_data_word(2 downto 0);
							when others =>
								null;
						end case;
						gpeeprom_restore_counter <= gpeeprom_restore_counter + 1;
						gpeeprom_restore_state <= "000";
					when others =>
						gpeeprom_restore_state <= "000";
				end case;
			end if;

			if (gpeeprom_restore_counter = "1111111") then
				-- 復元ステップを終えたら以下の処理を実施
				if (midi_all_notes_off_req_finished = '0') then
					-- MIDIのルーティングが復元された後に　MIDI の All Notes Offを要求
					-- (現状は全ポートに出力しているが、将来のため)
					midi_all_notes_off_req <= '1';
					if (midi_all_notes_off_ack = '1') then
						midi_all_notes_off_req <= '0';
						midi_all_notes_off_req_finished <= '1';
					end if;
				end if;
			end if;

			if (mt32pi_ack = '1') then
				mt32pi_req <= '0';
			end if;
			if keplerx_req = '1' and keplerx_ack = '0' then
				reg_num := conv_integer(sys_addr(4 downto 1));
				if sys_rw = '0' then
					-- write
					case keplerx_reg_state is
						when KXR_IDLE =>
							case sys_addr(8 downto 5) is
								when "0000" =>
									case reg_num is
										when 0 => -- special func
											keplerx_reg_state <= KXR_REG0;
										when 1 => -- read only
										when 2 => -- read only
										when 8 => -- read only
										when 11 => -- read only
										when 12 => -- read only
										when 13 => -- read only
										when 14 => -- read only
										when 15 => -- read only
											keplerx_reg_state <= KXR_ACK;
										when others => -- writable registers
											if i_uds_n_d = '0' then
												keplerx_reg(reg_num)(15 downto 8) <= sys_idata(15 downto 8);
											end if;
											if i_lds_n_d = '0' then
												keplerx_reg(reg_num)(7 downto 0) <= sys_idata(7 downto 0);
											end if;
											-- write back to EEPROM
											keplerx_reg_state <= KXR_EEPROM_WR_U0;
									end case;
									if reg_num = 10 then
										mt32pi_req <= '1';
									end if;
								when others =>
									-- 他の領域は read only
									keplerx_reg_state <= KXR_ACK;
							end case;
						when KXR_REG0 => -- REG0 の特殊操作
							case keplerx_reg(0)(1 downto 0) is
								when "00" =>
									if (sys_idata = x"0000") then
										keplerx_reg(0)(1 downto 0) <= "01";
									else
										keplerx_reg(0) <= (others => '0');
									end if;
								when "01" =>
									if (sys_idata = x"0000") then
										keplerx_reg(0)(1 downto 0) <= "01";
									elsif (sys_idata = x"ffff") then
										keplerx_reg(0)(1 downto 0) <= "10";
									end if;
								when "10" =>
									if (sys_idata = x"0000") then
										keplerx_reg(0)(1 downto 0) <= "01";
									elsif (sys_idata = x"4b58") then
										keplerx_reg(0)(1 downto 0) <= "11";
										gpeeprom_save_req <= '1'; -- Request the EEPROM to save
									else
										keplerx_reg(0) <= (others => '0');
									end if;
								when "11" =>
									if (gpeeprom_save_ack = '1') then -- Waiting ack from the EEPROM
										gpeeprom_save_req <= '0';
										keplerx_reg(0) <= (others => '0');
									end if;
								when others =>
									null;
							end case;
							keplerx_reg_state <= KXR_ACK;

						when KXR_EEPROM_WR_U0 =>
							gpeeprom_addr <= sys_addr(7 downto 1) & "0";
							gpeeprom_data_in <= sys_idata(15 downto 8);
							if (i_uds_n_d = '0') then
								gpeeprom_we <= '1';
							end if;
							keplerx_reg_state <= KXR_EEPROM_WR_U1;
						when KXR_EEPROM_WR_U1 =>
							keplerx_reg_state <= KXR_EEPROM_WR_L0;
						when KXR_EEPROM_WR_L0 =>
							gpeeprom_addr <= sys_addr(7 downto 1) & "1";
							gpeeprom_data_in <= sys_idata(7 downto 0);
							if (i_lds_n_d = '0') then
								gpeeprom_we <= '1';
							end if;
							keplerx_reg_state <= KXR_EEPROM_WR_L1;
						when KXR_EEPROM_WR_L1 =>
							keplerx_reg_state <= KXR_ACK;

						when KXR_ACK =>
							keplerx_ack <= '1';
							keplerx_reg_state <= KXR_IDLE;
						when others =>
							keplerx_reg_state <= KXR_IDLE;
					end case;
				else
					-- read
					case keplerx_reg_state is
						when KXR_IDLE =>
							case sys_addr(8 downto 5) is
								when "0000" =>
									case reg_num is
										when 0 => -- 
											case keplerx_reg(0)(1 downto 0) is
												when "00" =>
													keplerx_odata <= x"4b58"; -- "KX"
												when "01" =>
													keplerx_odata <= x"4b58"; -- "KX"
												when "10" =>
													keplerx_odata <= x"4b58"; -- "KX"
												when "11" =>
													keplerx_odata <= x"6b78"; -- "kx"
												when others =>
													null;
											end case;
										when others =>
											keplerx_odata <= keplerx_reg(conv_integer(sys_addr(4 downto 1)));
									end case;
									keplerx_reg_state <= KXR_ACK;
								when others =>
									-- 他の領域はEEPROMの中身をミラーする
									keplerx_reg_state <= KXR_EEPROM_RD_AU;
							end case;
						when KXR_EEPROM_RD_AU =>
							gpeeprom_addr <= sys_addr(7 downto 1) & "0";
							keplerx_reg_state <= KXR_EEPROM_RD_AL;
						when KXR_EEPROM_RD_AL =>
							gpeeprom_addr <= sys_addr(7 downto 1) & "1";
							keplerx_reg_state <= KXR_EEPROM_RD_WAIT;
						when KXR_EEPROM_RD_WAIT =>
							keplerx_reg_state <= KXR_EEPROM_RD_DU;
						when KXR_EEPROM_RD_DU =>
							keplerx_odata(15 downto 8) <= gpeeprom_data_out;
							keplerx_reg_state <= KXR_EEPROM_RD_DL;
						when KXR_EEPROM_RD_DL =>
							keplerx_odata(7 downto 0) <= gpeeprom_data_out;
							keplerx_reg_state <= KXR_ACK;

						when KXR_ACK =>
							keplerx_ack <= '1';
							keplerx_reg_state <= KXR_IDLE;
						when others =>
							keplerx_reg_state <= KXR_IDLE;
					end case;
				end if;
			elsif keplerx_req = '0' and keplerx_ack = '1' then
				keplerx_ack <= '0';
			else
				if (keplerx_reg_update_req(3) /= keplerx_reg_update_ack(3)) then
					keplerx_reg_update_ack(3) <= not keplerx_reg_update_ack(3);
					keplerx_reg(3)(11 downto 2) <= exmem_enabled(11 downto 2);
				end if;
			end if;
			if areaset_req = '1' and areaset_ack = '0' then
				if sys_rw = '0' then
					if i_uds_n_d = '0' then
						keplerx_reg(15)(15 downto 8) <= sys_idata(15 downto 8);
					end if;
					if i_lds_n_d = '0' then
						keplerx_reg(15)(7 downto 0) <= sys_idata(7 downto 0);
					end if;
				end if;
				areaset_ack <= '1';
			elsif areaset_req = '0' and areaset_ack = '1' then
				areaset_ack <= '0';
			end if;

			--
			-- status update
			--
			-- REG8: Sound Input Status (read only)
			--   bit 15-12 : S/PDIF external input detect (0: None, 1: 32kHz, 2: 44.1kHz, 3: 48kHz, 4: 96kHz) ※ 48kHz以外はまだサポート外 
			--   bit 11- 8 : mt32-pi input detect  (0: None, 1: 32kHz, 2: 44.1kHz, 3: 48kHz, 4: 96kHz) ※ 48kHz以外はまだサポート外
			if (i2s_dtct = '0') then
				keplerx_reg(8)(15 downto 12) <= "0000";
			else
				keplerx_reg(8)(15 downto 12) <= "0011"; -- TODO 他の周波数に対応
			end if;
			if (i2s_dtct_pi = '0') then
				keplerx_reg(8)(11 downto 8) <= "0000";
			else
				keplerx_reg(8)(11 downto 8) <= "0011"; -- TODO 他の周波数に対応
			end if;
			keplerx_reg(8)(1) <= plllock_pcm44k1;
			keplerx_reg(8)(0) <= plllock_pcm48k;

			keplerx_reg(10)(15) <= mt32pi_odata(15);

			--
			-- frequency detector
			-- 
			x68_clk10m_d <= x68clk10m;
			x68_clk10m_dd <= x68_clk10m_d;
			x68_hsync_d <= pGPIO1(1);
			x68_hsync_dd <= x68_hsync_d;
			x68_vsync_d <= pGPIO1(0);
			x68_vsync_dd <= x68_vsync_d;
			if (khz_counter = 0) then
				khz_counter <= sysclk_freq - 1;
				keplerx_reg(12) <= conv_std_logic_vector(x68_sysclk_counter, 16);
				x68_sysclk_counter <= 0;
				if (hz_counter = 0) then
					hz_counter <= 999;
					keplerx_reg(13) <= conv_std_logic_vector(x68_hsync_counter, 16);
					x68_hsync_counter <= 0;
					if (tensec_counter = 0) then
						tensec_counter <= 9;
						keplerx_reg(14) <= conv_std_logic_vector(x68_vsync_counter, 16);
						x68_vsync_counter <= 0;
					else
						tensec_counter <= tensec_counter - 1;
					end if;
				else
					hz_counter <= hz_counter - 1;
				end if;
			else
				khz_counter <= khz_counter - 1;
				if (x68_clk10m_dd = '0' and x68_clk10m_d = '1') then
					x68_sysclk_counter <= x68_sysclk_counter + 1;
				end if;
				if (x68_hsync_dd = '1' and x68_hsync_d = '0') then
					x68_hsync_counter <= x68_hsync_counter + 1;
				end if;
				if (x68_vsync_dd = '1' and x68_vsync_d = '0') then
					x68_vsync_counter <= x68_vsync_counter + 1;
				end if;
			end if;
		end if;
	end process;

	--
	-- PPI
	--
	PPI1 : e8255 port map(
		sys_clk => sys_clk,
		sys_rstn => sys_rstn,
		req => ppi1_req,
		ack => ppi1_ack,

		rw => sys_rw,
		addr => sys_addr(2 downto 1),
		idata => ppi1_idata,
		odata => open,

		PAi => ppi1_pai,
		PAo => ppi1_pao,
		PAoe => ppi1_paoe,
		PBi => ppi1_pbi,
		PBo => ppi1_pbo,
		PBoe => ppi1_pboe,
		PCHi => ppi1_pchi,
		PCHo => ppi1_pcho,
		PCHoe => ppi1_pchoe,
		PCLi => ppi1_pcli,
		PCLo => ppi1_pclo,
		PCLoe => ppi1_pcloe
	);

	ppi1_idata <= sys_idata(7 downto 0);

	ppi1_pai <= (others => '1');
	ppi1_pchi <= (others => '1');

	ppi1_pbi <= (others => '1');
	ppi1_pcli <= (others => '1');

	adpcm_clkdiv <= ppi1_pclo(3 downto 2);
	adpcm_enL <= not ppi1_pclo(0);
	adpcm_enR <= not ppi1_pclo(1);

	-- for JMMCSCSI
	PPI2 : e8255 port map(
		sys_clk => sys_clk,
		sys_rstn => sys_rstn,
		req => ppi2_req,
		ack => ppi2_ack,

		rw => sys_rw,
		addr => sys_addr(2 downto 1),
		idata => ppi2_idata,
		odata => ppi2_odata,

		PAi => ppi2_pai,
		PAo => ppi2_pao,
		PAoe => ppi2_paoe,
		PBi => ppi2_pbi,
		PBo => ppi2_pbo,
		PBoe => ppi2_pboe,
		PCHi => ppi2_pchi,
		PCHo => ppi2_pcho,
		PCHoe => ppi2_pchoe,
		PCLi => ppi2_pcli,
		PCLo => ppi2_pclo,
		PCLoe => ppi2_pcloe
	);

	ppi2_idata <= sys_idata(7 downto 0);

	--ppi1_pai<='1' & pJoyA(5 downto 4) & '1' & pJoyA(3 downto 0);
	--pStrA<=ppi1_pcho(0) when ppi1_pchoe='1' else 'Z';
	--pJoyA(4)<='Z' when ppi1_pcho(2)='0' else '0';
	--pJoyA(5)<='Z' when ppi1_pcho(3)='0' else '0';

	pGPIO1(25) <= 'Z' when ppi2_paoe = '0' else ppi2_pao(0); -- JoyA 1番ピン相当 - JMMCSCSIのCS
	pGPIO1(22) <= 'Z' when ppi2_paoe = '0' else ppi2_pao(1); -- JoyA 2番ピン相当 - JMMCSCSIのSCLK
	pGPIO1(23) <= 'Z' when ppi2_paoe = '0' else ppi2_pao(2); -- JoyA 3番ピン相当　- JMMCSCSIのMOSI
	pGPIO1(24) <= 'Z' when ppi2_pchoe = '0' else ppi2_pcho(0); -- JoyA 8番ピン相当 - JMMCSCSIのMISO
	--pGPIO2(12) <=
	--'0' when ppi2_paoe = '0' else
	--'1' when ppi2_pao(3) = '1' else
	--sys_counter_100m(22);-- JoyA 4番ピン相当 - JMMCSCSIのLED

	ppi2_pai <= "11111" & pGPIO1(23) & pGPIO1(22) & pGPIO1(25);
	ppi2_pchi <= "111" & pGPIO1(24);

	ppi2_pbi <= (others => '1');
	ppi2_pcli <= "1111";

	-- for osciloscope trigger
	--pGPIO2(11) <= exmem_req;

	--
	-- Sound
	--
	GEN_IKAOPM : if (YM2151_MODULE = "IKAOPM") generate
		OPM : OPM_IKAOPM port map(
			sys_clk => sys_clk,
			sys_rstn => sys_rstn,
			req => opm_req,
			ack => opm_ack,

			rw => sys_rw,
			addr => sys_addr(1),
			idata => opm_idata,
			odata => opm_odata,

			irqn => open,

			-- specific i/o
			snd_clk => snd_clk,
			pcmL => opm_pcmLi,
			pcmR => opm_pcmRi,

			CT1 => adpcm_clkmode,
			CT2 => open
		);
	end generate GEN_IKAOPM;

	GEN_JT51 : if (YM2151_MODULE = "JT51__") generate
		OPM : OPM_JT51 port map(
			sys_clk => sys_clk,
			sys_rstn => sys_rstn,
			req => opm_req,
			ack => opm_ack,

			rw => sys_rw,
			addr => sys_addr(1),
			idata => opm_idata,
			odata => opm_odata,

			irqn => open,

			-- specific i/o
			snd_clk => snd_clk,
			pcmL => opm_pcmLi,
			pcmR => opm_pcmRi,

			CT1 => adpcm_clkmode,
			CT2 => open
		);
	end generate GEN_JT51;

	opm_idata <= sys_idata(7 downto 0);

	opm_pcmL <= opm_pcmLi(15) & opm_pcmLi(15) & opm_pcmLi(15 downto 2);
	opm_pcmR <= opm_pcmRi(15) & opm_pcmRi(15) & opm_pcmRi(15 downto 2);

	-- to real YM2151
	GEN_REAL_YM2151_0 : if (ENABLE_REAL_YM2151 = 0) generate
		opm_YM2151_pcmLi <= (others => '0');
		opm_YM2151_pcmRi <= (others => '0');
		pGPIO2(0) <= 'Z';
		pGPIO2(8 downto 1) <= (others => 'Z');
		pGPIO2(9) <= 'Z';
		pGPIO2(10) <= 'Z';
		pGPIO2(11) <= 'Z';
		pGPIO2(12) <= 'Z';
	end generate GEN_REAL_YM2151_0;

	GEN_REAL_YM2151_1 : if (ENABLE_REAL_YM2151 = 1) generate
		OPM_YM2151_0 : OPM_YM2151 port map(
			sys_clk => sys_clk,
			sys_rstn => sys_rstn,
			req => opm_req,
			ack => open, -- ignore

			rw => sys_rw,
			addr => sys_addr(1),
			idata => opm_idata,
			odata => open,

			irqn => open,

			-- specific i/o
			snd_clk => snd_clk,
			pcmL => opm_YM2151_pcmLi,
			pcmR => opm_YM2151_pcmRi,

			CT1 => open,
			CT2 => open,

			-- external connection
			OPM_IC_n => opm_OPM_IC_n,
			OPM_PHYM => opm_OPM_PHYM,
			OPM_PHY1 => opm_OPM_PHY1,
			OPM_WR_n => opm_OPM_WR_n,
			OPM_A0 => opm_OPM_A0,
			OPM_DATA => opm_OPM_DATA,
			OPM_SH1 => opm_OPM_SH1,
			OPM_SH2 => opm_OPM_SH2,
			OPM_SDATA => opm_OPM_SDATA
		);

		opm_OPM_PHY1 <= pGPIO2_IN(0);
		opm_OPM_SDATA <= pGPIO2_IN(1);
		opm_OPM_SH2 <= pGPIO2_IN(2);
		opm_OPM_SH1 <= pGPIO2(0);
		pGPIO2(0) <= 'Z';
		pGPIO2(8 downto 1) <= opm_OPM_DATA;
		pGPIO2(9) <= opm_OPM_WR_n;
		pGPIO2(10) <= opm_OPM_A0;
		pGPIO2(11) <= opm_OPM_IC_n;
		pGPIO2(12) <= opm_OPM_PHYM;
	end generate GEN_REAL_YM2151_1;

	opm_YM2151_pcmL <= opm_YM2151_pcmLi(15) & opm_YM2151_pcmLi(15) & opm_YM2151_pcmLi(15 downto 2);
	opm_YM2151_pcmR <= opm_YM2151_pcmRi(15) & opm_YM2151_pcmRi(15) & opm_YM2151_pcmRi(15 downto 2);

	-- ADPCM
	adpcm : e6258 port map(
		sys_clk => sys_clk,
		sys_rstn => sys_rstn,
		req => adpcm_req,
		ack => adpcm_ack,

		rw => sys_rw,
		addr => sys_addr(1),
		idata => adpcm_idata,
		odata => open,

		drq => open,

		-- specific i/o
		clkdiv => adpcm_clkdiv,
		sft => adpcm_sft,
		adpcm_datemp => adpcm_datemp,
		adpcm_datover => adpcm_datover,

		snd_clk => snd_clk,
		pcm => adpcm_pcmRaw
	);

	adpcm_idata <= sys_idata(7 downto 0);

	adpcm_pcmL <= (adpcm_pcmRaw(11) & adpcm_pcmRaw & "000") when adpcm_enL = '1' else (others => '0');
	adpcm_pcmR <= (adpcm_pcmRaw(11) & adpcm_pcmRaw & "000") when adpcm_enR = '1' else (others => '0');

	-- 16MHzの snd_clkから、ADPCMの 4MHz / 8MHzのタイミングを作るカウンタ
	process (snd_clk, sys_rstn)begin
		if (sys_rstn = '0') then
			adpcm_clkdiv_count <= 0;
			adpcm_sft <= '0';
		elsif (snd_clk'event and snd_clk = '1') then
			adpcm_sft <= '0';
			if (adpcm_clkdiv_count = 0) then
				adpcm_sft <= '1';
				if (adpcm_clkmode = '1') then
					adpcm_clkdiv_count <= 3; -- 4MHz
				else
					adpcm_clkdiv_count <= 1; -- 8MHz
				end if;
			else
				adpcm_clkdiv_count <= adpcm_clkdiv_count - 1;
			end if;
		end if;
	end process;

	--
	-- I2S sound in
	--
	I2S_dec_spdif : i2s_decoder port map(
		snd_clk => snd_clk,

		i2s_data => i2s_data_in, -- I2S DATA
		i2s_lrck => i2s_lrck, -- I2S LRCK
		i2s_bclk => i2s_bclk,

		detected => i2s_dtct,

		snd_pcmL => i2s_pcmL_spdif,
		snd_pcmR => i2s_pcmR_spdif,

		rstn => sys_rstn
	);
	I2S_dec_pi : i2s_decoder port map(
		snd_clk => snd_clk,

		i2s_data => i2s_data_pi, -- I2S DATA
		i2s_lrck => i2s_lrck_pi, -- I2S LRCK
		i2s_bclk => i2s_bclk_pi,

		detected => i2s_dtct_pi,

		snd_pcmL => i2s_pcmL_pi,
		snd_pcmR => i2s_pcmR_pi,

		rstn => sys_rstn
	);

	i2s_data_pi <= pGPIO1(30); -- RasPi GPIO21
	i2s_lrck_pi <= pGPIO1(28); -- RasPi GPIO19
	i2s_bclk_pi <= pGPIO1(29); -- RasPi GPIO18
	spdifin_pcmL <= i2s_pcmL_spdif(30 downto 15); -- 1 bit delayed
	spdifin_pcmR <= i2s_pcmR_spdif(30 downto 15); -- 1 bit delayed
	raspi_pcmL <= i2s_pcmL_pi(31 downto 16);
	raspi_pcmR <= i2s_pcmR_pi(31 downto 16);

	--
	-- I2S sound out
	--
	mixL : addsat_16 generic map(16)
	port map(
		snd_clk, sys_rstn,

		spdifin_pcmL, keplerx_reg(5)(15 downto 12), keplerx_reg(7)(7),
		raspi_pcmL, keplerx_reg(5)(11 downto 8), keplerx_reg(7)(6),
		opm_pcmL, keplerx_reg(5)(7 downto 4), keplerx_reg(7)(5),
		adpcm_pcmL, keplerx_reg(5)(3 downto 0), keplerx_reg(7)(4),
		mercury_pcm_pcmL, keplerx_reg(6)(3 downto 0), keplerx_reg(7)(0),
		mercury_pcm_ssg0, keplerx_reg(6)(7 downto 4), keplerx_reg(7)(1),
		mercury_pcm_fmL0, keplerx_reg(6)(11 downto 8), keplerx_reg(7)(2),
		mercury_pcm_rhythmL0, keplerx_reg(6)(15 downto 12), keplerx_reg(7)(3),
		mercury_pcm_ssg1, keplerx_reg(6)(7 downto 4), keplerx_reg(7)(1),
		mercury_pcm_fmL1, keplerx_reg(6)(11 downto 8), keplerx_reg(7)(2),
		mercury_pcm_rhythmL1, keplerx_reg(6)(15 downto 12), keplerx_reg(7)(3),
		opm_YM2151_pcmL, keplerx_reg(5)(7 downto 4), keplerx_reg(7)(15),
		(others => '0'), x"0", '0',
		(others => '0'), x"0", '0',
		(others => '0'), x"0", '0',
		(others => '0'), x"0", '0',
		snd_pcmL
	);

	mixR : addsat_16 generic map(16)
	port map(
		snd_clk, sys_rstn,

		spdifin_pcmR, keplerx_reg(5)(15 downto 12), keplerx_reg(7)(7),
		raspi_pcmR, keplerx_reg(5)(11 downto 8), keplerx_reg(7)(6),
		opm_pcmR, keplerx_reg(5)(7 downto 4), keplerx_reg(7)(5),
		adpcm_pcmR, keplerx_reg(5)(3 downto 0), keplerx_reg(7)(4),
		mercury_pcm_pcmR, keplerx_reg(6)(3 downto 0), keplerx_reg(7)(0),
		mercury_pcm_ssg0, keplerx_reg(6)(7 downto 4), keplerx_reg(7)(1),
		mercury_pcm_fmR0, keplerx_reg(6)(11 downto 8), keplerx_reg(7)(2),
		mercury_pcm_rhythmR0, keplerx_reg(6)(15 downto 12), keplerx_reg(7)(3),
		mercury_pcm_ssg1, keplerx_reg(6)(7 downto 4), keplerx_reg(7)(1),
		mercury_pcm_fmR1, keplerx_reg(6)(11 downto 8), keplerx_reg(7)(2),
		mercury_pcm_rhythmR1, keplerx_reg(6)(15 downto 12), keplerx_reg(7)(3),
		opm_YM2151_pcmR, keplerx_reg(5)(7 downto 4), keplerx_reg(7)(15),
		(others => '0'), x"0", '0',
		(others => '0'), x"0", '0',
		(others => '0'), x"0", '0',
		(others => '0'), x"0", '0',
		snd_pcmR
	);

	--pGPIO0(19) <= i2s_bclk; -- I2S BCK
	I2S_enc : i2s_encoder port map(
		snd_clk => snd_clk,
		snd_pcmL => i2s_sndL,
		snd_pcmR => i2s_sndR,

		i2s_data => i2s_data_out, -- I2S DATA
		i2s_lrck => i2s_lrck, -- I2S LRCK

		i2s_bclk => i2s_bclk,
		bclk_pcmL => bclk_pcmL,
		bclk_pcmR => bclk_pcmR,

		rstn => sys_rstn
	);

	pClk24M576 <= pGPIO1_in(1);
	i2s_mclk <= pcm_clk_24M576; -- PLL clock
	pGPIO0(16) <= i2s_mclk; -- I2S MCLK
	pGPIO0(17) <= i2s_data_out;
	pGPIO0(18) <= i2s_lrck;
	pGPIO0(19) <= i2s_bclk; -- I2S BCLK
	pGPIO0(20) <= 'Z';
	i2s_data_in <= pGPIO0(20);
	i2s_sndL(31 downto 16) <= snd_pcmL;
	i2s_sndR(31 downto 16) <= snd_pcmR;
	i2s_sndL(15 downto 0) <= (others => '0');
	i2s_sndR(15 downto 0) <= (others => '0');

	--
	-- I2C Interface
	--
	I2C : I2CIF port map(
		DATIN => I2C_TXDAT,
		DATOUT => I2C_RXDAT,
		WRn => I2C_WRn,
		RDn => I2C_RDn,

		TXEMP => I2C_TXEMP,
		RXED => I2C_RXED,
		NOACK => I2C_NOACK,
		COLL => I2C_COLL,
		NX_READ => I2C_NX_READ,
		RESTART => I2C_RESTART,
		START => I2C_START,
		FINISH => I2C_FINISH,
		F_FINISH => I2C_F_FINISH,
		INIT => I2C_INIT,
		SDAIN => SDAIN,
		SDAOUT => SDAOUT,
		SCLIN => SCLIN,
		SCLOUT => SCLOUT,

		SFT => I2CCLKEN,
		clk => sys_clk,
		rstn => ini_rstn -- 電源投入時に一度だけリセットする
	);
	pGPIO0_04 <= '0' when SCLOUT = '0' else 'Z';
	pGPIO0_09 <= '0' when SDAOUT = '0' else 'Z';

	process (sys_clk, ini_rstn) begin
		if (ini_rstn = '0') then
			SCLIN <= '1';
			SDAIN <= '1';
		elsif (sys_clk'event and sys_clk = '1') then
			SCLIN <= pGPIO0_04;
			SDAIN <= pGPIO0_09;
		end if;
	end process;

	I2CMUX : I2C_MUX generic map(
		NUM_DRIVERS => NUM_DRIVERS) port map(
		-- I2C
		TXOUT => I2C_TXDAT,
		RXIN => I2C_RXDAT,
		WRn => I2C_WRn,
		RDn => I2C_RDn,

		TXEMP => I2C_TXEMP,
		RXED => I2C_RXED,
		NOACK => I2C_NOACK,
		COLL => I2C_COLL,
		NX_READ => I2C_NX_READ,
		RESTART => I2C_RESTART,
		START => I2C_START,
		FINISH => I2C_FINISH,
		F_FINISH => I2C_F_FINISH,
		INIT => I2C_INIT,

		-- for Driver
		DATIN_PXY => I2C_TXDAT_PXY,
		DATOUT_PXY => I2C_RXDAT_PXY,
		WRn_PXY => I2C_WRn_PXY,
		RDn_PXY => I2C_RDn_PXY,

		TXEMP_PXY => I2C_TXEMP_PXY,
		RXED_PXY => I2C_RXED_PXY,
		NOACK_PXY => I2C_NOACK_PXY,
		COLL_PXY => I2C_COLL_PXY,
		NX_READ_PXY => I2C_NX_READ_PXY,
		RESTART_PXY => I2C_RESTART_PXY,
		START_PXY => I2C_START_PXY,
		FINISH_PXY => I2C_FINISH_PXY,
		F_FINISH_PXY => I2C_F_FINISH_PXY,
		INIT_PXY => I2C_INIT_PXY,

		clk => sys_clk,
		rstn => ini_rstn -- 電源投入時に一度だけリセットする
	);

	I2CCLK : sftclk
	generic map(sysclk_freq, 800, 1)
	port map(
		SEL => "0",
		SFT => I2CCLKEN,
		CLK => sys_clk,
		RSTN => ini_rstn -- 電源投入時に一度だけリセットする
	);

	greenpak_inst : GreenPAK_EEPROM port map(
		-- Host interface
		addr => gpeeprom_addr,
		data_in => gpeeprom_data_in,
		data_out => gpeeprom_data_out,
		we => gpeeprom_we,

		ready => gpeeprom_ready,
		crc_error => gpeeprom_crc_error,

		save_req => gpeeprom_save_req,
		save_ack => gpeeprom_save_ack,

		-- I2C interface
		TXOUT => I2C_TXDAT_PXY(0),
		RXIN => I2C_RXDAT_PXY(0),
		WRn => I2C_WRn_PXY(0),
		RDn => I2C_RDn_PXY(0),

		TXEMP => I2C_TXEMP_PXY(0),
		RXED => I2C_RXED_PXY(0),
		NOACK => I2C_NOACK_PXY(0),
		COLL => I2C_COLL_PXY(0),
		NX_READ => I2C_NX_READ_PXY(0),
		RESTART => I2C_RESTART_PXY(0),
		START => I2C_START_PXY(0),
		FINISH => I2C_FINISH_PXY(0),
		F_FINISH => I2C_F_FINISH_PXY(0),
		INIT => I2C_INIT_PXY(0),

		clk => sys_clk,
		rstn => ini_rstn -- 電源投入時に一度だけリセットする
	);

	wm8804_inst : wm8804 port map(
		TXOUT => I2C_TXDAT_PXY(1),
		RXIN => I2C_RXDAT_PXY(1),
		WRn => I2C_WRn_PXY(1),
		RDn => I2C_RDn_PXY(1),

		TXEMP => I2C_TXEMP_PXY(1),
		RXED => I2C_RXED_PXY(1),
		NOACK => I2C_NOACK_PXY(1),
		COLL => I2C_COLL_PXY(1),
		NX_READ => I2C_NX_READ_PXY(1),
		RESTART => I2C_RESTART_PXY(1),
		START => I2C_START_PXY(1),
		FINISH => I2C_FINISH_PXY(1),
		F_FINISH => I2C_F_FINISH_PXY(1),
		INIT => I2C_INIT_PXY(1),

		clk => sys_clk,
		rstn => wm8804_rstn
	);
	wm8804_rstn <= sys_rstn;
	pGPIO1(26) <= 'Z'; -- WM8804 INT

	--
	-- HDMI
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
		clk_audio => hdmi_pcmclk,
		reset => hdmi_rst,
		rgb => hdmi_rgb,
		audio_sample_word => hdmi_pcm,

		tmds => hdmi_tmds,
		tmds_clock => hdmi_tmdsclk,

		cx => hdmi_cx,
		cy => hdmi_cy,

		frame_width => open,
		frame_height => open,
		screen_width => open,
		screen_height => open
	);

	hdmi_rst <= not sys_rstn;

	pGPIO0_HDMI_CLK <= hdmi_tmdsclk;
	pGPIO0_HDMI_DATA0 <= hdmi_tmds(0);
	pGPIO0_HDMI_DATA1 <= hdmi_tmds(1);
	pGPIO0_HDMI_DATA2 <= hdmi_tmds(2);

	hdmi_rgb <= console_rgb when hdmi_cy(9 downto 7) = "000" else
		hdmi_r & hdmi_g & hdmi_b;
	hdmi_pcmclk <= i2s_lrck;
	hdmi_pcm(0) <= bclk_pcmL(31 downto 16);
	hdmi_pcm(1) <= bclk_pcmR(31 downto 16);

	hdmi_adpcm_datemp <=
		'1' when ((adpcm_pcmRaw(11 downto 5) /= "0000000") and (adpcm_pcmRaw(11 downto 5) /= "1111111")) and adpcm_datemp = '1' else
		'0';
	hdmi_adpcm_datover <= adpcm_datover;

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
		rgb => console_rgb
	);

	console_textram0 : console_textram
	port map(
		clk => sys_clk,
		address => console_ram_addr,
		din => console_ram_din,
		dout => console_ram_dout,
		we => console_ram_we
	);

	process (sys_clk, sys_rstn)
		variable texty : std_logic_vector(5 downto 0);
	begin
		if (sys_rstn = '0') then
			console_ram_addr <= (others => '0');
			console_ram_din <= (others => '0');
			console_ram_we <= '0';
			console_char <= x"20";
		elsif (sys_clk' event and sys_clk = '1') then
			hdmi_cx_d <= hdmi_cx;
			hdmi_cy_d <= hdmi_cy;

			texty := hdmi_cy_d(9 downto 4); -- + nios2_scroll_y(5 downto 0);
			console_ram_addr <= texty(2 downto 0) & hdmi_cx_d(9 downto 3);
			if (hdmi_cx_d(2 downto 0) = "000") then
				if (hdmi_cx_d(9 downto 3) < 88) then
					console_char <= console_ram_dout;
				else
					console_char <= x"20";
				end if;
			end if;
		end if;
	end process;

	process (hdmi_cx, hdmi_cy)
		variable cx : integer range 0 to 719;
		variable bx : integer range 0 to 89; -- cx / 8
		variable lx : std_logic_vector(4 downto 0);
		variable lx2 : std_logic_vector(5 downto 0);
		variable r, g, b : std_logic_vector(7 downto 0);
		variable color_r, color_g, color_b : std_logic;
	begin
		cx := CONV_INTEGER(hdmi_cx);
		bx := cx / 8;

		r := (others => '0');

		color_r := '0';
		color_g := '0';
		color_b := '0';

		case cx is
			when 32 | 64 | 96 | 128 | 160 | 192 | 224 | 256 | 288 | 296 |
				360 | 424 | 432 | 464 | 496 | 528 | 560 | 592 | 624 | 656 | 688 =>
				r := "00000000"; -- boarder line
			when 16 | 48 | 80 | 112 | 144 | 176 | 208 | 240 | 272 | 328 |
				392 | 448 | 480 | 512 | 544 | 576 | 608 | 640 | 672 | 704 =>
				r := "00111111"; -- center line
			when others =>
				case bx is
					when 37 | 38 | 39 | 40 | 41 | 42 | 43 | 44 |
						45 | 46 | 47 | 48 | 49 | 50 | 51 | 52 =>
						r := "00101111"; -- bg color
					when others =>
						r := "00011111"; -- bg color
				end case;
		end case;

		case bx is
			when 0 | 1 | 2 | 3 =>
				lx := CONV_STD_LOGIC_VECTOR(cx, 5);
				if (lx = mercury_pcm_ssg1(15 downto 10) + 16) then
					r := "11111111";
				end if;
			when 4 | 5 | 6 | 7 =>
				lx := CONV_STD_LOGIC_VECTOR(cx, 5) - 32;
				if (lx = mercury_pcm_fmL1(15 downto 10) + 16) then
					r := "11111111";
				end if;
			when 8 | 9 | 10 | 11 =>
				lx := CONV_STD_LOGIC_VECTOR(cx, 5) - 64;
				if (lx = mercury_pcm_ssg0(15 downto 10) + 16) then
					r := "11111111";
				end if;
			when 12 | 13 | 14 | 15 =>
				lx := CONV_STD_LOGIC_VECTOR(cx, 5) - 96;
				if (lx = mercury_pcm_fmL0(15 downto 10) + 16) then
					r := "11111111";
				end if;
			when 16 | 17 | 18 | 19 =>
				lx := CONV_STD_LOGIC_VECTOR(cx, 5) - 128;
				if (lx = mercury_pcm_pcmL(15 downto 10) + 16) then
					r := "11111111";
				end if;
			when 20 | 21 | 22 | 23 =>
				lx := CONV_STD_LOGIC_VECTOR(cx, 5) - 160;
				if (lx = raspi_pcmL(15 downto 10) + 16) then
					r := "11111111";
				end if;
			when 24 | 25 | 26 | 27 =>
				lx := CONV_STD_LOGIC_VECTOR(cx, 5) - 192;
				if (lx = spdifin_pcmL(15 downto 10) + 16) then
					r := "11111111";
				end if;
			when 28 | 29 | 30 | 31 =>
				lx := CONV_STD_LOGIC_VECTOR(cx, 5) - 224;
				if hdmi_adpcm_datemp = '1' then
					r := "01111111";
					color_r := '1';
				elsif hdmi_adpcm_datover = '1' then
					r := "01111111";
					color_b := '1';
				elsif (lx = adpcm_pcmL(15 downto 9) + 16) then
					r := "11111111";
				end if;
			when 32 | 33 | 34 | 35 =>
				lx := CONV_STD_LOGIC_VECTOR(cx, 5) - 256;
				if (lx = opm_pcmL(15 downto 10) + 16) then
					r := "11111111";
				end if;
			when 36 =>
				r := "00000000";
			when 37 | 38 | 39 | 40 | 41 | 42 | 43 | 44 =>
				lx2 := CONV_STD_LOGIC_VECTOR(cx, 6) - 296;
				if (lx2 = snd_pcmL(15 downto 9) + 32) then
					r := "11111111";
				end if;
				--
				-- CENTER OF DISPLAY
				--
			when 45 | 46 | 47 | 48 | 49 | 50 | 51 | 52 =>
				lx2 := CONV_STD_LOGIC_VECTOR(cx, 6) - 360;
				if (lx2 = ("1111111" - snd_pcmR(15 downto 9)) + 32) then
					r := "11111111";
				end if;
			when 53 =>
				r := "00000000";
			when 54 | 55 | 56 | 57 =>
				lx := CONV_STD_LOGIC_VECTOR(cx, 5) - 432;
				if (lx = ("111111" - opm_pcmR(15 downto 10)) + 16) then
					r := "11111111";
				end if;
			when 58 | 59 | 60 | 61 =>
				lx := CONV_STD_LOGIC_VECTOR(cx, 5) - 464;
				if hdmi_adpcm_datemp = '1' then
					r := "01111111";
					color_r := '1';
				elsif hdmi_adpcm_datover = '1' then
					r := "01111111";
					color_b := '1';
				elsif (lx = ("1111111" - adpcm_pcmR(15 downto 9)) + 16) then
					r := "11111111";
				end if;
			when 62 | 63 | 64 | 65 =>
				lx := CONV_STD_LOGIC_VECTOR(cx, 5) - 496;
				if (lx = ("111111" - spdifin_pcmR(15 downto 10)) + 16) then
					r := "11111111";
				end if;
			when 66 | 67 | 68 | 69 =>
				lx := CONV_STD_LOGIC_VECTOR(cx, 5) - 528;
				if (lx = ("111111" - raspi_pcmR(15 downto 10)) + 16) then
					r := "11111111";
				end if;
			when 70 | 71 | 72 | 73 =>
				lx := CONV_STD_LOGIC_VECTOR(cx, 5) - 560;
				if (lx = ("111111" - mercury_pcm_pcmR(15 downto 10)) + 16) then
					r := "11111111";
				end if;
			when 74 | 75 | 76 | 77 =>
				lx := CONV_STD_LOGIC_VECTOR(cx, 5) - 592;
				if (lx = ("111111" - mercury_pcm_fmR0(15 downto 10)) + 16) then
					r := "11111111";
				end if;
			when 78 | 79 | 80 | 81 =>
				lx := CONV_STD_LOGIC_VECTOR(cx, 5) - 624;
				if (lx = ("111111" - mercury_pcm_ssg0(15 downto 10)) + 16) then
					r := "11111111";
				end if;
			when 82 | 83 | 84 | 85 =>
				lx := CONV_STD_LOGIC_VECTOR(cx, 5) - 656;
				if (lx = ("111111" - mercury_pcm_fmR1(15 downto 10)) + 16) then
					r := "11111111";
				end if;
			when 86 | 87 | 88 | 89 =>
				lx := CONV_STD_LOGIC_VECTOR(cx, 5) - 688;
				if (lx = ("111111" - mercury_pcm_ssg1(15 downto 10)) + 16) then
					r := "11111111";
				end if;
			when others =>
				null;
		end case;
		g := r;
		b := r;

		--
		if (color_r = '1') then
			hdmi_r <= r;
			hdmi_g <= (others => '0');
			hdmi_b <= (others => '0');
		elsif (color_g = '1') then
			hdmi_r <= (others => '0');
			hdmi_g <= g;
			hdmi_b <= (others => '0');
		elsif (color_b = '1') then
			hdmi_r <= (others => '0');
			hdmi_g <= (others => '0');
			hdmi_b <= b;
		else
			hdmi_r <= r;
			hdmi_g <= g;
			hdmi_b <= b;
		end if;
	end process;

	process (hdmi_cx, hdmi_cy)
		variable bg_line : std_logic_vector(7 downto 0);
	begin
		case hdmi_cx(9 downto 7) is
			when "000" => bg_line := (others => '0');
			when "001" => bg_line := CHAR_2(CONV_INTEGER(hdmi_cy(8 downto 5)));
			when "010" => bg_line := CHAR_0(CONV_INTEGER(hdmi_cy(8 downto 5)));
			when "011" => bg_line := CHAR_2(CONV_INTEGER(hdmi_cy(8 downto 5)));
			when "100" => bg_line := CHAR_2(CONV_INTEGER(hdmi_cy(8 downto 5)));
			when "101" => bg_line := (others => '0');
			when "110" => bg_line := (others => '0');
			when "111" => bg_line := (others => '0');
			when others => bg_line := (others => '0');
		end case;

		--mi68_bg <= bg_line(7 - CONV_INTEGER(hdmi_cx(6 downto 4)));
		mi68_bg <= '0';
	end process;

	--
	-- eMercury
	--
	mercury0 : eMercury
	port map(
		sys_clk => sys_clk,
		sys_rstn => sys_rstn,
		req => mercury_req,
		ack => mercury_ack,

		rw => sys_rw,
		addr => sys_addr(7 downto 0),
		uds_n => i_uds_n_d,
		lds_n => i_lds_n_d,
		idata => mercury_idata,
		odata => mercury_odata,

		irq_n => mercury_irq_n,
		int_vec => mercury_int_vec,

		drq_n => mercury_drq_n,
		dack_n => mercury_dack_n,

		pcl_en => mercury_pcl_en,
		pcl => mercury_pcl,

		-- specific i/o
		snd_clk => snd_clk,
		pcm_clk_6M144 => pcm_clk_6M144,
		pcm_clk_5M6448 => pcm_clk_5M6448,
		pcm_clk_8M => pcm_clk_8M,
		pcm_pcmL => mercury_pcm_pcmL,
		pcm_pcmR => mercury_pcm_pcmR,
		pcm_fmL0 => mercury_pcm_fmL0,
		pcm_fmR0 => mercury_pcm_fmR0,
		pcm_ssg0 => mercury_pcm_ssg0,
		pcm_rhythmL0 => mercury_pcm_rhythmL0,
		pcm_rhythmR0 => mercury_pcm_rhythmR0,
		pcm_fmL1 => mercury_pcm_fmL1,
		pcm_fmR1 => mercury_pcm_fmR1,
		pcm_ssg1 => mercury_pcm_ssg1,
		pcm_rhythmL1 => mercury_pcm_rhythmL1,
		pcm_rhythmR1 => mercury_pcm_rhythmR1,
		pcm_extinL => spdifin_pcmL,
		pcm_extinR => spdifin_pcmR
	);

	mercury_idata <= sys_idata;
	mercury_dack_n <= pGPIO1(3);
	pGPIO1(3) <= 'Z';

	pGPIO0(29) <= 'Z' when mercury_pcl_en = '0' else mercury_pcl;
	--pGPIO0(29) <= mercury_pcl;

	--
	-- MIDI I/F
	--
	midi : em3802 generic map(
		sysclk => sysclk_freq,
		oscm => 1000,
		oscf => 614
		)port map(
		sys_clk => sys_clk,
		sys_rstn => sys_rstn,
		req => midi_req,
		ack => midi_ack,

		rw => sys_rw,
		addr => sys_addr(3 downto 1),
		idata => midi_idata,
		odata => midi_odata,

		irq_n => midi_irq_n,
		int_vec => midi_int_vec,

		RxD => midi_rx,
		TxD => midi_tx,
		RxF => '1',
		TxF => open,
		SYNC => open,
		CLICK => open,
		GPOUT => open,
		GPIN => (others => '1'),
		GPOE => open,
		-- flow control
		transmitting => midi_transmitting,
		suspend => midi_suspend
	);
	midi_idata <= sys_idata(7 downto 0);

	-- MIDI TX
	pGPIO1(33) <= not midi_ext_tx; -- to External MIDI out
	pGPIO1(27) <= midi_mt32pi_tx; -- to mt32-pi MIDI in
	-- MIDI RX
	midi_rx <= pGPIO1(32);
	pGPIO1(32) <= 'Z';

	-- MIDI Control
	midi_ctrl0 : midi_ctrl
	generic map(
		sysclk => sysclk_freq
	)
	port map(
		sys_clk => sys_clk,
		sys_rstn => sys_rstn,
		req => mt32pi_req,
		ack => mt32pi_ack,

		rw => sys_rw,
		--addr => sys_addr(3 downto 1),
		idata => mt32pi_idata,
		odata => mt32pi_odata,

		-- All notes off request
		all_notes_off_req => midi_all_notes_off_req,
		all_notes_off_ack => midi_all_notes_off_ack,

		-- MIDI sources
		midi_source_1 => midi_tx,
		midi_source_1_active => midi_transmitting, -- 送信中は '1'
		midi_source_2 => midi_rx,
		midi_source_2_active => '0', -- TODO: MIDI-INをルーティングしている時もサスペンドできるようにする
		midi_source_3 => '1',
		midi_source_3_active => '0',

		-- MIDI outputs
		midi_out_ext => midi_ext_tx, -- 外部MIDI-OUT
		midi_out_mt32pi => midi_mt32pi_tx,

		-- MIDI routing
		midi_routing_ext => keplerx_reg(9)(1 downto 0), -- ("00": None, "01": Source1, "10": Source2, "11": Source3)
		midi_routing_mt32pi => keplerx_reg(9)(3 downto 2), -- ("00": None, "01": Source1, "10": Source2, "11": Source3)

		sending_ctrl_msg => midi_suspend
	);
	mt32pi_idata <= "0000" & keplerx_reg(10)(11 downto 0);

	--
	-- Expansion Memory
	--
	exmem : exmemory
	generic map(
		CLK_FREQUENCY => 100 -- SDRAM CLOCK FREQ 100MHz
	)
	port map(
		mem_clk => mem_clk,
		sys_rstn => sys_rstn,
		req => exmem_req,
		ack => exmem_ack,

		ref_lock_req => exmem_ref_lock_req,
		ref_lock_ack => exmem_ref_lock_ack,

		rw => sys_rw,
		uds_n => i_uds_n_d,
		lds_n => i_lds_n_d,
		addr => sys_addr(23 downto 0),
		idata => exmem_idata,
		odata => exmem_odata,
		odata_ready => exmem_odata_ready,

		-- SDRAM SIDE
		--sdram_clk => mem_clk,
		sdram_addr => exmem_SDRAM_ADDR,
		sdram_bank_addr => exmem_SDRAM_BA,
		sdram_idata => exmem_SDRAM_IDATA,
		sdram_odata => exmem_SDRAM_ODATA,
		sdram_odata_en => exmem_SDRAM_ODATA_en,
		sdram_clock_enable => exmem_SDRAM_CKE,
		sdram_cs_n => exmem_SDRAM_CS_N,
		sdram_ras_n => exmem_SDRAM_RAS_N,
		sdram_cas_n => exmem_SDRAM_CAS_N,
		sdram_we_n => exmem_SDRAM_WE_N,
		sdram_data_mask_low => exmem_SDRAM_DQM(0),
		sdram_data_mask_high => exmem_SDRAM_DQM(1)
	);

	pDRAM_ADDR <= exmem_SDRAM_ADDR;
	pDRAM_BA <= exmem_SDRAM_BA;
	pDRAM_CAS_N <= exmem_SDRAM_CAS_N;
	pDRAM_CKE <= exmem_SDRAM_CKE;
	pDRAM_CS_N <= exmem_SDRAM_CS_N;
	pDRAM_DQM <= exmem_SDRAM_DQM;
	pDRAM_RAS_N <= exmem_SDRAM_RAS_N;
	pDRAM_WE_N <= exmem_SDRAM_WE_N;

	pDRAM_DQ <= exmem_SDRAM_ODATA when exmem_SDRAM_ODATA_EN = '1' else (others => 'Z');
	exmem_SDRAM_IDATA <= pDRAM_DQ;

	--
	-- SPI Slave I/F for Raspberry-Pi
	--
	spi0 : SPI_SLAVE
	port map(
		CLK => sys_clk,
		RST => spi_rst,
		-- SPI SLAVE INTERFACE
		SCLK => spi_sclk, -- SPI clock
		CS_N => spi_cs_n, -- SPI chip select, active in low
		MOSI => spi_mosi, -- SPI serial data from master to slave
		MISO => spi_miso, -- SPI serial data from slave to master
		-- USER INTERFACE
		DIN => spi_din, -- data for transmission to SPI master
		DIN_VLD => spi_din_vld, -- when DIN_VLD = 1, data for transmission are valid
		DIN_RDY => spi_din_rdy, -- when DIN_RDY = 1, SPI slave is ready to accept valid data for transmission
		DOUT => spi_dout, -- received data from SPI master
		DOUT_VLD => spi_dout_vld -- when DOUT_VLD = 1, received data are valid
	);
	spi_rst <= not sys_rstn;
	spi_sclk <= pGPIO0_IN(0);
	spi_cs_n <= pGPIO0_IN(1);
	spi_mosi <= pGPIO0_00;
	pGPIO0_01 <= spi_miso;

	process (sys_clk, sys_rstn)
	begin
		if (sys_rstn = '0') then
			spi_din <= (others => '0');
			spi_din_vld <= '1';
			spi_dout_vld_d <= '0';
			spi_dout_vld_dd <= '0';
			spi_dout_latch <= (others => '0');
			spi_command <= (others => '0');
			spi_state <= SPI_IDLE;
			busmas_ack_d <= '0';
			spi_cs_n_d <= '1';
		elsif (sys_clk'event and sys_clk = '1') then
			busmas_ack_d <= busmas_ack;
			spi_cs_n_d <= spi_cs_n;

			spi_dout_vld_d <= spi_dout_vld;
			spi_dout_vld_dd <= spi_dout_vld_d;
			if (spi_dout_vld = '1') then
				spi_dout_latch <= spi_dout;
			end if;
			case spi_state is
				when SPI_IDLE =>
					spi_din <= busmas_status_berr & spi_command(6 downto 0); -- status
					if (spi_dout_vld_dd = '0' and spi_dout_vld_d = '1') then
						spi_command <= spi_dout_latch;
						case spi_dout_latch is
							when x"00" =>
								spi_state <= SPI_IDLE;
							when x"10" => -- busmaster set address
								spi_state <= SPI_CMD_BM_SETADDR_FC;
							when x"12" => -- busmaster set data
								spi_state <= SPI_CMD_BM_SETDATA_16;
							when x"13" => -- busmaster get data
								spi_state <= SPI_CMD_BM_GETDATA_16;
								spi_din <= spi_bm_idata(15 downto 8);
							when x"18" | x"19" | x"1a" | x"1b" => -- busmaster read
								-- 下位2bit : uds_n / lds_n
								spi_state <= SPI_CMD_BM_READ;
							when x"1c" | x"1d" | x"1e" | x"1f" => -- busmaster write
								-- 下位2bit : uds_n / lds_n
								spi_state <= SPI_CMD_BM_WRITE;

							when others =>
								spi_state <= SPI_IDLE;
						end case;
					end if;
					-- set addr
				when SPI_CMD_BM_SETADDR_FC =>
					if (spi_dout_vld_dd = '0' and spi_dout_vld_d = '1') then
						spi_bm_fc <= spi_dout_latch(2 downto 0);
						spi_state <= SPI_CMD_BM_SETADDR_24;
					end if;
				when SPI_CMD_BM_SETADDR_24 =>
					if (spi_dout_vld_dd = '0' and spi_dout_vld_d = '1') then
						spi_bm_addr(23 downto 16) <= spi_dout_latch;
						spi_state <= SPI_CMD_BM_SETADDR_16;
					end if;
				when SPI_CMD_BM_SETADDR_16 =>
					if (spi_dout_vld_dd = '0' and spi_dout_vld_d = '1') then
						spi_bm_addr(15 downto 8) <= spi_dout_latch;
						spi_state <= SPI_CMD_BM_SETADDR_8;
					end if;
				when SPI_CMD_BM_SETADDR_8 =>
					if (spi_dout_vld_dd = '0' and spi_dout_vld_d = '1') then
						spi_bm_addr(7 downto 0) <= spi_dout_latch;
						spi_state <= SPI_FIN;
					end if;
					-- set data
				when SPI_CMD_BM_SETDATA_16 =>
					if (spi_dout_vld_dd = '0' and spi_dout_vld_d = '1') then
						spi_bm_odata(15 downto 8) <= spi_dout_latch;
						spi_state <= SPI_CMD_BM_SETDATA_8;
					end if;
				when SPI_CMD_BM_SETDATA_8 =>
					if (spi_dout_vld_dd = '0' and spi_dout_vld_d = '1') then
						spi_bm_odata(7 downto 0) <= spi_dout_latch;
						spi_state <= SPI_FIN;
					end if;
					-- get data
				when SPI_CMD_BM_GETDATA_16 =>
					if (spi_dout_vld_dd = '0' and spi_dout_vld_d = '1') then
						spi_state <= SPI_CMD_BM_GETDATA_8;
						spi_din <= spi_bm_idata(7 downto 0);
					end if;
				when SPI_CMD_BM_GETDATA_8 =>
					if (spi_dout_vld_dd = '0' and spi_dout_vld_d = '1') then
						spi_state <= SPI_FIN;
					end if;
					-- read
				when SPI_CMD_BM_READ =>
					busmas_fc <= spi_bm_fc;
					busmas_addr <= spi_bm_addr;
					busmas_rw <= '1';
					busmas_uds_n <= spi_command(1);
					busmas_lds_n <= spi_command(0);
					busmas_req <= '1';
					spi_state <= SPI_CMD_BM_READ_WAIT;
				when SPI_CMD_BM_READ_WAIT =>
					busmas_req <= '1';
					if (busmas_ack_d = '1') then
						busmas_req <= '0';
						spi_bm_idata <= busmas_idata;
						spi_state <= SPI_FIN;
					end if;
					-- write
				when SPI_CMD_BM_WRITE =>
					busmas_fc <= spi_bm_fc;
					busmas_addr <= spi_bm_addr;
					busmas_rw <= '0';
					busmas_uds_n <= spi_command(1);
					busmas_lds_n <= spi_command(0);
					busmas_odata <= spi_bm_odata;
					busmas_req <= '1';
					spi_state <= SPI_CMD_BM_WRITE_WAIT;
				when SPI_CMD_BM_WRITE_WAIT =>
					busmas_req <= '1';
					if (busmas_ack_d = '1') then
						busmas_req <= '0';
						spi_state <= SPI_FIN;
					end if;
					-- fin
				when SPI_FIN =>
					-- FINの時は cs_nが '1'になってIDLEに戻るのを待つ
					if (spi_cs_n_d = '1') then
						spi_state <= SPI_IDLE;
					end if;

				when others =>
					spi_state <= SPI_IDLE;
			end case;
		end if;
	end process;

end rtl;