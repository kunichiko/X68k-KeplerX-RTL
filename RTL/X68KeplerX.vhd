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

	signal x68clk10m : std_logic;

	signal pllrst : std_logic;
	signal plllock : std_logic;

	signal sys_clk : std_logic;
	signal sys_rstn : std_logic;

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

	-- Sound
	signal snd_clk : std_logic; -- internal sound operation clock (32MHz)
	signal snd_pcmL, snd_pcmR : std_logic_vector(15 downto 0);

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

	signal opm_pcmL : std_logic_vector(15 downto 0);
	signal opm_pcmR : std_logic_vector(15 downto 0);

	-- i2s sound

	component i2s_encoder
		port (
			snd_clk : in std_logic;
			snd_pcmL : in std_logic_vector(31 downto 0);
			snd_pcmR : in std_logic_vector(31 downto 0);

			i2s_data : out std_logic;
			i2s_lrck : out std_logic;

			i2s_bclk : in std_logic; -- I2S BCK (Bit Clock) 3.072MHz (=48kHz * 64)
			rstn : in std_logic
		);
	end component;

	signal i2s_bclk : std_logic; -- I2C BCK 
	signal i2s_sndL, i2s_sndR : std_logic_vector(31 downto 0);

	-- test register
	signal tst_req : std_logic;
	signal tst_ack : std_logic;
	signal reg0 : std_logic_vector(15 downto 0);

	-- X68000 Bus Signals
	signal i_as : std_logic;
	signal i_lds : std_logic;
	signal i_uds : std_logic;
	signal i_rw : std_logic;
	signal i_sdata : std_logic_vector(15 downto 0);
	signal o_dtack : std_logic;
	signal o_sdata : std_logic_vector(15 downto 0);
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
	BS_S_FIN,
	BS_M_ABOUT_U,
	BS_M_ABOUT_L,
	BS_M_DBIN,
	BS_M_DBOUT
	);
	signal bus_state : bus_state_t;
	signal bus_mode : std_logic_vector(3 downto 0);

	signal as_d : std_logic;
	signal as_dd : std_logic;
	signal addr : std_logic_vector(23 downto 0);

