library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.STD_LOGIC_UNSIGNED.all;

entity e8255 is
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
end e8255;

architecture rtl of e8255 is
	signal OE_A : std_logic;
	signal OE_B : std_logic;
	signal OE_CH : std_logic;
	signal OE_CL : std_logic;
	signal ODAT_A : std_logic_vector(7 downto 0);
	signal ODAT_B : std_logic_vector(7 downto 0);
	signal ODAT_C : std_logic_vector(7 downto 0);
	signal REG : std_logic_vector(7 downto 0);
	signal PA, PB, PC : std_logic_vector(7 downto 0);
	signal RD : std_logic;
	signal WR : std_logic;
	signal MODE : std_logic_vector(1 downto 0);

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
	-- sysclk synchronized inputs
	process (sys_clk, sys_rstn)
	begin
		if (sys_rstn = '0') then
			ack <= '0';
			RD <= '0';
			WR <= '0';
		elsif (sys_clk' event and sys_clk = '1') then
			ack <= '0';
			RD <= '0';
			WR <= '0';
			case state is
				when IDLE =>
					if req = '1' then
						if rw = '0' then
							state <= WR_REQ;
							WR <= '1';
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

	process (sys_clk, sys_rstn)begin
		if (sys_rstn = '0') then
			ODAT_A <= (others => deflogic);
			ODAT_B <= (others => deflogic);
			ODAT_C <= (others => deflogic);
			REG <= (others => '0');
			OE_A <= '0';
			OE_B <= '0';
			OE_CH <= '0';
			OE_CL <= '0';
		elsif (sys_clk' event and sys_clk = '1') then
			if (WR = '1') then
				case addr is
					when "00" =>
						ODAT_A <= idata;
					when "01" =>
						ODAT_B <= idata;
					when "10" =>
						ODAT_C <= idata;
					when "11" =>
						REG <= idata;
						if (idata(7) = '1') then --mode select
							MODE <= idata(6 downto 5);
							OE_A <= not idata(4);
							OE_CH <= not idata(3);
							OE_B <= not idata(1);
							OE_CL <= not idata(0);
							if (idata(4) = '0') then
								ODAT_A <= (others => '0');
							end if;
							if (idata(1) = '0') then
								ODAT_B <= (others => '0');
							end if;
							if (idata(3) = '0') then
								ODAT_C(7 downto 4) <= (others => '0');
							end if;
							if (idata(0) = '0') then
								ODAT_C(3 downto 0) <= (others => '0');
							end if;
						else
							case idata(3 downto 1) is
								when "000" =>
									ODAT_C(0) <= idata(0);
								when "001" =>
									ODAT_C(1) <= idata(0);
								when "010" =>
									ODAT_C(2) <= idata(0);
								when "011" =>
									ODAT_C(3) <= idata(0);
								when "100" =>
									ODAT_C(4) <= idata(0);
								when "101" =>
									ODAT_C(5) <= idata(0);
								when "110" =>
									ODAT_C(6) <= idata(0);
								when "111" =>
									ODAT_C(7) <= idata(0);
								when others =>
							end case;
						end if;
					when others =>
				end case;
			end if;
		end if;
	end process;

	PAo <= ODAT_A;
	PBo <= ODAT_B;
	PCHo <= ODAT_C(7 downto 4);
	PCLo <= ODAT_C(3 downto 0);

	PAoe <= OE_A;
	PBoe <= OE_B;
	PCHoe <= OE_CH;
	PCLoe <= OE_CL;

	PA <= PAi when OE_A = '0' else ODAT_A;
	PB <= PBi when OE_B = '0' else ODAT_B;
	PC(7 downto 4) <= PCHi when OE_CH = '0' else ODAT_C(7 downto 4);
	PC(3 downto 0) <= PCLi when OE_CL = '0' else ODAT_C(3 downto 0);

	odata <=
		PA when addr = "00" else
		PB when addr = "01" else
		PC when addr = "10" else
		REG;

end rtl;