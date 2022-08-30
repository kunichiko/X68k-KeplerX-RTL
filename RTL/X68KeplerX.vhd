library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.STD_LOGIC_ARITH.all;
use IEEE.STD_LOGIC_UNSIGNED.all;
use work.X68KeplerX_pkg.all;

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

	signal x68clk10m : std_logic;

	signal pllrst : std_logic;
	signal plllock : std_logic;

	signal sys_clk : std_logic;
	signal sys_rstn : std_logic;

	component mainpll is
		port (
			areset : in std_logic := '0';
			inclk0 : in std_logic := '0';
			c0 : out std_logic; -- 25MHz
			c1 : out std_logic; -- 32MHz
			c2 : out std_logic; -- 125MHz
			locked : out std_logic
		);
	end component;

	component subpll is
		port (
			areset : in std_logic := '0';
			inclk0 : in std_logic := '0';
			c0 : out std_logic; -- 27MHz
			c1 : out std_logic; -- 153MHz
			locked : out std_logic
		);
	end component;

	signal led_counter_25m : std_logic_vector(23 downto 0);
	signal led_counter_10m : std_logic_vector(23 downto 0);

	--
	-- Sound
	--
	signal snd_clk : std_logic; -- internal sound operation clock (32MHz)
	signal snd_pcmL, snd_pcmR : std_logic_vector(15 downto 0);

	-- util
	component addsat
		generic (
			datwidth : integer := 16
		);
		port (
			INA : in std_logic_vector(datwidth - 1 downto 0);
			INB : in std_logic_vector(datwidth - 1 downto 0);
			INC : in std_logic_vector(datwidth - 1 downto 0);

			OUTQ : out std_logic_vector(datwidth - 1 downto 0);
			OFLOW : out std_logic;
			UFLOW : out std_logic
		);
	end component;

	signal i2s_pmclk_div : std_logic_vector(7 downto 0);
	signal i2s_pbclk_div : std_logic_vector(2 downto 0);
	signal i2s_pmclk : std_logic;
	signal i2s_pbclk : std_logic;

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

	signal i2s_bclk : std_logic; -- I2S BCLK
	signal i2s_lrck : std_logic; -- I2S LRCK
	signal i2s_sndL, i2s_sndR : std_logic_vector(31 downto 0);
	signal bclk_pcmL, bclk_pcmR : std_logic_vector(31 downto 0);

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
			pcmL : out std_logic_vector(15 downto 0);
			pcmR : out std_logic_vector(15 downto 0)
		);
	end component;

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
	signal mercury_pcmL : std_logic_vector(15 downto 0);
	signal mercury_pcmR : std_logic_vector(15 downto 0);

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

	--
	-- X68000 Bus Signals
	--
	signal i_as : std_logic;
	signal i_lds : std_logic;
	signal i_uds : std_logic;
	signal i_rw : std_logic;
	signal i_iack : std_logic;
	signal i_sdata : std_logic_vector(15 downto 0);
	signal o_dtack : std_logic;
	signal o_sdata : std_logic_vector(15 downto 0);
	signal o_irq : std_logic;
	signal o_drq : std_logic;
	type bus_state_t is(
	BS_IDLE,
	BS_S_ABIN_U,
	BS_S_ABIN_U2,
	BS_S_ABIN_U3,
	BS_S_ABIN_U_Z,
	BS_S_ABIN_L,
	BS_S_ABIN_L2,
	BS_S_ABIN_L3,
	BS_S_ABIN_L_Z,
	BS_S_DBIN,
	BS_S_DBIN2,
	BS_S_DBOUT_P,
	BS_S_DBOUT,
	BS_S_FIN_WAIT,
	BS_S_FIN_RD,
	BS_S_FIN,
	BS_S_IACK,
	BS_M_ABOUT_U,
	BS_M_ABOUT_L,
	BS_M_DBIN,
	BS_M_DBOUT
	);
	signal bus_state : bus_state_t;
	signal bus_mode : std_logic_vector(3 downto 0);

	signal as_d : std_logic;
	signal as_dd : std_logic;
	signal sys_addr : std_logic_vector(23 downto 0);
	signal sys_idata : std_logic_vector(15 downto 0);
	signal sys_rw : std_logic;
	signal sys_uds : std_logic;
	signal sys_lds : std_logic;
	signal sys_iack : std_logic;

