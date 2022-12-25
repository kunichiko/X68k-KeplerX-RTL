--
--  OPM_JT51.vhd
--
--    Author Kunihiko Ohnaka
--
library IEEE;

use IEEE.STD_LOGIC_1164.all;
use IEEE.STD_LOGIC_ARITH.all;
use IEEE.STD_LOGIC_UNSIGNED.all;

-- KeplerX から JT51を使用するためのコンポーネントです

entity OPM_JT51 is
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
end OPM_JT51;

architecture rtl of OPM_JT51 is

	-- JT51 Verilog module definition is below:
	--
	-- module jt51(
	--    input               rst,    // reset
	--    input               clk,    // main clock
	--    input               cen,    // clock enable
	--    input               cen_p1, // clock enable at half the speed
	--    input               cs_n,   // chip select
	--    input               wr_n,   // write
	--    input               a0,
	--    input       [7:0]   din, // data in
	--    output      [7:0]   dout, // data out
	--    // peripheral control
	--    output              ct1,
	--    output              ct2,
	--    output              irq_n,  // I do not synchronize this signal
	--    // Low resolution output (same as real chip)
	--    output              sample, // marks new output sample
	--    output  signed  [15:0] left,
	--    output  signed  [15:0] right,
	--    // Full resolution output
	--    output  signed  [15:0] xleft,
	--    output  signed  [15:0] xright,
	--    // unsigned outputs for sigma delta converters, full resolution
	--    output  [15:0] dacleft,
	--    output  [15:0] dacright
	--);

	component jt51
		port (
			rst : in std_logic;
			clk : in std_logic;
			cen : in std_logic;
			cen_p1 : in std_logic;
			cs_n : in std_logic;
			wr_n : in std_logic;
			a0 : in std_logic;
			din : in std_logic_vector(7 downto 0);
			dout : out std_logic_vector(7 downto 0);
			-- peripheral control
			ct1 : out std_logic;
			ct2 : out std_logic;
			irq_n : out std_logic;
			-- Low resolution output (same as real chip)
			sample : out std_logic;
			left : out std_logic_vector(15 downto 0); --signed
			right : out std_logic_vector(15 downto 0); --signed
			-- Full resolution output
			xleft : out std_logic_vector(15 downto 0); --signed
			xright : out std_logic_vector(15 downto 0) --signed
		);
	end component;

	signal jt51_rst : std_logic;
	signal jt51_cen : std_logic;
	signal jt51_cen_p1 : std_logic;
	signal jt51_cs_n : std_logic;
	signal jt51_wr_n : std_logic;
	signal jt51_a0 : std_logic;
	signal jt51_din : std_logic_vector(7 downto 0);
	signal jt51_dout : std_logic_vector(7 downto 0);
	signal jt51_ct1 : std_logic;
	signal jt51_ct2 : std_logic;
	signal jt51_irq_n : std_logic;
	signal jt51_xleft : std_logic_vector(15 downto 0);
	signal jt51_xright : std_logic_vector(15 downto 0);

	signal din_latch : std_logic_vector(7 downto 0);
	signal ad0_latch : std_logic;

	signal divider : std_logic_vector(2 downto 0); -- 16MHz → 4MHz → 2MHz

	signal write_req : std_logic;
	signal write_req_d : std_logic;
	signal write_ack : std_logic;
	signal write_ack_d : std_logic;
	signal read_req : std_logic;
	signal read_req_d : std_logic;
	signal read_ack : std_logic;
	signal read_ack_D : std_logic;

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
begin

	jt51_rst <= not sys_rstn;

	jt51_u0 : jt51 port map(
		rst => jt51_rst,
		clk => snd_clk,
		cen => jt51_cen,
		cen_p1 => jt51_cen_p1,
		cs_n => jt51_cs_n,
		wr_n => jt51_wr_n,
		a0 => jt51_a0,
		din => jt51_din,
		dout => jt51_dout,
		-- peripheral control
		ct1 => jt51_ct1,
		ct2 => jt51_ct2,
		irq_n => jt51_irq_n,
		-- Low resolution output (same as real chip)
		sample => open,
		left => open,
		right => open,
		-- Full resolution output
		xleft => jt51_xleft,
		xright => jt51_xright
	);

	-- data bus
	odata <= jt51_dout;

	jt51_din <= din_latch;
	jt51_a0 <= ad0_latch;

	-- snd_clk(sndclk) synchronized signals (can be connected directly)
	pcmL <= jt51_xleft(15 downto 0);
	pcmR <= jt51_xright(15 downto 0);

	-- sysclk synchronized inputs
	process (sys_clk, sys_rstn)
	begin
		if (sys_rstn = '0') then
			din_latch <= (others => '0');
			ad0_latch <= '0';
			write_req <= '0';
			write_ack_d <= '0';
			read_req <= '0';
			read_ack_d <= '0';
			--
			ack <= '0';
		elsif (sys_clk' event and sys_clk = '1') then
			ack <= '0';
			write_ack_d <= write_ack; -- メタステーブル回避
			read_ack_d <= read_ack; -- メタステーブル回避
			case state is
				when IDLE =>
					if req = '1' then
						if rw = '0' then
							state <= WR_REQ;
							din_latch <= idata;
							ad0_latch <= addr;
							write_req <= not write_req;
						else
							state <= RD_REQ;
							read_req <= not read_req;
						end if;
					end if;

					-- write cycle
				when WR_REQ =>
					state <= WR_WAIT;
				when WR_WAIT =>
					if (write_req = write_ack_d) then
						state <= WR_ACK;
						ack <= '1';
					end if;
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
					if (read_req = read_ack_d) then
						state <= RD_ACK;
						ack <= '1';
					end if;
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

	-- sysclk synchronized outputs
	process (sys_clk, sys_rstn)begin
		if (sys_rstn = '0') then
			ct1 <= '0';
			ct2 <= '0';
			irqn <= '1';
		elsif (sys_clk' event and sys_clk = '1') then
			ct1 <= jt51_ct2;   -- JT51の実装がCT1とCT2が入れ替わっているので対策
			ct2 <= jt51_ct1;
			irqn <= jt51_irq_n;
		end if;
	end process;

	-- snd_clk synchronized
	process (snd_clk, sys_rstn)begin
		if (sys_rstn = '0') then
			write_req_d <= '0';
			write_ack <= '0';
			read_req_d <= '0';
			read_ack <= '0';
			jt51_cs_n <= '1';
			jt51_wr_n <= '1';
		elsif (snd_clk' event and snd_clk = '1') then
			write_req_d <= write_req; -- メタステーブル回避
			read_req_d <= read_req; -- メタステーブル回避
			jt51_cs_n <= '1';
			jt51_wr_n <= '1';
			if (write_req_d /= write_ack) then
				jt51_cs_n <= '0';
				jt51_wr_n <= '0';
				write_ack <= not write_ack;
			end if;
			if (read_req_d /= read_ack) then
				jt51_cs_n <= '0';
				jt51_wr_n <= '1';
				read_ack <= not read_ack;
			end if;

		end if;
	end process;

	-- snd_clk enable
	-- On X68000, YM2151 is driven by 4MHz.
	-- So cen should be active every 4 clocks (16MHz/4 = 4MHz)
	-- And cen_p1 should be active every 8 clock (16MHz/16 = 2MHz)
	process (snd_clk, sys_rstn)begin
		if (sys_rstn = '0') then
			jt51_cen <= '0';
			jt51_cen_p1 <= '0';
			divider <= (others => '0');
		elsif (snd_clk' event and snd_clk = '1') then
			divider <= divider + 1;

			jt51_cen <= '0';
			jt51_cen_p1 <= '0';
			if (divider = 0) then
				jt51_cen <= '1';
				jt51_cen_p1 <= '1';
			elsif (divider = 4) then
				jt51_cen <= '1';
			end if;
		end if;
	end process;

end rtl;