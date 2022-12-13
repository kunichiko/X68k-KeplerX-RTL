library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.STD_LOGIC_SIGNED.all;
use ieee.std_logic_arith.all;

entity addsat is
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
end addsat;

architecture rtl of addsat is
begin
	process (snd_clk)
		variable WA, WB, SUM : std_logic_vector(datwidth downto 0);
		variable SUM2 : std_logic_vector(1 downto 0);
	begin
		if (snd_clk' event and snd_clk = '1') then
			WA := INA(datwidth - 1) & INA;
			WB := INB(datwidth - 1) & INB;
			SUM := WA + WB;
			SUM2 := SUM(datwidth downto datwidth - 1);
			case SUM2 is
				when "00" | "11" =>
					OUTQ <= SUM(datwidth - 1 downto 0);
					OFLOW <= '0';
					UFLOW <= '0';
				when "01" =>
					OUTQ(datwidth - 1) <= '0';
					OUTQ(datwidth - 2 downto 0) <= (others => '1');
					OFLOW <= '1';
					UFLOW <= '0';
				when "10" =>
					OUTQ(datwidth - 1) <= '1';
					OUTQ(datwidth - 2 downto 0) <= (others => '0');
					OFLOW <= '0';
					UFLOW <= '1';
				when others =>
					OUTQ <= (others => '0');
					OFLOW <= '1';
					UFLOW <= '1';
			end case;
		end if;
	end process;
end rtl;