begin

	pllrst <= not sys_rstn;
	mainpll_inst : mainpll port map(
		areset => pllrst,
		inclk0 => pClk50M,
		c0 => sys_clk, -- 25MHz
		c1 => snd_clk, -- 32MHz
		c2 => open,
		locked => plllock
	);

	subpll_inst : subpll port map(
		areset => pllrst,
		inclk0 => pClk50M,
		c0 => hdmi_clk, -- 27MHz
		c1 => hdmi_clk_x5, -- 135MHz
		locked => open
	);

	x68clk10m <= pGPIO1_IN(0);
	sys_rstn <= pGPIO1(31);

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

	-- test register
	-- X68000 Bus Access
	i_as <= pGPIO0(21);
	i_lds <= pGPIO0(22);
	i_uds <= pGPIO0(23);
	i_rw <= pGPIO0(24);
	i_iack <= pGPIO1(4);

	pGPIO0(27) <= 'Z' when o_dtack = '1' else '0';
	pGPIO0(28) <= 'Z' when o_drq = '1' else '0'; -- EXREQ
	pGPIO0(31) <= 'Z' when o_irq = '1' else '0';

	o_drq <= mercury_drq_n;
	--o_drq <= mercury_pcl;
	o_irq <= mercury_irq_n;

	bus_mode <=
		"0000" when bus_state = BS_IDLE else
		"0010" when bus_state = BS_S_ABIN_U else
		"0010" when bus_state = BS_S_ABIN_U2 else
		"0010" when bus_state = BS_S_ABIN_U3 else
		"0000" when bus_state = BS_S_ABIN_U_Z else
		"0011" when bus_state = BS_S_ABIN_L else
		"0011" when bus_state = BS_S_ABIN_L2 else
		"0011" when bus_state = BS_S_ABIN_L3 else
		"0000" when bus_state = BS_S_ABIN_L_Z else
		"0100" when bus_state = BS_S_DBIN else
		"0100" when bus_state = BS_S_DBIN2 else
		"0100" when bus_state = BS_S_FIN_WAIT and sys_rw = '0' else
		"0000" when bus_state = BS_S_FIN and sys_rw = '0' else
		"0000" when bus_state = BS_S_DBOUT_P else
		"0000" when bus_state = BS_S_FIN_WAIT and sys_rw = '1' else
		"0101" when bus_state = BS_S_FIN_RD else
		"0101" when bus_state = BS_S_FIN and sys_rw = '1' else
		"0000";
	pGPIO0(15) <= bus_mode(0);
	pGPIO0(14) <= bus_mode(1);
	pGPIO0(13) <= bus_mode(2);
	pGPIO0(12) <= bus_mode(3);

	i_sdata <= pGPIO1(21 downto 6);
	pGPIO1(21 downto 6) <= o_sdata when sys_rw = '1' and (bus_state = BS_S_FIN_WAIT or bus_state = BS_S_FIN_RD or bus_state = BS_S_FIN) else (others => 'Z');

	process (sys_clk, sys_rstn)
		variable cs : std_logic;
		variable fin : std_logic;
	begin
		if (sys_rstn = '0') then
			cs := '0';
			fin := '0';
			bus_state <= BS_IDLE;
			sys_addr <= (others => '0');
			sys_idata <= (others => '0');
			sys_rw <= '1';
			sys_uds <= '1';
			sys_lds <= '1';
			sys_iack <= '1';
			o_dtack <= '1';
			as_d <= '1';
			as_dd <= '1';
			tst_req <= '0';
			opm_req <= '0';
			adpcm_req <= '0';
			ppi_req <= '0';
		elsif (sys_clk' event and sys_clk = '1') then
			as_d <= i_as;
			as_dd <= as_d;
			o_dtack <= '1';

			case bus_state is
				when BS_IDLE =>
					tst_req <= '0';
					opm_req <= '0';
					adpcm_req <= '0';
					ppi_req <= '0';
					if (as_dd = '1' and as_d = '0') then
						-- falling edge
						bus_state <= BS_S_ABIN_U;
					end if;
				when BS_S_ABIN_U =>
					bus_state <= BS_S_ABIN_U2;
				when BS_S_ABIN_U2 =>
					bus_state <= BS_S_ABIN_U3;
				when BS_S_ABIN_U3 =>
					bus_state <= BS_S_ABIN_L;
					sys_addr(23 downto 16) <= i_sdata(7 downto 0);
					sys_rw <= i_rw;
					sys_uds <= i_uds;
					sys_lds <= i_lds;
					sys_iack <= i_iack;
				when BS_S_ABIN_L =>
					bus_state <= BS_S_ABIN_L2;
				when BS_S_ABIN_L2 =>
					bus_state <= BS_S_ABIN_L3;
				when BS_S_ABIN_L3 =>
					if (sys_uds = '1' and sys_lds = '0') then
						sys_addr(15 downto 0) <= i_sdata(15 downto 1) & "1";
					else
						sys_addr(15 downto 0) <= i_sdata(15 downto 1) & "0";
					end if;
					if (sys_iack = '0') then
						bus_state <= BS_S_IACK;
					elsif (sys_rw = '0') then
						bus_state <= BS_S_DBIN;
					else
						bus_state <= BS_S_DBOUT_P;
					end if;

					-- write cycle
				when BS_S_DBIN =>
					bus_state <= BS_S_DBIN2;
				when BS_S_DBIN2 =>
					sys_idata <= i_sdata;
					cs := '1';
					if (sys_addr(23 downto 12) = x"ecb") then -- test register
						tst_req <= '1';
					elsif (sys_addr(23 downto 2) = x"e9000" & "00") then -- OPM (YM2151)
						opm_req <= '1';
					elsif (sys_addr(23 downto 2) = x"e9200" & "00") and sys_lds = '0' then -- ADPCM (6258)
						adpcm_req <= '1';
					elsif (sys_addr(23 downto 4) = x"eafa0") then -- MIDI I/F
						midi_req <= '1';
					elsif (sys_addr(23 downto 3) = x"e9a00" & "0") and sys_lds = '0' then -- PPI (8255)
						ppi_req <= '1';
					elsif (sys_addr(23 downto 8) = x"ecc0") then -- Mercury Unit
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

					-- interrup acknowledge cycle
				when BS_S_IACK =>
					if (mercury_irq_n = '0') then
						o_sdata <= x"00" & mercury_int_vec;
					elsif (midi_irq_n = '0') then
						o_sdata <= x"00" & midi_int_vec;
					else
						o_sdata <= (others => '0');
					end if;
					bus_state <= BS_S_FIN_RD;

					-- read cycle
				when BS_S_DBOUT_P =>
					cs := '1';
					if (sys_addr(23 downto 12) = x"ecb") then -- test register
						tst_req <= '1';
					elsif (sys_addr(23 downto 2) = x"e9000" & "00") then -- OPM (YM2151)
						-- ignore read cycle
						opm_req <= '0';
						cs := '0';
					elsif (sys_addr(23 downto 2) = x"e9200" & "00") then -- ADPCM (6258)
						-- ignore read cycle
						adpcm_req <= '0';
						cs := '0';
					elsif (sys_addr(23 downto 4) = x"eafa0") then -- MIDI I/F
						midi_req <= '1';
					elsif (sys_addr(23 downto 3) = x"e9a00" & "0") then -- PPI (8255)
						-- ignore read cycle
						ppi_req <= '0';
						cs := '0';
					elsif (sys_addr(23 downto 8) = x"ecc0") then -- Mercury Unit
						-- 0xecc000〜0xecdfff
						mercury_req <= '1';
					else
						cs := '0';
					end if;

					if cs = '1' then
						bus_state <= BS_S_FIN_WAIT;
					else
						bus_state <= BS_IDLE;
					end if;

					-- finish
				when BS_S_FIN_WAIT =>
					fin := '0';
					if tst_req = '1' then
						o_sdata <= test_reg(conv_integer(sys_addr(3 downto 1)));
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
					bus_state <= BS_S_FIN;

				when BS_S_FIN =>
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

	adpcm_pcmL <= (adpcm_pcmRaw(11) & adpcm_pcmRaw & "000") when adpcm_enL = '1' else (others => '0');
	adpcm_pcmR <= (adpcm_pcmRaw(11) & adpcm_pcmRaw & "000") when adpcm_enR = '1' else (others => '0');

	-- 32MHzの snd_clkから、ADPCMの 4MHz / 8MHzのタイミングを作るカウンタ
	process (snd_clk, sys_rstn)begin
		if (sys_rstn = '0') then
			adpcm_clkdiv_count <= 0;
			adpcm_sft <= '0';
		elsif (snd_clk' event and snd_clk = '1') then
			adpcm_sft <= '0';
			if (adpcm_clkdiv_count > 0) then
				adpcm_clkdiv_count <= adpcm_clkdiv_count - 1;
			else
				adpcm_sft <= '1';
				if (adpcm_clkmode = '1') then
					adpcm_clkdiv_count <= 7; -- 4MHz
				else
					adpcm_clkdiv_count <= 3; -- 8MHz
				end if;
			end if;
		end if;
	end process;

	-- i2s sound
	mixL : addsat generic map(16) port map(opm_pcmL, adpcm_pcmL, mercury_pcmL, snd_pcmL, open, open);
	mixR : addsat generic map(16) port map(opm_pcmR, adpcm_pcmR, mercury_pcmR, snd_pcmR, open, open);

	--pGPIO0(19) <= i2s_bclk; -- I2S BCK
	I2S : i2s_encoder port map(
		snd_clk => snd_clk,
		snd_pcmL => i2s_sndL,
		snd_pcmR => i2s_sndR,

		i2s_data => pGPIO0(17), -- I2S DATA
		i2s_lrck => i2s_lrck, -- I2S LRCK

		--i2s_bclk => i2s_bclk, -- I2S BCK (4MHz for 62.5kHz)
		i2s_bclk => i2s_pbclk, -- 3.076MHz (about 3.072 MHz)
		bclk_pcmL => bclk_pcmL,
		bclk_pcmR => bclk_pcmR,

		rstn => sys_rstn
	);

	pGPIO0(18) <= i2s_lrck;
	pGPIO0(19) <= i2s_pbclk; -- I2S Pseudo BCK
	pGPIO0(20) <= i2s_pmclk; -- I2S Pseudo MCK
	i2s_sndL(31 downto 16) <= snd_pcmL;
	i2s_sndR(31 downto 16) <= snd_pcmR;
	i2s_sndL(15 downto 0) <= (others => '0');
	i2s_sndL(15 downto 0) <= (others => '0');

	--
	-- 50MHzで128クロック中 63回上下させることで約24.609Mhzのクロックを生成し、
	-- 24.576MHzの代わりにする実験
	--
	process (pClk50M, sys_rstn)begin
		if (sys_rstn = '0') then
			i2s_pmclk_div <= (others => '0');
			i2s_pmclk <= '1';
		elsif (pClk50M' event and pClk50M = '1') then
			if (i2s_pmclk_div = 127) then
				i2s_pmclk_div <= (others => '0');
				i2s_pmclk <= '1';
			else
				i2s_pmclk_div <= i2s_pmclk_div + 1;
			end if;
			if ((i2s_pmclk_div = 0) or (i2s_pmclk_div = 64)) then
				--			if ((i2s_pmclk_div = 0) or (i2s_pmclk_div = 42) or (i2s_pmclk_div = 85)) then
				i2s_pmclk <= i2s_pmclk;
			else
				i2s_pmclk <= not i2s_pmclk;
			end if;
		end if;
	end process;

	process (i2s_pmclk, sys_rstn)begin
		if (sys_rstn = '0') then
			i2s_pbclk_div <= (others => '0');
		elsif (i2s_pmclk' event and i2s_pmclk = '1') then
			if (i2s_pbclk_div = 7) then
				i2s_pbclk_div <= (others => '0');
			else
				i2s_pbclk_div <= i2s_pbclk_div + 1;
			end if;
		end if;
	end process;

	i2s_pbclk <= i2s_pbclk_div(2);

	--
	-- HDMI
	--
	hdmi0 : hdmi
	generic map(
		VIDEO_ID_CODE => 2,
		BIT_WIDTH => 10,
		BIT_HEIGHT => 10,
		VIDEO_REFRESH_RATE => 59.94,
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
		"11111111" when hdmi_cx(9 downto 8) = "00" and hdmi_cx(7 downto 0) = (snd_pcmL(15 downto 8) + 128) else
		"00111111" when hdmi_cx = 128 else
		"00000000" when hdmi_cx = 256 else
		"11111111" when hdmi_cx(9 downto 8) = "01" and hdmi_cx(7 downto 0) = (snd_pcmR(15 downto 8) + 128) else
		"00111111" when hdmi_cx = 384 else
		"00000000" when hdmi_cx = 512 else
		"11111111" when hdmi_cx(9 downto 7) = "100" and hdmi_cx(6 downto 0) = (adpcm_pcmRaw(11 downto 5) + 64) else
		"00111111" when hdmi_cx = 576 else
		"01111111" when hdmi_cx(9 downto 7) = "100" and adpcm_datemp = '1' else
		"01111111" when hdmi_cx(9 downto 7) = "100" and adpcm_datover = '1' else
		"00000000" when hdmi_cx(9 downto 7) = "101" or hdmi_cx(9 downto 8) = "11" else
		"00011111";
	hdmi_test_g <=
		"00000000" when hdmi_cx(9 downto 7) = "100" and adpcm_datemp = '1' else
		hdmi_test_r;
	hdmi_test_b <=
		"00000000" when hdmi_cx(9 downto 7) = "100" and adpcm_datemp = '1' else
		hdmi_test_r;

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
		pcmL => mercury_pcmL,
		pcmR => mercury_pcmR
	);

	mercury_idata <= sys_idata;
	mercury_dack_n <= pGPIO1(3);

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

		RxD => '1',
		TxD => pGPIO1(33),
		RxF => '1',
		TxF => open,
		SYNC => open,
		CLICK => open,
		GPOUT => open,
		GPIN => (others => '1'),
		GPOE => open
	);
	midi_idata <= sys_idata(7 downto 0);

end rtl;