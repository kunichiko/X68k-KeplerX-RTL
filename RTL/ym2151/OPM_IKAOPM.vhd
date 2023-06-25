--
--  OPM_IKAOPM.vhd
--
--    Author Kunihiko Ohnaka
--
library IEEE;

use IEEE.STD_LOGIC_1164.all;
use IEEE.STD_LOGIC_ARITH.all;
use IEEE.STD_LOGIC_UNSIGNED.all;

-- KeplerX から IKAOPMを使用するためのコンポーネントです
-- https://github.com/ika-musume/IKAOPM

entity OPM_IKAOPM is
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
end OPM_IKAOPM;

architecture rtl of OPM_IKAOPM is

	-- IKAOPM Verilog module definition is below:
	-- 	module IKAOPM (
	--     //chip clock
	--     input   wire            i_EMUCLK, //emulator master clock
	--     input   wire            i_phiM_PCEN_n, //phiM clock enable

	--     //chip reset
	--     input   wire            i_IC_n,    

	--     //phi1
	--     output  wire            o_phi1,

	--     //bus control and address
	--     input   wire            i_CS_n,
	--     input   wire            i_RD_n,
	--     input   wire            i_WR_n,
	--     input   wire            i_A0,

	--     //bus data
	--     input   wire    [7:0]   i_D,
	--     output  wire    [7:0]   o_D,

	--     //output driver enable
	--     output  wire            o_CTRL_OE,

	--     //ct
	--     output  wire            o_CT2,
	--     output  wire            o_CT1,

	--     //interrupt
	--     output  wire            o_IRQ_n,

	--     //sh
	--     output  wire            o_SH1,
	--     output  wire            o_SH2,

	--     //output
	--     output  wire            o_SO,
	--     output  wire    [15:0]  o_EMU_R_PO, o_EMU_L_PO
	-- );

	component IKAOPM
		port (
			i_EMUCLK : in std_logic; --  //emulator master clock
			i_phiM_PCEN_n : in std_logic; --  //phiM clock enable
			-- chip reset
			i_IC_n : in std_logic;
			-- phi1
			o_phi1 : out std_logic;
			-- bus control and address
			i_CS_n : in std_logic;
			i_RD_n : in std_logic;
			i_WR_n : in std_logic;
			i_A0 : in std_logic;
			-- bus data
			i_D : in std_logic_vector(7 downto 0);
			o_D : out std_logic_vector(7 downto 0);
			-- output driver enable
			o_CTRL_OE : out std_logic;
			-- ct
			o_CT2 : out std_logic;
			o_CT1 : out std_logic;
			-- interrupt
			o_IRQ_n : out std_logic;
			-- sh
			o_SH1 : out std_logic;
			o_SH2 : out std_logic;
			-- output
			o_SO : out std_logic; -- 
			o_EMU_R_PO : out std_logic_vector(15 downto 0);
			o_EMU_L_PO : out std_logic_vector(15 downto 0)
		);
	end component;

	signal ic_counter : std_logic_vector(5 downto 0);

	signal ikaopm_ic_n : std_logic;
	signal ikaopm_cen_n : std_logic;
	signal ikaopm_cs_n : std_logic;
	signal ikaopm_rd_n : std_logic;
	signal ikaopm_wr_n : std_logic;
	signal ikaopm_a0 : std_logic;
	signal ikaopm_din : std_logic_vector(7 downto 0);
	signal ikaopm_dout : std_logic_vector(7 downto 0);
	signal ikaopm_ct1 : std_logic;
	signal ikaopm_ct2 : std_logic;
	signal ikaopm_irq_n : std_logic;
	signal ikaopm_xleft : std_logic_vector(15 downto 0);
	signal ikaopm_xright : std_logic_vector(15 downto 0);

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

	process (snd_clk, sys_rstn)begin
		if (sys_rstn = '0') then
			ic_counter <= (others => '1');
			ikaopm_ic_n <= '0';
		elsif (snd_clk' event and snd_clk = '1') then
			if (ic_counter = 0) then
				ikaopm_ic_n <= '1';
			else
				ikaopm_ic_n <= '0';
				ic_counter <= ic_counter - 1;
			end if;
		end if;
	end process;

	ikaopm_u0 : IKAOPM port map(
		i_EMUCLK => snd_clk, --  //emulator master clock
		i_phiM_PCEN_n => ikaopm_cen_n, --  //phiM clock enable
		-- chip reset
		i_IC_n => ikaopm_ic_n,
		-- phi1
		o_phi1 => open,
		-- bus control and address
		i_CS_n => ikaopm_cs_n,
		i_RD_n => ikaopm_rd_n,
		i_WR_n => ikaopm_wr_n,
		i_A0 => ikaopm_a0,
		-- bus data
		i_D => ikaopm_din,
		o_D => ikaopm_dout,
		-- output driver enable
		o_CTRL_OE => open,
		-- ct
		o_CT2 => ikaopm_ct2,
		o_CT1 => ikaopm_ct1,
		-- interrupt
		o_IRQ_n => ikaopm_irq_n,
		-- sh
		o_SH1 => open,
		o_SH2 => open,
		-- output
		o_SO => open,
		o_EMU_R_PO => ikaopm_xright,
		o_EMU_L_PO => ikaopm_xleft
	);

	-- data bus
	odata <= ikaopm_dout;

	ikaopm_din <= din_latch;
	ikaopm_a0 <= ad0_latch;

	-- snd_clk(sndclk) synchronized signals (can be connected directly)
	pcmL <= ikaopm_xleft(15 downto 0);
	pcmR <= ikaopm_xright(15 downto 0);

	-- sysclk synchronized inputs
	process (sys_clk, sys_rstn)
	begin
		if (sys_rstn = '0') then
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
			ct1 <= ikaopm_ct2; -- JT51の実装がCT1とCT2が入れ替わっているので対策
			ct2 <= ikaopm_ct1;
			irqn <= ikaopm_irq_n;
		end if;
	end process;

	-- snd_clk synchronized
	process (snd_clk, sys_rstn)begin
		if (sys_rstn = '0') then
			din_latch <= (others => '0');
			ad0_latch <= '0';
			write_req_d <= '0';
			write_ack <= '0';
			read_req_d <= '0';
			read_ack <= '0';
			ikaopm_cs_n <= '1';
			ikaopm_rd_n <= '1';
			ikaopm_wr_n <= '1';
		elsif (snd_clk' event and snd_clk = '1') then
			write_req_d <= write_req; -- メタステーブル回避
			read_req_d <= read_req; -- メタステーブル回避
			ikaopm_cs_n <= '1';
			ikaopm_rd_n <= '1';
			ikaopm_wr_n <= '1';
			if (write_req_d /= write_ack) then
				ikaopm_cs_n <= '0';
				ikaopm_rd_n <= '1';
				ikaopm_wr_n <= '0';
				din_latch <= idata;
				ad0_latch <= addr;
				write_ack <= not write_ack;
			end if;
			if (read_req_d /= read_ack) then
				ikaopm_cs_n <= '0';
				ikaopm_rd_n <= '0';
				ikaopm_wr_n <= '1';
				ad0_latch <= addr;
				read_ack <= not read_ack;
			end if;

		end if;
	end process;

	-- snd_clk enable
	-- On X68000, YM2151 is driven by 4MHz.
	-- So cen should be active every 4 clocks (16MHz/4 = 4MHz)
	process (snd_clk, sys_rstn)begin
		if (sys_rstn = '0') then
			ikaopm_cen_n <= '1';
			divider <= (others => '0');
		elsif (snd_clk' event and snd_clk = '1') then
			divider <= divider + 1;

			ikaopm_cen_n <= '1';
			if (divider = 0) then
				ikaopm_cen_n <= '0';
			elsif (divider = 4) then
				ikaopm_cen_n <= '0';
			end if;
		end if;
	end process;

end rtl;