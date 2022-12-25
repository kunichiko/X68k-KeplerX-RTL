library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.STD_LOGIC_UNSIGNED.all;
use IEEE.STD_LOGIC_ARITH.all;

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

		drq : out std_logic; -- DMAリクエスト: Kepler-Xでは使わない（本体のADPCMがやるため）

		-- specific i/o
		clkdiv : in std_logic_vector(1 downto 0);
		sft : in std_logic;
		adpcm_datemp : out std_logic;
		adpcm_datover : out std_logic;

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

	constant fifosizew : integer := 2; -- ビット数
	constant fifosize : integer := 2 ** fifosizew; -- FIFOの長さ
	type adpcmbuf is array (fifosize - 1 downto 0) of std_logic_vector(3 downto 0);
	signal nxtbuf : adpcmbuf;
	signal nxtbuf_r, nxtbuf_w : integer range 0 to fifosize - 1;
	signal bufcount : std_logic_vector(fifosizew - 1 downto 0);

	signal clkdiv_d : std_logic_vector(1 downto 0);
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

	signal datwr_req : std_logic;
	signal datwr_req_d : std_logic;
	signal datwr_ack : std_logic;
begin

	-- sysclk synchronized inputs
	process (sys_clk, sys_rstn)
	begin
		if (sys_rstn = '0') then
			idatabuf <= (others => '0');
			addrbuf <= '0';
			--
			ack <= '0';
			datwr_req <= '0';
		elsif (sys_clk' event and sys_clk = '1') then
			ack <= '0';
			case state is
				when IDLE =>
					if req = '1' then
						if rw = '0' then
							state <= WR_REQ;
							idatabuf <= idata;
							addrbuf <= addr;
							datwr_req <= not datwr_req;
							--						else
							--							state <= RD_REQ;
						end if;
					end if;

					-- write cycle
				when WR_REQ =>
					state <= WR_WAIT;
				when WR_WAIT =>
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

	bufcount <= conv_std_logic_vector(nxtbuf_w, fifosizew) - conv_std_logic_vector(nxtbuf_r, fifosizew);

	process (snd_clk, sys_rstn)
	begin
		if (sys_rstn = '0') then
			playen <= '0';
			recen <= '0';
			nxtbuf <= (others => (others => '0'));
			nxtbuf_r <= 0;
			nxtbuf_w <= 0;
			drq <= '0';
			datwr_req_d <= '0';
			datwr_ack <= '0';
			adpcm_datover <= '0';
		elsif (snd_clk' event and snd_clk = '1') then
			datwr_req_d <= datwr_req;
			if (datwr_req_d /= datwr_ack) then
				datwr_ack <= datwr_req_d;
				if (addrbuf = '0') then
					-- Command
					if (idatabuf(1) = '1') then
						playen <= '1';
					elsif (idatabuf(2) = '1') then
						recen <= '1';
					elsif (idatabuf(0) = '1') then
						playen <= '0';
						recen <= '0';
					end if;
				else
					-- Data
					if (bufcount <= fifosize - 2) then
						nxtbuf(nxtbuf_w) <= idatabuf(3 downto 0);
						nxtbuf(nxtbuf_w + 1) <= idatabuf(7 downto 4);
						nxtbuf_w <= nxtbuf_w + 2;
						adpcm_datover <= '0';
					else
						-- 間に合わなかったら最後の2データを上書きする
						-- 一部この方が良いゲームがあるが原因がわからない
						-- PCM8をかますと綺麗に聞こえたりするので、レジスタ書き込みタイミングはまだ要調整
						nxtbuf(nxtbuf_w - 1) <= idatabuf(3 downto 0);
						nxtbuf(nxtbuf_w + 0) <= idatabuf(7 downto 4);
						adpcm_datover <= '1';
					end if;
				end if;
			else
				drq <= '0';
			end if;
			if (datuse = '1') then
				if (bufcount > 0) then
					nxtbuf_r <= nxtbuf_r + 1;
				end if;
				if (bufcount <= 1) then
					drq <= '1';
				end if;
			end if;
		end if;
	end process;

	process (snd_clk, sys_rstn)begin
		if (sys_rstn = '0') then
			clkdiv_d <= (others => '0');
			playdat <= (others => '0');
			playwr <= '0';
			divcount <= 0;
			datuse <= '0';
			calcsft <= '0';
			sftcount <= 0;
		elsif (snd_clk' event and snd_clk = '1') then
			clkdiv_d <= clkdiv;
			playwr <= '0';
			datuse <= '0';
			calcsft <= '0';
			if (playen = '1' and sft = '1') then
				-- 8MHz (max)
				if (sftcount > 0) then
					sftcount <= sftcount - 1;
				else
					-- 2MHz (max)
					if (clkdiv_d = "01") then
						sftcount <= 5;
					else
						sftcount <= 3;
					end if;
					calcsft <= '1';
					if (divcount = 0) then
						-- 15.6kHz (max)
						playdat <= nxtbuf(nxtbuf_r);
						if (bufcount = 0) then
							-- バッファが足りていない場合は calcadpcmにそのことを伝える
							datemp <= '1';
						else
							datemp <= '0';
						end if;
						playwr <= '1';
						datuse <= '1';
						case clkdiv_d is
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

		clkdiv => clkdiv_d,
		sft => calcsft,
		clk => snd_clk,
		rstn => sys_rstn
	);

	odata <= (playen or recen) & '1' & "000000" when addr = '0' else (others => '0');

	adpcm_datemp <= datemp;
end rtl;