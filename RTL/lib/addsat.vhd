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

		VOLA : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
		VOLB : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute

		OUTQ : out std_logic_vector(datwidth - 1 downto 0);
		OFLOW : out std_logic;
		UFLOW : out std_logic
	);
end addsat;
architecture rtl of addsat is
	signal phase : std_logic_vector(2 downto 0);
	signal resultA, resultB : std_logic_vector(datwidth - 1 downto 0);
	signal deltaA, deltaB : std_logic_vector(datwidth - 1 downto 0);

	function add_sat (A : std_logic_vector; B : std_logic_vector) return std_logic_vector is
		variable WA, WB, SUM : std_logic_vector(datwidth downto 0);
		variable SUM2 : std_logic_vector(1 downto 0);
		variable OFLOW2, UFLOW2 : std_logic;
	begin
		WA := A(datwidth - 1) & A;
		WB := B(datwidth - 1) & B;
		SUM := WA + WB;
		SUM2 := SUM(datwidth downto datwidth - 1);
		case SUM2 is
			when "00" | "11" =>
				OFLOW2 := '0';
				UFLOW2 := '0';
			when "01" =>
				OFLOW2 := '1';
				UFLOW2 := '0';
				SUM(datwidth - 1) := '0';
				SUM(datwidth - 2 downto 0) := (others => '1');
			when "10" =>
				OFLOW2 := '0';
				UFLOW2 := '1';
				SUM(datwidth - 1) := '1';
				SUM(datwidth - 2 downto 0) := (others => '0');
			when others =>
				OFLOW2 := '1';
				UFLOW2 := '1';
				SUM := (others => '0');
		end case;
		return OFLOW2 & UFLOW2 & SUM(datwidth - 1 downto 0);
	end function;

begin

	process (snd_clk)
		variable WA, WB : std_logic_vector(datwidth - 1 downto 0);
		variable result : std_logic_vector(datwidth + 1 downto 0);
		variable negA, negB, phase_now : std_logic_vector(3 downto 0);
	begin
		if (snd_clk' event and snd_clk = '1') then

			phase <= phase + 1;
			if (phase = 0) then
				resultA <= INA;
				resultB <= INB;
				deltaA <= INA(datwidth - 1) & INA(datwidth - 1) & INA(datwidth - 1) & INA(datwidth - 1 downto 3);
				deltaB <= INB(datwidth - 1) & INB(datwidth - 1) & INB(datwidth - 1) & INB(datwidth - 1 downto 3);
				--
				if (VOLA = "1000") then
					WA := (others => '0');
				else
					WA := resultA;
				end if;
				if (VOLB = "1000") then
					WB := (others => '0');
				else
					WB := resultB;
				end if;
				result := add_sat(WA, WB);
				OFLOW <= result(datwidth + 1);
				UFLOW <= result(datwidth + 0);
				OUTQ <= result(datwidth - 1 downto 0);
			else
				phase_now := '0' & phase;
				negA := (not VOLA) + 1;
				if ((VOLA(3) = '0') and (VOLA >= phase_now)) then
					result := add_sat(resultA, deltaA);
					resultA <= result(datwidth - 1 downto 0);
				end if;
				if ((VOLA(3) = '1') and (negA >= phase_now)) then
					result := add_sat(resultA, (not deltaA) + 1);
					resultA <= result(datwidth - 1 downto 0);
				end if;
				negB := (not VOLB) + 1;
				if ((VOLB(3) = '0') and (VOLB >= phase_now)) then
					result := add_sat(resultB, deltaB);
					resultB <= result(datwidth - 1 downto 0);
				end if;
				if ((VOLB(3) = '1') and (negB >= phase_now)) then
					result := add_sat(resultB, (not deltaB) + 1);
					resultB <= result(datwidth - 1 downto 0);
				end if;
			end if;
		end if;
	end process;
end rtl;