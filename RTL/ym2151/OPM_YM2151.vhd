--
--  OPM_YM2151.vhd
--
--    Author Kunihiko Ohnaka
--
library IEEE;

use IEEE.STD_LOGIC_1164.all;
use IEEE.STD_LOGIC_ARITH.all;
use IEEE.STD_LOGIC_UNSIGNED.all;

-- KeplerX から YM2151日チップを使用するためのコンポーネントです

entity OPM_YM2151 is
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
end OPM_YM2151;

architecture rtl of OPM_YM2151 is
	component EM3012
		port (
			CLK_PHY1 : in std_logic; -- Phy0 clock 2MHz divided by YM2151
			SDATA : in std_logic;
			SAM_HOLD1 : in std_logic;
			SAM_HOLD2 : in std_logic;

			-- sytem side
			sndL : out std_logic_vector(15 downto 0);
			sndR : out std_logic_vector(15 downto 0);

			snd_clk : in std_logic; -- 16MHz
			sys_rstn : in std_logic
		);
	end component;
	signal em3012_sndL : std_logic_vector(15 downto 0);
	signal em3012_sndR : std_logic_vector(15 downto 0);

	--
	signal opm_clk_divider : std_logic_vector(1 downto 0); -- 16MHz → 4MHz
	signal ack_snd : std_logic;
	signal req_d : std_logic;
	signal req_dd : std_logic;
	signal addr_d : std_logic;
	signal data_d : std_logic_vector(7 downto 0);

	type state_t is(
	IDLE,
	WR_WAIT1,
	WR_WAIT2,
	WR_WAIT3,
	WR_WAIT4,
	WR_END
	);
	signal state : state_t;

	-- write fifo
	constant fifosizew : integer := 3; -- ビット数
	constant fifosize : integer := 2 ** fifosizew; -- FIFOの長さ
	type fifo is array (fifosize - 1 downto 0) of std_logic_vector(8 downto 0);
	signal writefifo : fifo;
	signal writefifo_r, writefifo_w : integer range 0 to fifosize - 1;
	signal writefifo_count : std_logic_vector(fifosizew - 1 downto 0);
	signal write_wait_count : std_logic_vector(8 downto 0);

begin
	-- snd_clk 16MHz -> fmclk 4mhz
	-- (On X68000, YM2151 is driven by 4MHz)
	process (snd_clk, sys_rstn)begin
		if (sys_rstn = '0') then
			opm_clk_divider <= (others => '0');
		elsif (snd_clk' event and snd_clk = '1') then
			opm_clk_divider <= opm_clk_divider + 1;
		end if;
	end process;

	OPM_PHYM <= opm_clk_divider(1);
	OPM_IC_n <= sys_rstn;

	em3012_0 : EM3012 port map(
		CLK_PHY1 => OPM_PHY1,
		SDATA => OPM_SDATA,
		SAM_HOLD1 => OPM_SH1,
		SAM_HOLD2 => OPM_SH2,

		-- system side
		sndL => em3012_sndL,
		sndR => em3012_sndR,

		snd_clk => snd_clk,
		sys_rstn => sys_rstn
	);

	-- snd_clk(sndclk) synchronized signals (can be connected directly)
	pcmL <= em3012_sndL(15 downto 0);
	pcmR <= em3012_sndR(15 downto 0);

	-- sysclk synchronized inputs
	process (sys_clk, sys_rstn)
	begin
		if (sys_rstn = '0') then
			ack <= '0';
		elsif (sys_clk' event and sys_clk = '1') then
			ack <= ack_snd;
		end if;
	end process;

	-- snd_clk synchronized
	writefifo_count <= conv_std_logic_vector(writefifo_w, fifosizew) - conv_std_logic_vector(writefifo_r, fifosizew);

	process (snd_clk, sys_rstn)begin
		if (sys_rstn = '0') then
			OPM_WR_n <= '1';
			OPM_A0 <= '0';
			OPM_DATA <= (others => '0');
			state <= IDLE;
			req_d <= '0';
			req_dd <= '0';
			addr_d <= '0';
			data_d <= (others => '0');
			ack_snd <= '0';
			--
			writefifo_r <= 0;
			writefifo_w <= 0;
			write_wait_count <= (others => '0');
		elsif (snd_clk' event and snd_clk = '1') then
			req_d <= req;
			req_dd <= req_d;
			addr_d <= addr;
			data_d <= idata;
			ack_snd <= '0';
			if req_dd = '0' and req_d = '1' then
				if rw = '0' then
					-- write to fifo
					ack_snd <= '1';
					if (writefifo_count <= fifosize - 1) then
						writefifo(writefifo_w) <= addr_d & data_d;
						writefifo_w <= writefifo_w + 1;
					end if;
				else
					-- write にしか応答しない
					null;
				end if;
			end if;

			case state is
				when IDLE =>
					if ((writefifo_count > 0) and (write_wait_count = 0)) then
						OPM_WR_n <= '1';
						OPM_A0 <= writefifo(writefifo_r)(8);
						OPM_DATA <= writefifo(writefifo_r)(7 downto 0);
						writefifo_r <= writefifo_r + 1;
						write_wait_count <= conv_std_logic_vector(31,9); -- 31 clocks delay for next write
						--write_wait_count <= "111111"; -- 63 clocks delay for next write
						--if (writefifo(writefifo_r)(8) = '0') then
						--	write_wait_count <= conv_std_logic_vector(68,9); -- 17 clocks@4MHz delay for next write
						--else
						--	write_wait_count <= conv_std_logic_vector(332,9); -- 83 clocks@4MHz delay for next write
						--end if;
						state <= WR_WAIT1;
					else
						if (write_wait_count > 0) then
							write_wait_count <= write_wait_count - 1;
						end if;
					end if;

					-- write cycle
				when WR_WAIT1 =>
					OPM_WR_n <= '0';
					state <= WR_WAIT2;
				when WR_WAIT2 =>
					state <= WR_WAIT3;
				when WR_WAIT3 =>
					state <= WR_WAIT4;
				when WR_WAIT4 =>
					state <= WR_END;
				when WR_END =>
					OPM_WR_n <= '1';
					ack_snd <= '1';
					state <= IDLE;
				when others =>
					state <= IDLE;
			end case;

		end if;
	end process;

end rtl;