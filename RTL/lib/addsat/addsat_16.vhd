library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.STD_LOGIC_SIGNED.all;
use ieee.std_logic_arith.all;

-- 最大16入力の PCM音声を時分割処理で合成するコンポーネント
-- 加算機を並列で動かすと回路の消費が多いため、snd_clkで自分割に処理します。
-- まず、各入力を 15/8倍〜1/8倍にする処理を 8clkかけて処理します。その処理を16個の
-- 入力に対して順次行うため、音声信号の 8x16 = 128倍のクロックが必要です。
-- 音声信号が48kHzの場合、snd_clkは 6.144MHz以上が必要です(16MHzなので問題ない)
entity addsat_16 is
    generic (
        datwidth : integer := 16
    );
    port (
        snd_clk : std_logic;
        rst_n : std_logic;

        in0 : in std_logic_vector(datwidth - 1 downto 0);
        vol0 : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
        mute0 : in std_logic;

        in1 : in std_logic_vector(datwidth - 1 downto 0);
        vol1 : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
        mute1 : in std_logic;

        in2 : in std_logic_vector(datwidth - 1 downto 0);
        vol2 : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
        mute2 : in std_logic;

        in3 : in std_logic_vector(datwidth - 1 downto 0);
        vol3 : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
        mute3 : in std_logic;

        in4 : in std_logic_vector(datwidth - 1 downto 0);
        vol4 : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
        mute4 : in std_logic;

        in5 : in std_logic_vector(datwidth - 1 downto 0);
        vol5 : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
        mute5 : in std_logic;

        in6 : in std_logic_vector(datwidth - 1 downto 0);
        vol6 : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
        mute6 : in std_logic;

        in7 : in std_logic_vector(datwidth - 1 downto 0);
        vol7 : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
        mute7 : in std_logic;

        in8 : in std_logic_vector(datwidth - 1 downto 0);
        vol8 : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
        mute8 : in std_logic;

        in9 : in std_logic_vector(datwidth - 1 downto 0);
        vol9 : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
        mute9 : in std_logic;

        inA : in std_logic_vector(datwidth - 1 downto 0);
        volA : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
        muteA : in std_logic;

        inB : in std_logic_vector(datwidth - 1 downto 0);
        volB : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
        muteB : in std_logic;

        inC : in std_logic_vector(datwidth - 1 downto 0);
        volC : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
        muteC : in std_logic;

        inD : in std_logic_vector(datwidth - 1 downto 0);
        volD : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
        muteD : in std_logic;

        inE : in std_logic_vector(datwidth - 1 downto 0);
        volE : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
        muteE : in std_logic;

        inF : in std_logic_vector(datwidth - 1 downto 0);
        volF : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
        muteF : in std_logic;

        outq : out std_logic_vector(datwidth - 1 downto 0)
    );
end addsat_16;

architecture rtl of addsat_16 is
    signal phase_sum : std_logic_vector(3 downto 0);
    signal phase_vol : std_logic_vector(2 downto 0);
    signal result_sum : std_logic_vector(datwidth + 2 downto 0);
    signal delta : std_logic_vector(datwidth + 2 downto 0);
    signal vol_abs : integer range 0 to 7;

    function add_sat (A : std_logic_vector; B : std_logic_vector) return std_logic_vector is
        variable WA, WB, SUM : std_logic_vector(datwidth + 3 downto 0);
        variable SUM2 : std_logic_vector(1 downto 0);
        variable OFLOW2, UFLOW2 : std_logic;
    begin
        WA := A(datwidth + 2) & A;
        WB := B(datwidth + 2) & B;
        SUM := WA + WB;
        SUM2 := SUM(datwidth + 3 downto datwidth + 2);
        case SUM2 is
            when "00" | "11" =>
                OFLOW2 := '0';
                UFLOW2 := '0';
            when "01" =>
                OFLOW2 := '1';
                UFLOW2 := '0';
                SUM(datwidth + 2) := '0';
                SUM(datwidth + 1 downto 0) := (others => '1');
            when "10" =>
                OFLOW2 := '0';
                UFLOW2 := '1';
                SUM(datwidth + 2) := '1';
                SUM(datwidth + 1 downto 0) := (others => '0');
            when others =>
                OFLOW2 := '1';
                UFLOW2 := '1';
                SUM := (others => '0');
        end case;
        return OFLOW2 & UFLOW2 & SUM(datwidth + 2 downto 0);
    end function;

