library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.STD_LOGIC_UNSIGNED.all;

entity calcadpcm is
	port (
		playen : in std_logic;
		datin : in std_logic_vector(3 downto 0);
		datemp : in std_logic;
		datwr : in std_logic;

		play_init_req : in std_logic;

		datout : out std_logic_vector(11 downto 0);

		clkdiv : in std_logic_vector(1 downto 0);
		sft : in std_logic;
		clk : in std_logic;
		rstn : in std_logic
	);

end calcadpcm;

architecture rtl of calcadpcm is
	component tbl6258
		port (
			address : in std_logic_vector (8 downto 0);
			clock : in std_logic := '1';
			q : out std_logic_vector (11 downto 0)
		);
	end component;

	signal curval : std_logic_vector(19 downto 0);
	signal nxtvalx : std_logic_vector(19 downto 0);
	signal step : std_logic_vector(5 downto 0);
	signal tbladdr : std_logic_vector(8 downto 0);
	signal diffval : std_logic_vector(11 downto 0);
	signal diffvalx : std_logic_vector(21 downto 0);
	signal sign : std_logic;
	signal snden : std_logic;

	type state_t is(
	st_idle,
	st_wait,
	st_calc
	);
	signal state : state_t;

begin

	diftbl : tbl6258 port map(
		address => tbladdr,
		clock => clk,
		q => diffval
	);

	process (clk, rstn)
		variable nxtstep : std_logic_vector(5 downto 0);
		variable nxtval : std_logic_vector(21 downto 0);
	begin
		if (rstn = '0') then
			nxtvalx <= (others => '0');
			step <= (others => '0');
			snden <= '0';
			state <= st_idle;
		elsif (clk' event and clk = '1') then
			case state is
				when st_idle =>
					if (playen = '0') then
						nxtvalx <= (others => '0');
						step <= (others => '0');
						snden <= '0';
						if (curval > 0) then
							nxtvalx <= curval - 1;
						elsif (curval < 0) then
							nxtvalx <= curval + 1;
						end if;
					elsif (datwr = '1') then
						tbladdr <= step & datin(2 downto 0);
						sign <= datin(3);
						case datin(2 downto 0) is
							when "000" | "001" | "010" | "011" =>
								if (step > "000000") then
									nxtstep := step - "000001";
								else
									nxtstep := step;
								end if;
							when "100" =>
								nxtstep := step + "000010";
							when "101" =>
								nxtstep := step + "000100";
							when "110" =>
								nxtstep := step + "000110";
							when "111" =>
								nxtstep := step + "001000";
							when others =>
								nxtstep := step;
						end case;
						if (nxtstep > "110000") then
							step <= "110000";
						else
							step <= nxtstep;
						end if;
						snden <= '1';
						state <= st_wait;
					elsif (sft = '1') then
						if (datemp = '1') then
							-- データが来ない時はDC成分を少しずつ下げていく
							if (curval(19) = '0') then
								nxtvalx <= curval - 256;
							else
								nxtvalx <= curval + 256;
							end if;
						elsif (snden = '1') then
							state <= st_calc;
							--					else
							--						if(curval>0)then
							--							nxtvalx<=curval-1;
							--						elsif(curval<0)then
							--							nxtvalx<=curval+1;
							--						end if;
						end if;
					end if;
				when st_wait =>
					state <= st_calc;
				when st_calc =>
					if (sign = '0') then
						nxtval := (curval(19) & curval(19) & curval) + diffvalx;
						if (nxtval(21) = '0' and nxtval(20 downto 19) /= "00") then
							nxtval(21 downto 19) := "000";
							nxtval(18 downto 0) := (others => '1');
						end if;
					else
						nxtval := (curval(19) & curval(19) & curval) - diffvalx;
						if (nxtval(21) = '1' and nxtval(20 downto 19) /= "11") then
							nxtval(21 downto 19) := "111";
							nxtval(18 downto 0) := (others => '0');
						end if;
					end if;
					-- DC成分を消すために 毎回  4095/4096倍する (1/4096を引く)
					-- 2MHzでオーバーサンプリングしているので、実質、15.6kHzごとに 248/256倍してることになる
					nxtvalx <= nxtval(19 downto 0)
						- (nxtval(19) & nxtval(19) & nxtval(19) & nxtval(19) & nxtval(19) & nxtval(19) & nxtval(19) & nxtval(19) & nxtval(19) & nxtval(19) & nxtval(19) & nxtval(19) & nxtval(19 downto 12));
					state <= st_idle;
			end case;
		end if;
	end process;

	curval <= nxtvalx;
	datout <= curval(19 downto 8);

	diffvalx <= "0000000000" & diffval when clkdiv = "00" else
		"000000000" & diffval & '0' when clkdiv = "01" else
		"000000000" & diffval & '0' when clkdiv = "10" else
		"00" & diffval & "00000000";

end rtl;