begin

	pllrst <= not sys_rstn;
	mainpll_inst : mainpll port map(
		areset => pllrst,
		inclk0 => pClk50M,
		c0 => sys_clk,
		c1 => snd_clk,
		c2 => i2s_bclk,
		locked => plllock
	);

	x68clk10m <= pGPIO1_IN(0);
	sys_rstn <= pGPIO1_IN(1);

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

	pGPIO0(27) <= 'Z' when o_dtack = '1' else '0';

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
		"0100" when bus_state = BS_S_FIN_WAIT and i_rw = '1' else
		"0000" when bus_state = BS_S_FIN and i_rw = '1' else
		"0000" when bus_state = BS_S_DBOUT_P else
		"0101" when bus_state = BS_S_FIN_WAIT and i_rw = '0' else
		"0101" when bus_state = BS_S_FIN and i_rw = '0' else
		"0000";
	pGPIO0(15) <= bus_mode(0);
	pGPIO0(14) <= bus_mode(1);
	pGPIO0(13) <= bus_mode(2);
	pGPIO0(12) <= bus_mode(3);

	i_sdata <= pGPIO1(21 downto 6);
	pGPIO1(21 downto 6) <= o_sdata when i_rw = '0' and (bus_state = BS_S_FIN_WAIT or bus_state = BS_S_FIN) else (others => 'Z');

	process (sys_clk, sys_rstn)
		variable cs : std_logic;
		variable fin : std_logic;
	begin
		if (sys_rstn = '0') then
			cs := '0';
			fin := '0';
			bus_state <= BS_IDLE;
			addr <= (others => '0');
			o_dtack <= '1';
			as_d <= '1';
			as_dd <= '1';
			tst_req <= '0';
			opm_req <= '0';
		elsif (sys_clk' event and sys_clk = '1') then
			as_d <= i_as;
			as_dd <= as_d;
			o_dtack <= '1';

			case bus_state is
				when BS_IDLE =>
					tst_req <= '0';
					opm_req <= '0';
					if (as_dd = '1' and as_d = '0') then
						-- falling edge
						bus_state <= BS_S_ABIN_U;
					end if;
				when BS_S_ABIN_U =>
					bus_state <= BS_S_ABIN_U2;
				when BS_S_ABIN_U2 =>
					bus_state <= BS_S_ABIN_U3;
				when BS_S_ABIN_U3 =>
					bus_state <= BS_S_ABIN_U_Z;
					addr(23 downto 16) <= i_sdata(7 downto 0);
				when BS_S_ABIN_U_Z =>
					bus_state <= BS_S_ABIN_L;
				when BS_S_ABIN_L =>
					bus_state <= BS_S_ABIN_L2;
				when BS_S_ABIN_L2 =>
					bus_state <= BS_S_ABIN_L3;
				when BS_S_ABIN_L3 =>
					bus_state <= BS_S_ABIN_L_Z;
					addr(15 downto 0) <= i_sdata(15 downto 1) & "0";
				when BS_S_ABIN_L_Z =>
					if (i_rw = '0') then
						bus_state <= BS_S_DBIN;
					else
						bus_state <= BS_S_DBOUT_P;
					end if;

					-- write cycle
				when BS_S_DBIN =>
					bus_state <= BS_S_DBIN2;
				when BS_S_DBIN2 =>
					cs := '1';
					if (addr(23 downto 12) = x"ec1") then -- test register
						tst_req <= '1';
					elsif (addr(23 downto 2) = x"e9000" & "00") then -- OPM (YM2151)
						opm_req <= '1';
					else
						cs := '0';
					end if;

					if cs = '1' then
						bus_state <= BS_S_FIN_WAIT;
					else
						bus_state <= BS_IDLE;
					end if;

					-- read cycle
				when BS_S_DBOUT_P =>
					cs := '1';
					if (addr(23 downto 12) = x"ec1") then -- test register
						tst_req <= '1';
					elsif (addr(23 downto 2) = x"e9000" & "00") then -- OPM (YM2151)
						-- ignore read cycle
						opm_req <= '0';
						cs := '0';
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
					if tst_req = '1' and tst_ack = '1' then
						o_sdata <= reg0;
						tst_req <= '0';
						fin := '1';
					elsif opm_req = '1' and opm_ack = '1' then
						o_sdata <= (others => '0');
						opm_req <= '0';
						if i_rw = '0' then
							bus_state <= BS_IDLE; -- write access ignore
						else
							fin := '1';
						end if;
					else
						fin := '0';
					end if;

					if fin = '1' then
						bus_state <= BS_S_FIN;
					end if;
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
				if i_rw = '1' then
					reg0 <= i_sdata;
				end if;
				tst_ack <= '1';
			end if;
			if tst_req = '0' and tst_ack = '1' then
				tst_ack <= '0';
			end if;
		end if;
	end process;
	--
	-- Sound
	--
	snd_pcmL <= opm_pcmL;
	snd_pcmR <= opm_pcmR;
	opm_idata <= i_sdata(7 downto 0);

	OPM : OPM_JT51 port map(
		sys_clk => sys_clk,
		sys_rstn => sys_rstn,
		req => opm_req,
		ack => opm_ack,

		rw => i_rw,
		addr => addr(1),
		idata => opm_idata,
		odata => opm_odata,

		irqn => open,

		-- specific i/o
		snd_clk => snd_clk,
		pcmL => opm_pcmL,
		pcmR => opm_pcmR,

		CT1 => open,
		CT2 => open
	);

	-- i2s sound
	pGPIO0(19) <= i2s_bclk; -- I2S BCK
	i2s_sndL(31 downto 16) <= snd_pcmL;
	i2s_sndR(31 downto 16) <= snd_pcmR;
	i2s_sndL(15 downto 0) <= (others => '0');
	i2s_sndL(15 downto 0) <= (others => '0');

	I2S : i2s_encoder port map(
		snd_clk => snd_clk,
		snd_pcmL => i2s_sndL,
		snd_pcmR => i2s_sndR,

		i2s_data => pGPIO0(17), -- I2S DATA
		i2s_lrck => pGPIO0(18), -- I2S LRCK

		i2s_bclk => i2s_bclk, -- I2S BCK (4MHz = 62.5kHz)
		rstn => sys_rstn
	);
end rtl;