begin

    process (snd_clk, rst_n)
        variable in_now : std_logic_vector(datwidth + 2 downto 0);
        variable vol_now : std_logic_vector(3 downto 0);
        variable mute_now : std_logic;
        variable delta_now : std_logic_vector(datwidth + 2 downto 0);
        variable addsat_result : std_logic_vector(datwidth + 4 downto 0);
        variable phase_vol_int : integer range 0 to 7;
    begin
        if (rst_n = '0') then
            phase_sum <= (others => '0');
            phase_vol <= (others => '0');
            delta <= (others => '0');
            vol_abs <= 0;
        elsif (snd_clk' event and snd_clk = '1') then

            phase_vol <= phase_vol + 1;
            if (phase_vol = 0) then
                phase_sum <= phase_sum + 1;

                case phase_sum is
                    when "0000" =>
                        in_now := in0 & "000";
                        vol_now := vol0;
                        mute_now := mute0;
                    when "0001" =>
                        in_now := in1 & "000";
                        vol_now := vol1;
                        mute_now := mute1;
                    when "0010" =>
                        in_now := in2 & "000";
                        vol_now := vol2;
                        mute_now := mute2;
                    when "0011" =>
                        in_now := in3 & "000";
                        vol_now := vol3;
                        mute_now := mute3;
                    when "0100" =>
                        in_now := in4 & "000";
                        vol_now := vol4;
                        mute_now := mute4;
                    when "0101" =>
                        in_now := in5 & "000";
                        vol_now := vol5;
                        mute_now := mute5;
                    when "0110" =>
                        in_now := in6 & "000";
                        vol_now := vol6;
                        mute_now := mute6;
                    when "0111" =>
                        in_now := in7 & "000";
                        vol_now := vol7;
                        mute_now := mute7;
                    when "1000" =>
                        in_now := in8 & "000";
                        vol_now := vol8;
                        mute_now := mute8;
                    when "1001" =>
                        in_now := in9 & "000";
                        vol_now := vol9;
                        mute_now := mute9;
                    when "1010" =>
                        in_now := inA & "000";
                        vol_now := volA;
                        mute_now := muteA;
                    when "1011" =>
                        in_now := inB & "000";
                        vol_now := volB;
                        mute_now := muteB;
                    when "1100" =>
                        in_now := inC & "000";
                        vol_now := volC;
                        mute_now := muteC;
                    when "1101" =>
                        in_now := inD & "000";
                        vol_now := volD;
                        mute_now := muteD;
                    when "1110" =>
                        in_now := inE & "000";
                        vol_now := volE;
                        mute_now := muteE;
                    when "1111" =>
                        in_now := inF & "000";
                        vol_now := volF;
                        mute_now := muteF;
                    when others =>
                        in_now := (others => '0');
                        vol_now := (others => '0');
                        mute_now := '0';
                end case;

                delta_now := in_now(datwidth + 2) & in_now(datwidth + 2) & in_now(datwidth + 2) & in_now(datwidth + 2 downto 3);

                if (vol_now = "1000" or mute_now ='1') then -- mute
                    delta_now := (others => '0');
                    in_now := (others => '0');
                    vol_abs <= 0;
                elsif (vol_now(3) = '0') then
                    vol_abs <= CONV_INTEGER('0' & vol_now(2 downto 0));
                else
                    vol_abs <= CONV_INTEGER(not vol_now(3 downto 0)) + 1;
                    delta_now := (not delta_now) + 1; -- volが負の数の場合は正負反転
                end if;

                if phase_sum = "0000" then
                    outq <= result_sum(datwidth + 2 downto 3); -- 結果出力
                    result_sum <= in_now;
                else
                    addsat_result := add_sat(result_sum, in_now);
                    result_sum <= addsat_result(datwidth + 2 downto 0);
                end if;

                delta <= delta_now;
            else
                phase_vol_int := CONV_INTEGER('0' & phase_vol);
                if (vol_abs >= phase_vol_int) then
                    addsat_result := add_sat(result_sum, delta);
                    result_sum <= addsat_result(datwidth + 2 downto 0);
                end if;
            end if;
        end if;
    end process;
end rtl;