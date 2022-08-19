library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.STD_LOGIC_UNSIGNED.all;

entity e6258 is
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

		snd_clk : in std_logic;
		pcm : out std_logic_vector(11 downto 0)
	);
end e6258;

architecture rtl of e6258 is
	component calcadpcm
		port (
			playen : in std_logic;
			datin : in std_logic_vector(3 downto 0);
			datemp : in std_logic;
			datwr : in std_logic;

			datout : out std_logic_vector(11 downto 0);

			clkdiv : in std_logic_vector(1 downto 0);
			sft : in std_logic;
			clk : in std_logic;
			rstn : in std_logic
		);

	end component;

	signal nxtbuf0, nxtbuf1 : std_logic_vector(3 downto 0);
	signal bufcount : integer range 0 to 2;
	signal sftcount : integer range 0 to 5;
	signal divcount : integer range 0 to 255;
	signal playen : std_logic;
	signal recen : std_logic;
	signal playwr : std_logic;
	signal datuse : std_logic;
	signal playdat : std_logic_vector(3 downto 0);
	signal datemp : std_logic;
	signal calcsft : std_logic;
	signal idatabuf : std_logic_vector(7 downto 0);
	signal addrbuf : std_logic;

	type state_t is(
	IDLE,
	WR_REQ,
	WR_WAIT,
	WR_ACK,
	RD_REQ,
	RD_WAIT,
	RD_ACK
	);
	signal state : state_t;

	signal datwr : std_logic;
begin

	-- sysclk synchronized inputs
	process (sys_clk, sys_rstn)
	begin
		if (sys_rstn = '0') then
			idatabuf <= (others => '0');
			addrbuf <= '0';
			--
			ack <= '0';
			datwr <= '1';
		elsif (sys_clk' event and sys_clk = '1') then
			ack <= '0';
			case state is
				when IDLE =>
					if req = '1' then
						if rw = '0' then
							state <= WR_REQ;
							idatabuf <= idata;
							addrbuf <= addr;
							datwr <= '0';
							--						else
							--							state <= RD_REQ;
						end if;
					end if;

					-- write cycle
				when WR_REQ =>
					state <= WR_WAIT;
				when WR_WAIT =>
					datwr <= '1';
					state <= WR_ACK;
					ack <= '1';
				when WR_ACK =>
					if req = '1' then
						ack <= '1';
					else
						ack <= '0';
						state <= IDLE;
					end if;

					-- read cycle
				when RD_REQ =>
					state <= RD_WAIT;
				when RD_WAIT =>
					state <= RD_ACK;
					ack <= '1';
				when RD_ACK =>
					if req = '1' then
						ack <= '1';
					else
						ack <= '0';
						state <= IDLE;
					end if;
				when others =>
					state <= IDLE;
			end case;
		end if;
	end process;

	process (sys_clk, sys_rstn)
	begin
		if (sys_rstn = '0') then
			idatabuf <= (others => '0');
			addrbuf <= '0';
		elsif (sys_clk' event and sys_clk = '1') then
			if (datwr = '1') then
				idatabuf <= idata;
				addrbuf <= addr;
			end if;
		end if;
	end process;

	process (snd_clk, sys_rstn)
		variable ldatwr : std_logic_vector(1 downto 0);
	begin
		if (sys_rstn = '0') then
			playen <= '0';
			recen <= '0';
			bufcount <= 0;
			nxtbuf0 <= (others => '0');
			nxtbuf1 <= (others => '0');
			drq <= '0';
			ldatwr := "00";
		elsif (snd_clk' event and snd_clk = '1') then
			if (datwr = '1') then
				drq <= '0';
			elsif (ldatwr = "10") then
				if (addrbuf = '0') then
					if (idatabuf(1) = '1') then
						playen <= '1';
					elsif (idatabuf(2) = '1') then
						recen <= '1';
					elsif (idatabuf(0) = '1') then
						playen <= '0';
						recen <= '0';
					end if;
				else
					nxtbuf1 <= idatabuf(7 downto 4);
					nxtbuf0 <= idatabuf(3 downto 0);
					bufcount <= 2;
				end if;
			end if;
			if (datuse = '1') then
				nxtbuf0 <= nxtbuf1;
				nxtbuf1 <= (others => '0');
				if (bufcount > 0) then
					bufcount <= bufcount - 1;
				end if;
				if (bufcount <= 1) then
					drq <= '1';
				end if;
			end if;
			ldatwr := ldatwr(0) & datwr;
		end if;
	end process;

	process (snd_clk, sys_rstn)begin
		if (sys_rstn = '0') then
			playdat <= (others => '0');
			playwr <= '0';
			divcount <= 0;
			datuse <= '0';
			calcsft <= '0';
			sftcount <= 0;
		elsif (snd_clk' event and snd_clk = '1') then
			playwr <= '0';
			datuse <= '0';
			calcsft <= '0';
			if (playen = '1' and sft = '1') then
				if (sftcount > 0) then
					sftcount <= sftcount - 1;
				else
					if (clkdiv = "01") then
						sftcount <= 5;
					else
						sftcount <= 3;
					end if;
					calcsft <= '1';
					if (divcount = 0) then
						playdat <= nxtbuf0;
						if (bufcount = 0) then
							datemp <= '1';
						else
							datemp <= '0';
						end if;
						playwr <= '1';
						datuse <= '1';
						case clkdiv is
							when "00" =>
								divcount <= 255;
							when "01" =>
								divcount <= 127;
							when "10" =>
								divcount <= 127;
							when others =>
								divcount <= 0; --for debug
						end case;
					else
						divcount <= divcount - 1;
					end if;
				end if;
			end if;
		end if;
	end process;

	adpcm : calcadpcm port map(
		playen => playen,
		datin => playdat,
		datemp => datemp,
		datwr => playwr,

		datout => pcm,

		clkdiv => clkdiv,
		sft => calcsft,
		clk => snd_clk,
		rstn => sys_rstn
	);

	odata <= (playen or recen) & '1' & "000000" when addr = '0' else
		(others => '0');
end rtl;