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
		pGPIO_2 : inout std_logic_vector(12 downto 0);
		pGPIO_2_IN : in std_logic_vector(2 downto 0);

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

	signal pClk24M576 : std_logic;

	signal x68clk10m : std_logic;
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
			c0 : out std_logic; -- 12.288MHz
			c1 : out std_logic; -- 3.072MHz
			locked : out std_logic
		);
	end component;

	component pllpcm44k1 is
		port (
			areset : in std_logic := '0';
			inclk0 : in std_logic := '0';
			c0 : out std_logic; -- 11.2896MHz
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

	signal led_counter_25m : std_logic_vector(23 downto 0);
	signal led_counter_10m : std_logic_vector(23 downto 0);

	--
	-- Sound
	--
	signal snd_clk : std_logic; -- internal sound operation clock (16MHz)
	signal snd_pcmL, snd_pcmR : std_logic_vector(15 downto 0);
	signal snd_pcm_mix31L, snd_pcm_mix31R : std_logic_vector(15 downto 0);
	signal snd_pcm_mix32L, snd_pcm_mix32R : std_logic_vector(15 downto 0);
	signal snd_pcm_mix33L, snd_pcm_mix33R : std_logic_vector(15 downto 0);
	signal snd_pcm_mix34L, snd_pcm_mix34R : std_logic_vector(15 downto 0);
	signal snd_pcm_mix21L, snd_pcm_mix21R : std_logic_vector(15 downto 0);
	signal snd_pcm_mix22L, snd_pcm_mix22R : std_logic_vector(15 downto 0);

	-- util
	component addsat
		generic (
			datwidth : integer := 16
		);
		port (
			snd_clk : std_logic;

			INA : in std_logic_vector(datwidth - 1 downto 0);
			INB : in std_logic_vector(datwidth - 1 downto 0);

			OUTQ : out std_logic_vector(datwidth - 1 downto 0);
			OFLOW : out std_logic;
			UFLOW : out std_logic
		);
	end component;

	-- FM Sound
	component OPM_JT51
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

	signal opm_req : std_logic;
	signal opm_ack : std_logic;
	signal opm_idata : std_logic_vector(7 downto 0);
	signal opm_odata : std_logic_vector(7 downto 0);

	signal opm_pcmLi : std_logic_vector(15 downto 0);
	signal opm_pcmRi : std_logic_vector(15 downto 0);
	signal opm_pcmL : std_logic_vector(15 downto 0);
	signal opm_pcmR : std_logic_vector(15 downto 0);

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

	-- i2s sound

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

	signal i2s_sndL, i2s_sndR : std_logic_vector(31 downto 0);
	signal bclk_pcmL, bclk_pcmR : std_logic_vector(31 downto 0);

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
			SYS_CLK : integer := 25000;
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

	-- ppi

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

	signal ppi_req : std_logic;
	signal ppi_ack : std_logic;
	signal ppi_idata : std_logic_vector(7 downto 0);
	signal ppi_pai : std_logic_vector(7 downto 0);
	signal ppi_pao : std_logic_vector(7 downto 0);
	signal ppi_paoe : std_logic;
	signal ppi_pbi : std_logic_vector(7 downto 0);
	signal ppi_pbo : std_logic_vector(7 downto 0);
	signal ppi_pboe : std_logic;
	signal ppi_pchi : std_logic_vector(3 downto 0);
	signal ppi_pcho : std_logic_vector(3 downto 0);
	signal ppi_pchoe : std_logic;
	signal ppi_pcli : std_logic_vector(3 downto 0);
	signal ppi_pclo : std_logic_vector(3 downto 0);
	signal ppi_pcloe : std_logic;

	--
	-- HDMI
	--
	type audio_sample_word_t is array (1 downto 0) of std_logic_vector(15 downto 0);

	component hdmi
		generic (
			VIDEO_ID_CODE : integer := 1;
			BIT_WIDTH : integer := 10;
			BIT_HEIGHT : integer := 10;
			VIDEO_REFRESH_RATE : real := 59.94;
			AUDIO_RATE : integer := 48000;
			AUDIO_BIT_WIDTH : integer := 16
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
	signal hdmi_cy : std_logic_vector(9 downto 0);

	signal hdmi_test_r : std_logic_vector(7 downto 0);
	signal hdmi_test_g : std_logic_vector(7 downto 0);
	signal hdmi_test_b : std_logic_vector(7 downto 0);

	--
	-- test register
	--
	signal tst_req : std_logic;
	signal tst_ack : std_logic;
	type reg_type is array(0 to 7) of std_logic_vector(15 downto 0);
	signal test_reg : reg_type;

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
			pcm_clk_12M288 : in std_logic; -- 48kHz * 2 * 128
			pcm_clk_11M2896 : in std_logic; -- 44.1kHz * 2 * 128
			pcm_clk_8M : in std_logic; -- 32kHz * 2 * 125
			pcm_pcmL : out pcm_type;
			pcm_pcmR : out pcm_type;
			pcm_fm0 : out pcm_type;
			pcm_ssg0 : out pcm_type;
			pcm_fm1 : out pcm_type;
			pcm_ssg1 : out pcm_type
		);
	end component;

	signal pcm_clk_12M288 : std_logic; -- 48kHz * 2 * 128
	signal pcm_clk_11M2896 : std_logic; -- 44.1kHz * 2 * 128
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
	signal mercury_pcm_fm0 : std_logic_vector(15 downto 0);
	signal mercury_pcm_ssg0 : std_logic_vector(15 downto 0);
	signal mercury_pcm_fm1 : std_logic_vector(15 downto 0);
	signal mercury_pcm_ssg1 : std_logic_vector(15 downto 0);

	--
	-- MIDI I/F
	--
	component em3802
		generic (
			sysclk : integer := 25000;
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
			GPOE : out std_logic_vector(7 downto 0)
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

	--
	-- Expansion Memory
	--
	component exmemory
		port (
			sys_clk : in std_logic;
			sys_rstn : in std_logic;
			req : in std_logic;
			ack : out std_logic;

			rw : in std_logic;
			uds_n : in std_logic;
			lds_n : in std_logic;
			addr : in std_logic_vector(23 downto 0);
			idata : in std_logic_vector(15 downto 0);
			odata : out std_logic_vector(15 downto 0);

			-- SDRAM SIDE
			sdram_clk : in std_logic;
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
	signal exmem_watchdog : std_logic_vector(3 downto 0);
	signal exmem_req : std_logic;
	signal exmem_ack : std_logic;
	signal exmem_ack_d : std_logic;
	signal exmem_idata : std_logic_vector(15 downto 0);
	signal exmem_odata : std_logic_vector(15 downto 0);

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
	signal i_as_n : std_logic;
	signal i_as_n_d : std_logic;
	signal i_as_n_dd : std_logic;
	signal i_as_duration : std_logic_vector(7 downto 0);
	signal i_lds_n : std_logic;
	signal i_uds_n : std_logic;
	signal i_rw : std_logic;
	signal i_bg_n : std_logic;
	signal i_bg_n_d : std_logic;
	signal i_sdata : std_logic_vector(15 downto 0);
	signal i_iack_n : std_logic;
	signal o_dtack_n : std_logic;
	signal o_sdata : std_logic_vector(15 downto 0);
	signal o_irq_n : std_logic;
	signal o_drq_n : std_logic;
	-- for bus master
	signal o_as_n : std_logic;
	signal o_lds_n : std_logic;
	signal o_uds_n : std_logic;
	signal i_dtack_n : std_logic;
	signal i_dtack_n_d : std_logic;
	signal i_dtack_n_dd : std_logic;
	signal i_dtack_n_ddd : std_logic;
	signal o_rw : std_logic;
	signal o_br_n : std_logic;
	signal o_bgack_n : std_logic;
	type bus_state_t is(
	BS_IDLE,
	BS_S_ABIN_U,
	BS_S_ABIN_U2,
	BS_S_ABIN_L,
	BS_S_ABIN_L2,
	BS_S_DBIN,
	BS_S_DBIN2,
	BS_S_DBOUT_P,
	BS_S_DBOUT,
	BS_S_FIN_WAIT,
	BS_S_FIN_RD,
	BS_S_FIN_RD_2,
	BS_S_FIN,
	BS_S_IACK,
	BS_S_IACK2,
	BS_M_ABOUT_U,
	BS_M_ABOUT_U2,
	BS_M_ABOUT_U3,
	BS_M_ABOUT_L,
	BS_M_ABOUT_L2,
	BS_M_ABOUT_L3,
	BS_M_DBIN_WAIT, -- wait for dtack
	BS_M_DBIN, -- latch data on 16374
	BS_M_DBIN2, -- latch data on FPGA
	BS_M_DBOUT_P,
	BS_M_DBOUT, -- out data
	BS_M_DBOUT_WAIT, -- wait for dtack
	BS_M_FIN_WAIT, -- wait for ack
	BS_M_FIN
	);
	signal bus_state : bus_state_t;
	signal bus_mode : std_logic_vector(3 downto 0);

	signal sys_fc : std_logic_vector(2 downto 0);
	signal sys_addr : std_logic_vector(23 downto 0);
	signal sys_idata : std_logic_vector(15 downto 0);
	signal sys_rw : std_logic;
	signal sys_uds_n : std_logic;
	signal sys_lds_n : std_logic;

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
	x68clk10m <= pGPIO1_IN(0);
	x68rstn <= pGPIO1(31);
	pGPIO1(31) <= 'Z';

	pllrst <= not x68rstn;
	pllmain_inst : pllmain port map(
		areset => pllrst,
		inclk0 => pClk50M,
		c0 => mem_clk, -- 100MHz
		c1 => pDRAM_CLK, -- 100MHz + 180°
		c2 => sys_clk, -- 25MHz
		c3 => snd_clk, -- 16MHz
		c4 => pcm_clk_8M,
		locked => plllock_main
	);

	pllpcm48k_inst : pllpcm48k port map(
		areset => pllrst,
		inclk0 => pClk24M576,
		--inclk0 => pClk50M,		
		c0 => pcm_clk_12M288, -- 24.576MHz / 2
		c1 => i2s_bclk,
		locked => plllock_pcm48k
	);

	pllpcm44k1_inst : pllpcm44k1 port map(
		areset => pllrst,
		inclk0 => pClk24M576,
		--inclk0 => pClk50M,
		c0 => pcm_clk_11M2896, -- 22.5792MHz / 2
		locked => plllock_pcm44k1
	);

	plldvi_inst : plldvi port map(
		areset => pllrst,
		inclk0 => pClk50M,
		c0 => hdmi_clk, -- 27MHz
		c1 => hdmi_clk_x5, -- 135MHz
		locked => plllock_dvi
	);

	--	sys_rstn <= plllock_main and plllock_pcm48k and plllock_pcm44k1 and plllock_dvi and x68rstn;
	sys_rstn <= plllock_main and plllock_dvi and x68rstn;

	pLED(7) <= led_counter_25m(23);
	pLED(6) <= led_counter_25m(22);
	pLED(5) <= led_counter_25m(21);
	pLED(4) <= led_counter_25m(20);
	pLED(3) <= led_counter_10m(23);
	pLED(2) <= led_counter_10m(22);
	pLED(1) <= led_counter_10m(21);
	pLED(0) <= led_counter_10m(20);

	process (sys_clk, sys_rstn)begin
		if (sys_rstn = '0') then
			led_counter_25m <= (others => '0');
		elsif (sys_clk' event and sys_clk = '1') then
			led_counter_25m <= led_counter_25m + 1;
		end if;
	end process;

	process (x68clk10m, sys_rstn)begin
		if (sys_rstn = '0') then
			led_counter_10m <= (others => '0');
		elsif (x68clk10m' event and x68clk10m = '1') then
			led_counter_10m <= led_counter_10m + 1;
		end if;
	end process;

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
	pGPIO0(31) <= 'Z' when o_irq_n = '1' else '0';
	pGPIO0(32) <= 'Z' when o_br_n = '1' else '0';
	pGPIO0(33) <= 'Z' when o_bgack_n = '1' else '0';
	pGPIO0(21) <= 'Z' when o_as_n = '1' else '0';
	pGPIO0(22) <= 'Z' when o_lds_n = '1' else '0';
	pGPIO0(23) <= 'Z' when o_uds_n = '1' else '0';
	pGPIO0(24) <= 'Z' when o_as_n = '1' else o_rw;

	o_drq_n <= mercury_drq_n;
	--o_drq <= mercury_pcl;
	o_irq_n <= mercury_irq_n and midi_irq_n;

	bus_mode <=
		"0000" when bus_state = BS_IDLE else
		"0010" when bus_state = BS_S_ABIN_U else
		"0010" when bus_state = BS_S_ABIN_U2 else
		"0011" when bus_state = BS_S_ABIN_L else
		"0011" when bus_state = BS_S_ABIN_L2 else
		"0100" when bus_state = BS_S_DBIN else
		"0100" when bus_state = BS_S_DBIN2 else
		"0100" when bus_state = BS_S_FIN_WAIT and sys_rw = '0' else
		"0000" when bus_state = BS_S_FIN and sys_rw = '0' else
		"0000" when bus_state = BS_S_DBOUT_P else -- アドレスが確定して、内部のどのペリフェラルへのアクセスかを判定中
		"0000" when bus_state = BS_S_FIN_WAIT and sys_rw = '1' else
		"0000" when bus_state = BS_S_IACK else
		"0000" when bus_state = BS_S_IACK2 else
		"0000" when bus_state = BS_S_FIN_RD else
		"0101" when bus_state = BS_S_FIN_RD_2 else
		"0101" when bus_state = BS_S_FIN and sys_rw = '1' else
		"1000" when bus_state = BS_M_ABOUT_U else
		"1010" when bus_state = BS_M_ABOUT_U2 else -- AOCKU rise
		"1000" when bus_state = BS_M_ABOUT_U3 else
		"1000" when bus_state = BS_M_ABOUT_L else
		"1011" when bus_state = BS_M_ABOUT_L2 else -- AOCKL rise
		"1011" when bus_state = BS_M_ABOUT_L3 else
		"1000" when bus_state = BS_M_DBIN_WAIT else
		"1100" when bus_state = BS_M_DBIN else -- DICK rise
		"1100" when bus_state = BS_M_DBIN2 else
		"1100" when bus_state = BS_M_FIN_WAIT and busmas_rw = '1' else
		"1000" when bus_state = BS_M_DBOUT_P else
		"1101" when bus_state = BS_M_DBOUT else -- DOCK rise
		"1101" when bus_state = BS_M_DBOUT_WAIT else
		"1101" when bus_state = BS_M_FIN_WAIT and busmas_rw = '0' else
		"0000" when bus_state = BS_M_FIN else
		"0000";
	pGPIO0(15) <= bus_mode(0);
	pGPIO0(14) <= bus_mode(1);
	pGPIO0(13) <= bus_mode(2);
	pGPIO0(12) <= bus_mode(3);

	i_sdata <= pGPIO1(21 downto 6);
	pGPIO1(21 downto 6) <=
	o_sdata when sys_rw = '1' and (bus_state = BS_S_FIN_WAIT or bus_state = BS_S_FIN_RD or bus_state = BS_S_FIN_RD_2 or bus_state = BS_S_FIN) else
	o_sdata when bus_state = BS_S_IACK or bus_state = BS_S_IACK2 else
	o_sdata when bus_state = BS_M_ABOUT_U or bus_state = BS_M_ABOUT_U2 or bus_state = BS_M_ABOUT_U3 or
	bus_state = BS_M_ABOUT_L or bus_state = BS_M_ABOUT_L2 or bus_state = BS_M_ABOUT_L3 or
	bus_state = BS_M_DBOUT_P or bus_state = BS_M_DBOUT else
	(others => 'Z');

	process (sys_clk, sys_rstn)
		variable cs : std_logic;
		variable fin : std_logic;
		variable addr_block : std_logic_vector(3 downto 0);
	begin
		if (sys_rstn = '0') then
			cs := '0';
			fin := '0';
			addr_block := (others => '0');
			bus_state <= BS_IDLE;
			sys_fc <= (others => '0');
			sys_addr <= (others => '0');
			sys_idata <= (others => '0');
			sys_rw <= '1';
			sys_uds_n <= '1';
			sys_lds_n <= '1';
			o_dtack_n <= '1';
			i_as_n_d <= '1';
			i_as_n_dd <= '1';
			i_dtack_n_d <= '1';
			i_dtack_n_dd <= '1';
			i_dtack_n_ddd <= '1';
			exmem_req <= '0';
			exmem_ack_d <= '0';
			exmem_enabled <= (others => '0');
			tst_req <= '0';
			opm_req <= '0';
			adpcm_req <= '0';
			ppi_req <= '0';
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
		elsif (sys_clk' event and sys_clk = '1') then
			if i_as_n_d = '1' then
				i_as_duration <= (others => '0');
			else
				i_as_duration <= i_as_duration + 1;
			end if;
			i_as_n_d <= i_as_n;
			i_as_n_dd <= i_as_n_d;
			o_dtack_n <= '1';
			exmem_ack_d <= exmem_ack;

			-- busmaster request
			busmas_req_d <= busmas_req;
			o_br_n <= '1';
			i_bg_n_d <= i_bg_n;
			i_dtack_n_d <= i_dtack_n;
			i_dtack_n_dd <= i_dtack_n_d;
			i_dtack_n_ddd <= i_dtack_n_dd;
			o_as_n <= '1';
			o_uds_n <= '1';
			o_lds_n <= '1';
			o_bgack_n <= '1';
			if (busmas_req_d /= busmas_ack and o_bgack_n = '1') then
				-- バスマスタでアクセスしたくなったらとにかくバスリクエストを出す
				o_br_n <= '0';
			end if;

			case bus_state is
				when BS_IDLE =>
					tst_req <= '0';
					opm_req <= '0';
					adpcm_req <= '0';
					ppi_req <= '0';
					exmem_watchdog <= (others => '1');
					if (i_as_n_dd = '1' and i_as_n_d = '0') then
						-- falling edge
						bus_state <= BS_S_ABIN_U;
					elsif (i_bg_n_d = '0') then
						-- bus granted
						o_bgack_n <= '0';
						o_sdata <= "00000" & --
							busmas_fc & -- FC2-0 : "101" is supervisor data
							busmas_addr(23 downto 16);
						bus_state <= BS_M_ABOUT_U;
					end if;
				when BS_S_ABIN_U =>
					-- このタイミングだとdtackを誤読することがあったので、ここではdtackの応答はみない
					bus_state <= BS_S_ABIN_U2;
				when BS_S_ABIN_U2 =>
					if (i_as_n_d = '1') then -- 自分以外が応答していたらIDLEに戻る
						bus_state <= BS_IDLE;
					else
						bus_state <= BS_S_ABIN_L;
					end if;
					sys_fc(2 downto 0) <= i_sdata(10 downto 8);
					sys_addr(23 downto 16) <= i_sdata(7 downto 0);
					sys_rw <= i_rw;
					sys_uds_n <= i_uds_n;
					sys_lds_n <= i_lds_n;
				when BS_S_ABIN_L =>
					if (i_as_n_d = '1') then -- 自分以外が応答していたらIDLEに戻る
						bus_state <= BS_IDLE;
					else
						bus_state <= BS_S_ABIN_L2;
					end if;
				when BS_S_ABIN_L2 =>
					if (i_as_n_d = '1') then -- 自分以外が応答していたらIDLEに戻る
						bus_state <= BS_IDLE;
					else
						if (sys_uds_n = '1' and sys_lds_n = '0') then
							sys_addr(15 downto 0) <= i_sdata(15 downto 1) & "1";
						else
							sys_addr(15 downto 0) <= i_sdata(15 downto 1) & "0";
						end if;
						case sys_fc is
							when "000" | "011" | "100" =>
								-- no defined
								bus_state <= BS_IDLE;
							when "001" | "010" | "101" | "110" =>
								-- user access and supervisor access
								if (sys_rw = '0') then
									bus_state <= BS_S_DBIN;
								else
									bus_state <= BS_S_DBOUT_P;
								end if;
							when "111" =>
								-- interrupt acknowledge
								if (i_iack_n = '0') then
									bus_state <= BS_S_IACK;
								else
									bus_state <= BS_IDLE;
								end if;
							when others =>
								bus_state <= BS_IDLE;
						end case;
					end if;

					-- write cycle
				when BS_S_DBIN =>
					if (i_as_n_d = '1') then -- 自分以外が応答していたらIDLEに戻る
						bus_state <= BS_IDLE;
					else
						bus_state <= BS_S_DBIN2;
					end if;
				when BS_S_DBIN2 =>
					sys_idata <= i_sdata;
					if (sys_addr(23 downto 20) >= x"2" and sys_addr(23 downto 20) < x"c") then -- mem
						addr_block := sys_addr(23 downto 20);
						if (exmem_enabled(CONV_INTEGER(addr_block)) = '1') then
							exmem_req <= '1';
							bus_state <= BS_S_FIN_WAIT;
						else
							if (i_as_n_d = '1') then
								-- 自分以外の誰かが DTACKをアサートしたら無視
								bus_state <= BS_IDLE;
							elsif (exmem_watchdog = 0) then
								-- 一定時間内に誰も DTACKをアサートしなかったら自分が応答
								-- フラグを立てて、次回は自動応答
								exmem_enabled(CONV_INTEGER(addr_block)) <= '1';
								exmem_req <= '1';
								bus_state <= BS_S_FIN_WAIT;
							else
								exmem_watchdog <= exmem_watchdog - 1;
							end if;
						end if;
					else
						cs := '1';
						if (sys_fc(2) = '1' and sys_addr(23 downto 12) = x"ecb") then -- test register
							tst_req <= '1';
						elsif (sys_fc(2) = '1' and sys_addr(23 downto 2) = x"e9000" & "00") then -- OPM (YM2151)
							opm_req <= '1';
						elsif (sys_fc(2) = '1' and sys_addr(23 downto 2) = x"e9200" & "00") and sys_lds_n = '0' then -- ADPCM (6258)
							adpcm_req <= '1';
						elsif (sys_fc(2) = '1' and sys_addr(23 downto 4) = x"eafa0") then -- MIDI I/F
							midi_req <= '1';
						elsif (sys_fc(2) = '1' and sys_addr(23 downto 3) = x"e9a00" & "0") and sys_lds_n = '0' then -- PPI (8255)
							ppi_req <= '1';
						elsif (sys_fc(2) = '1' and sys_addr(23 downto 8) = x"ecc0") then -- Mercury Unit
							-- 0xecc000〜0xecc0ff
							mercury_req <= '1';
						else
							cs := '0';
						end if;

						if cs = '1' then
							bus_state <= BS_S_FIN_WAIT;
						else
							bus_state <= BS_IDLE;
						end if;
					end if;
					-- interrup acknowledge cycle
				when BS_S_IACK =>
					if (mercury_irq_n = '0') then
						o_sdata <= x"00" & mercury_int_vec;
					elsif (midi_irq_n = '0') then
						o_sdata <= x"00" & midi_int_vec;
					else
						o_sdata <= (others => '0');
					end if;
					bus_state <= BS_S_IACK2;

				when BS_S_IACK2 =>
					bus_state <= BS_S_FIN_RD;

					-- read cycle
				when BS_S_DBOUT_P =>
					if (sys_addr(23 downto 20) >= x"2" and sys_addr(23 downto 20) < x"c") then -- mem
						addr_block := sys_addr(23 downto 20);
						if (exmem_enabled(CONV_INTEGER(addr_block)) = '1') then
							exmem_req <= '1';
							bus_state <= BS_S_FIN_WAIT;
						else
							if (i_as_n_d = '1') then
								-- 自分以外の誰かが DTACKをアサートしたら無視
								bus_state <= BS_IDLE;
							elsif (exmem_watchdog = 0) then
								-- 一定時間内に誰も DTACKをアサートしなかったら自分が応答
								-- フラグを立てて、次回は自動応答
								exmem_enabled(CONV_INTEGER(addr_block)) <= '1';
								exmem_req <= '1';
								bus_state <= BS_S_FIN_WAIT;
							else
								exmem_watchdog <= exmem_watchdog - 1;
							end if;
						end if;
					else
						cs := '1';
						if (sys_fc(2) = '1' and sys_addr(23 downto 12) = x"ecb") then -- test register
							tst_req <= '1';
						elsif (sys_fc(2) = '1' and sys_addr(23 downto 2) = x"e9000" & "00") then -- OPM (YM2151)
							-- ignore read cycle
							opm_req <= '0';
							cs := '0';
						elsif (sys_fc(2) = '1' and sys_addr(23 downto 2) = x"e9200" & "00") then -- ADPCM (6258)
							-- ignore read cycle
							adpcm_req <= '0';
							cs := '0';
						elsif (sys_fc(2) = '1' and sys_addr(23 downto 4) = x"eafa0") then -- MIDI I/F
							midi_req <= '1';
						elsif (sys_fc(2) = '1' and sys_addr(23 downto 3) = x"e9a00" & "0") then -- PPI (8255)
							-- ignore read cycle
							ppi_req <= '0';
							cs := '0';
						elsif (sys_fc(2) = '1' and sys_addr(23 downto 8) = x"ecc0") then -- Mercury Unit
							-- 0xecc000〜0xecc0ff
							mercury_req <= '1';
						else
							cs := '0';
						end if;

						if cs = '1' then
							bus_state <= BS_S_FIN_WAIT;
						else
							bus_state <= BS_IDLE;
						end if;
					end if;

					-- finish
				when BS_S_FIN_WAIT =>
					fin := '0';
					if exmem_req = '1' then
						o_sdata <= exmem_odata;
						if exmem_ack_d = '1' then
							exmem_req <= '0';
							fin := '1';
						end if;
					elsif tst_req = '1' then
						if sys_addr(4) = '0' then
							o_sdata <= test_reg(conv_integer(sys_addr(3 downto 1)));
						else
							o_sdata <= x"00" & i_as_duration;
						end if;
						if tst_ack = '1' then
							tst_req <= '0';
							fin := '1';
						end if;
					elsif opm_req = '1' then
						o_sdata <= (others => '0');
						if opm_ack = '1' then
							opm_req <= '0';
							bus_state <= BS_IDLE; -- ignore dtack
						end if;
					elsif adpcm_req = '1' then
						o_sdata <= (others => '0');
						if adpcm_ack = '1' then
							adpcm_req <= '0';
							bus_state <= BS_IDLE; -- ignore dtack
						end if;
					elsif midi_req = '1' then
						o_sdata <= x"00" & midi_odata;
						if midi_ack = '1' then
							midi_req <= '0';
							fin := '1';
						end if;
					elsif ppi_req = '1' then
						o_sdata <= (others => '0');
						if ppi_ack = '1' then
							ppi_req <= '0';
							bus_state <= BS_IDLE; -- ignore dtack
						end if;
					elsif mercury_req = '1' then
						o_sdata <= mercury_odata;
						if mercury_ack = '1' then
							mercury_req <= '0';
							fin := '1';
						end if;
					else
						-- invalid state (no req was found)
						bus_state <= BS_IDLE;
					end if;

					if fin = '1' then
						if (sys_rw = '0') then
							bus_state <= BS_S_FIN;
						else
							bus_state <= BS_S_FIN_RD;
						end if;
					end if;
				when BS_S_FIN_RD =>
					bus_state <= BS_S_FIN_RD_2;

				when BS_S_FIN_RD_2 =>
					bus_state <= BS_S_FIN;

				when BS_S_FIN =>
					o_dtack_n <= '0';
					if (i_as_n_d = '1') then
						bus_state <= BS_IDLE;
					end if;

					--
					-- bus master cyle
					--
				when BS_M_ABOUT_U =>
					o_bgack_n <= '0';
					bus_state <= BS_M_ABOUT_U2;
				when BS_M_ABOUT_U2 =>
					o_bgack_n <= '0';
					bus_state <= BS_M_ABOUT_U3;
				when BS_M_ABOUT_U3 =>
					o_bgack_n <= '0';
					o_sdata <= busmas_addr(15 downto 0);
					bus_state <= BS_M_ABOUT_L;
				when BS_M_ABOUT_L =>
					o_bgack_n <= '0';
					bus_state <= BS_M_ABOUT_L2;
				when BS_M_ABOUT_L2 =>
					o_bgack_n <= '0';
					bus_state <= BS_M_ABOUT_L3;
				when BS_M_ABOUT_L3 =>
					o_bgack_n <= '0';
					o_rw <= busmas_rw;
					if (busmas_rw = '1') then
						bus_state <= BS_M_DBIN_WAIT;
						busmas_counter <= (others => '1');
					else
						o_sdata <= busmas_odata;
						bus_state <= BS_M_DBOUT_P;
					end if;
					-- read cycle
				when BS_M_DBIN_WAIT => -- 相手のDTACKを待つ
					o_bgack_n <= '0';
					o_as_n <= '0';
					o_uds_n <= busmas_uds_n;
					o_lds_n <= busmas_lds_n;
					if (i_dtack_n_ddd = '0') then
						bus_state <= BS_M_DBIN;
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
				when BS_M_DBIN => -- このタイミングで16374に入力データが取り込まれるので、次のステートてFPGAに取り込む
					o_bgack_n <= '0';
					o_as_n <= '0';
					o_uds_n <= busmas_uds_n;
					o_lds_n <= busmas_lds_n;
					bus_state <= BS_M_DBIN2;
				when BS_M_DBIN2 =>
					o_bgack_n <= '0';
					o_as_n <= '0';
					o_uds_n <= busmas_uds_n;
					o_lds_n <= busmas_lds_n;
					busmas_idata <= i_sdata;
					bus_state <= BS_M_FIN_WAIT;
					-- write cycle
				when BS_M_DBOUT_P =>
					o_bgack_n <= '0';
					o_as_n <= '1';
					bus_state <= BS_M_DBOUT;
					busmas_counter <= (others => '1');
				when BS_M_DBOUT => --このタイミングで16374に出力データが取り込まれるので、次のステートでAS,UDS,LDSをアサート
					o_bgack_n <= '0';
					o_as_n <= '1';
					bus_state <= BS_M_DBOUT_WAIT;
					busmas_counter <= (others => '1');
				when BS_M_DBOUT_WAIT =>
					o_bgack_n <= '0';
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
					o_bgack_n <= '1';
					o_as_n <= '1';
					o_uds_n <= '1';
					o_lds_n <= '1';
					busmas_ack <= '1';
					if (busmas_req = '0') then
						busmas_ack <= '0';
						bus_state <= BS_M_FIN;
					end if;
				when BS_M_FIN =>
					o_bgack_n <= '1';
					o_as_n <= '1';
					o_uds_n <= '1';
					o_lds_n <= '1';
					bus_state <= BS_IDLE;

					-- other
				when others =>
					bus_state <= BS_IDLE;
					o_dtack_n <= '1';
			end case;
		end if;
	end process;

	--
	-- test register
	--
	process (sys_clk, sys_rstn)
	begin
		if (sys_rstn = '0') then
			tst_ack <= '0';
		elsif (sys_clk' event and sys_clk = '1') then
			if tst_req = '1' and tst_ack = '0' then
				if sys_rw = '0' then
					test_reg(conv_integer(sys_addr(3 downto 1))) <= sys_idata;
				end if;
				tst_ack <= '1';
			end if;
			if tst_req = '0' and tst_ack = '1' then
				tst_ack <= '0';
			end if;
		end if;
	end process;

	--
	-- PPI
	--
	PPI : e8255 port map(
		sys_clk => sys_clk,
		sys_rstn => sys_rstn,
		req => ppi_req,
		ack => ppi_ack,

		rw => sys_rw,
		addr => sys_addr(2 downto 1),
		idata => ppi_idata,
		odata => open,

		PAi => ppi_pai,
		PAo => ppi_pao,
		PAoe => ppi_paoe,
		PBi => ppi_pbi,
		PBo => ppi_pbo,
		PBoe => ppi_pboe,
		PCHi => ppi_pchi,
		PCHo => ppi_pcho,
		PCHoe => ppi_pchoe,
		PCLi => ppi_pcli,
		PCLo => ppi_pclo,
		PCLoe => ppi_pcloe
	);

	ppi_idata <= sys_idata(7 downto 0);

	ppi_pai <= (others => '1');
	ppi_pbi <= (others => '1');
	adpcm_clkdiv <= ppi_pclo(3 downto 2);
	adpcm_enL <= not ppi_pclo(0);
	adpcm_enR <= not ppi_pclo(1);

	--
	-- Sound
	--
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

	opm_idata <= sys_idata(7 downto 0);

	opm_pcmL <= opm_pcmLi(15) & opm_pcmLi(15) & opm_pcmLi(15 downto 2);
	opm_pcmR <= opm_pcmRi(15) & opm_pcmRi(15) & opm_pcmRi(15 downto 2);

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

	--	adpcm_pcmL <= (adpcm_pcmRaw(11) & adpcm_pcmRaw & "000") when adpcm_enL = '1' else (others => '0');
	--	adpcm_pcmR <= (adpcm_pcmRaw(11) & adpcm_pcmRaw & "000") when adpcm_enR = '1' else (others => '0');
	adpcm_pcmL <= (others => '0');
	adpcm_pcmR <= (others => '0');

	-- 16MHzの snd_clkから、ADPCMの 4MHz / 8MHzのタイミングを作るカウンタ
	process (snd_clk, sys_rstn)begin
		if (sys_rstn = '0') then
			adpcm_clkdiv_count <= 0;
			adpcm_sft <= '0';
		elsif (snd_clk' event and snd_clk = '1') then
			adpcm_sft <= '0';
			if (adpcm_clkdiv_count = 0) then
				adpcm_sft <= '1';
				if (adpcm_clkmode = '1') then
					adpcm_clkdiv_count <= 7; -- 4MHz
				else
					adpcm_clkdiv_count <= 3; -- 8MHz
				end if;
			else
				adpcm_clkdiv_count <= adpcm_clkdiv_count - 1;
			end if;
		end if;
	end process;

	--
	-- i2s sound
	--
	mix31L : addsat generic map(16) port map(snd_clk, opm_pcmL, adpcm_pcmL, snd_pcm_mix31L, open, open);
	mix31R : addsat generic map(16) port map(snd_clk, opm_pcmR, adpcm_pcmR, snd_pcm_mix31R, open, open);
	mix32L : addsat generic map(16) port map(snd_clk, mercury_pcm_pcmL, (others => '0'), snd_pcm_mix32L, open, open);
	mix32R : addsat generic map(16) port map(snd_clk, mercury_pcm_pcmR, (others => '0'), snd_pcm_mix32R, open, open);
	mix33L : addsat generic map(16) port map(snd_clk, mercury_pcm_fm0, mercury_pcm_ssg0, snd_pcm_mix33L, open, open);
	mix33R : addsat generic map(16) port map(snd_clk, mercury_pcm_fm0, mercury_pcm_ssg0, snd_pcm_mix33R, open, open);
	mix34L : addsat generic map(16) port map(snd_clk, mercury_pcm_fm1, mercury_pcm_ssg1, snd_pcm_mix34L, open, open);
	mix34R : addsat generic map(16) port map(snd_clk, mercury_pcm_fm1, mercury_pcm_ssg1, snd_pcm_mix34R, open, open);

	mix21L : addsat generic map(16) port map(snd_clk, snd_pcm_mix31L, snd_pcm_mix32L, snd_pcm_mix21L, open, open);
	mix21R : addsat generic map(16) port map(snd_clk, snd_pcm_mix31R, snd_pcm_mix32R, snd_pcm_mix21R, open, open);
	mix22L : addsat generic map(16) port map(snd_clk, snd_pcm_mix33L, snd_pcm_mix34L, snd_pcm_mix22L, open, open);
	mix22R : addsat generic map(16) port map(snd_clk, snd_pcm_mix33R, snd_pcm_mix34R, snd_pcm_mix22R, open, open);

	mixL : addsat generic map(16) port map(snd_clk, snd_pcm_mix21L, snd_pcm_mix22L, snd_pcmL, open, open);
	mixR : addsat generic map(16) port map(snd_clk, snd_pcm_mix21R, snd_pcm_mix22R, snd_pcmR, open, open);

	--pGPIO0(19) <= i2s_bclk; -- I2S BCK
	I2S : i2s_encoder port map(
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
	i2s_mclk <= pClk24M576;
	pGPIO0(16) <= i2s_mclk; -- I2S MCLK
	pGPIO0(17) <= i2s_data_out;
	pGPIO0(18) <= i2s_lrck;
	pGPIO0(19) <= i2s_bclk; -- I2S BCLK
	pGPIO0(20) <= 'Z';
	i2s_sndL(31 downto 16) <= snd_pcmL;
	i2s_sndR(31 downto 16) <= snd_pcmR;
	i2s_sndL(15 downto 0) <= (others => '0');
	i2s_sndR(15 downto 0) <= (others => '0');

	-- I2C Interface
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
		rstn => sys_rstn
	);
	pGPIO0_04 <= '0' when SCLOUT = '0' else 'Z';
	pGPIO0_09 <= '0' when SDAOUT = '0' else 'Z';
	process (sys_clk, sys_rstn)begin
		if (sys_rstn = '0') then
			SCLIN <= '1';
			SDAIN <= '1';
		elsif (sys_clk' event and sys_clk = '1') then
			SCLIN <= pGPIO0_04;
			SDAIN <= pGPIO0_09;
		end if;
	end process;

	I2CCLK : sftclk
	generic map(25000, 800, 1)
	port map(
		SEL => "0",
		SFT => I2CCLKEN,
		CLK => sys_clk,
		RSTN => sys_rstn
	);

	wm8804_inst : wm8804 port map(
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

		clk => sys_clk,
		rstn => sys_rstn
	);

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
		AUDIO_BIT_WIDTH => 16
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

	hdmi_rgb <= hdmi_test_r & hdmi_test_g & hdmi_test_b;
	hdmi_pcmclk <= i2s_lrck;
	hdmi_pcm(0) <= bclk_pcmL(31 downto 16);
	hdmi_pcm(1) <= bclk_pcmR(31 downto 16);

	--	hdmi_test_r <= hdmi_cx(5 downto 0) & "00";
	--	hdmi_test_g <= hdmi_cy(5 downto 0) & "00";
	--	hdmi_test_b <= hdmi_cy(8 downto 6) & hdmi_cx(8 downto 6) & "00";

	hdmi_test_r <=
		"11111111" when hdmi_cx(9 downto 7) = "000" and hdmi_cx(6 downto 0) = (snd_pcmL(15 downto 8) + 64) else
		"00111111" when hdmi_cx = 64 else
		"00000000" when hdmi_cx = 128 else
		"11111111" when hdmi_cx(9 downto 7) = "001" and hdmi_cx(6 downto 0) = (snd_pcmR(15 downto 8) + 64) else
		"00111111" when hdmi_cx = 192 else
		"00000000" when hdmi_cx = 256 else
		"11111111" when hdmi_cx(9 downto 7) = "010" and hdmi_cx(6 downto 0) = (adpcm_pcmRaw(11 downto 5) + 64) else
		"01111111" when hdmi_cx(9 downto 7) = "010" and adpcm_datemp = '1' else
		"01111111" when hdmi_cx(9 downto 7) = "010" and adpcm_datover = '1' else
		"00111111" when hdmi_cx = 320 else
		"00000000" when hdmi_cx = 384 else
		"11111111" when hdmi_cx(9 downto 7) = "011" and hdmi_cx(6 downto 0) = (snd_pcm_mix22L(15 downto 8) + 64) else
		"00111111" when hdmi_cx = 448 else
		"00000000" when hdmi_cx = 512 else
		"11111111" when hdmi_cx(9 downto 7) = "100" and hdmi_cx(6 downto 0) = (snd_pcm_mix22R(15 downto 8) + 64) else
		"00111111" when hdmi_cx = 576 else
		"00000000" when hdmi_cx = 640 else
		"00000000" when hdmi_cx(9 downto 7) = "101" or hdmi_cx(9 downto 8) = "11" else
		"00011111";
	hdmi_test_g <=
		"00000000" when hdmi_cx(9 downto 7) = "010" and adpcm_datemp = '1' else
		hdmi_test_r;
	hdmi_test_b <=
		"11111111" when mi68_bg = '1' else
		"00000000" when hdmi_cx(9 downto 7) = "010" and adpcm_datemp = '1' else
		hdmi_test_r;

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

		mi68_bg <= bg_line(7 - CONV_INTEGER(hdmi_cx(6 downto 4)));
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
		pcm_clk_12M288 => pcm_clk_12M288,
		pcm_clk_11M2896 => pcm_clk_11M2896,
		pcm_clk_8M => pcm_clk_8M,
		pcm_pcmL => mercury_pcm_pcmL,
		pcm_pcmR => mercury_pcm_pcmR,
		pcm_fm0 => mercury_pcm_fm0,
		pcm_ssg0 => mercury_pcm_ssg0,
		pcm_fm1 => mercury_pcm_fm1,
		pcm_ssg1 => mercury_pcm_ssg1
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
		sysclk => 25000,
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
		GPOE => open
	);
	midi_idata <= sys_idata(7 downto 0);
	pGPIO1(33) <= not midi_tx;
	midi_rx <= pGPIO1(32);
	pGPIO1(32) <= 'Z';

	--
	-- Expansion Memory
	--
	exmem : exmemory
	port map(
		sys_clk => sys_clk,
		sys_rstn => sys_rstn,
		req => exmem_req,
		ack => exmem_ack,

		rw => sys_rw,
		uds_n => sys_uds_n,
		lds_n => sys_lds_n,
		addr => sys_addr(23 downto 0),
		idata => exmem_idata,
		odata => exmem_odata,

		-- SDRAM SIDE
		sdram_clk => mem_clk,
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
	exmem_idata <= sys_idata(15 downto 0);

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
		elsif (sys_clk' event and sys_clk = '1') then
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