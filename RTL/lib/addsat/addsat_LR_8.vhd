library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.STD_LOGIC_SIGNED.all;
use ieee.std_logic_arith.all;
use work.X68KeplerX_pkg.all;

-- 最大8入力のステレオPCM音声を時分割処理で合成するコンポーネント
-- 加算機を並列で動かすと回路の消費が多いため、snd_clkを使った時分割で処理します。
-- まず、各入力を 15/8倍〜1/8倍にする処理を 8clkかけて処理します。
-- その処理を8個の入力に対して順次行い、さらにL/Rそれぞれのチャンネルに対して行うため、
-- 音声信号の 8x8x2 = 128倍以上のクロックが必要です。
-- (音声信号が48kHzの場合、snd_clkは 6.144MHz以上が必要)
-- また、音声信号の入力は、左右のステレオ信号を1つの信号にまとめて入力するので、
-- 左右の信号の出力タイミングを合わせるために、lrck信号を入力する必要があります。
-- lrckが0のタイミングがLの処理、lrckが1のタイミングがRの処理となります。
-- snc_clkが16MHzでlrckが48kHzの場合、lrckが0の期間にsnd_clkは 16MHz/48kHz/2 で
-- 約166.6clkあります。snd_clkと非整数倍の関係にあるためこのクロック数は一定しませんが、
-- この期間に、8クロックx8入力分 = 64クロックの処理を行えれば良いので、
-- 64以上あれば問題ありません。つまり、96kHzの処理も可能なポテンシャルがあります。
--
-- なお、合成結果はLRCKの立ち下がり(Rの終わり)に出力されますが、入力は各チャンネルの計算が
-- 行われるタイミングで取り込まれるため、注意が必要です。LRCKの立ち下がりから計算処理が終わるまで
-- 入力信号が変化しないようにする責任は音源ソース側にあります。mt32-piの音声とS/PDIFの入力のように
-- 同じ48kHzでもLRCKが同期していない場合は、どちらかのLRCKを使ってラッチしておく必要があります。
-- もし 48kHzのLRCKとしてI2Cの出力LRCKを使う場合は、全ての入力をLRCKでラッチしておく必要があります。
--
entity addsat_LR_8 is
    port (
        snd_clk : std_logic;
        rst_n : std_logic;

        lrck : in std_logic; -- snd_clkに同期したLRCK

        in0 : in pcmLR_type;
        vol0 : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
        mute0 : in std_logic;

        in1 : in pcmLR_type;
        vol1 : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
        mute1 : in std_logic;

        in2 : in pcmLR_type;
        vol2 : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
        mute2 : in std_logic;

        in3 : in pcmLR_type;
        vol3 : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
        mute3 : in std_logic;

        in4 : in pcmLR_type;
        vol4 : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
        mute4 : in std_logic;

        in5 : in pcmLR_type;
        vol5 : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
        mute5 : in std_logic;

        in6 : in pcmLR_type;
        vol6 : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
        mute6 : in std_logic;

        in7 : in pcmLR_type;
        vol7 : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
        mute7 : in std_logic;

        outq : out pcmLR_type
    );
end addsat_LR_8;

architecture rtl of addsat_LR_8 is
    signal lrck_d : std_logic;
    signal phase_sum : std_logic_vector(3 downto 0); -- 最上位ビットは終了フラグを兼ねる
    signal phase_vol : std_logic_vector(2 downto 0);
    signal result_sum : std_logic_vector(PCM_BIT_WIDTH + 2 downto 0);
    signal result_LR : pcmLR_type;
    signal delta : std_logic_vector(PCM_BIT_WIDTH + 2 downto 0);
    signal vol_abs : integer range 0 to 7;

    function add_sat (A : std_logic_vector; B : std_logic_vector) return std_logic_vector is
        variable WA, WB, SUM : std_logic_vector(PCM_BIT_WIDTH + 3 downto 0);
        variable SUM2 : std_logic_vector(1 downto 0);
        variable OFLOW2, UFLOW2 : std_logic;
    begin
        WA := A(PCM_BIT_WIDTH + 2) & A;
        WB := B(PCM_BIT_WIDTH + 2) & B;
        SUM := WA + WB;
        SUM2 := SUM(PCM_BIT_WIDTH + 3 downto PCM_BIT_WIDTH + 2);
        case SUM2 is
            when "00" | "11" =>
                OFLOW2 := '0';
                UFLOW2 := '0';
            when "01" =>
                OFLOW2 := '1';
                UFLOW2 := '0';
                SUM(PCM_BIT_WIDTH + 2) := '0';
                SUM(PCM_BIT_WIDTH + 1 downto 0) := (others => '1');
            when "10" =>
                OFLOW2 := '0';
                UFLOW2 := '1';
                SUM(PCM_BIT_WIDTH + 2) := '1';
                SUM(PCM_BIT_WIDTH + 1 downto 0) := (others => '0');
            when others =>
                OFLOW2 := '1';
                UFLOW2 := '1';
                SUM := (others => '0');
        end case;
        return OFLOW2 & UFLOW2 & SUM(PCM_BIT_WIDTH + 2 downto 0);
    end function;

begin

    process (snd_clk, rst_n)
        variable in_now : std_logic_vector(PCM_BIT_WIDTH + 2 downto 0);
        variable lr_now : integer range 0 to 1;
        variable vol_now : std_logic_vector(3 downto 0);
        variable mute_now : std_logic;
        variable delta_now : std_logic_vector(PCM_BIT_WIDTH + 2 downto 0);
        variable addsat_result : std_logic_vector(PCM_BIT_WIDTH + 4 downto 0);
        variable phase_vol_int : integer range 0 to 7;
    begin
        if (rst_n = '0') then
            phase_sum <= (others => '0');
            phase_vol <= (others => '0');
            delta <= (others => '0');
            vol_abs <= 0;
            lrck_d <= '0';
            result_sum <= (others => '0');
            outq <= (others => (others => '0'));
        elsif (snd_clk' event and snd_clk = '1') then
            lrck_d <= lrck;
            if (lrck_d = '1' and lrck = '0') then -- Lチャンネル開始
                phase_sum <= "0000";
                phase_vol <= "000";
                outq <= result_LR; -- 前回の結果を出力
                lr_now := 0;
            elsif (lrck_d = '0' and lrck = '1') then -- Rチャンネル開始
                phase_sum <= "0000";
                phase_vol <= "000";
                lr_now := 1;
            else
                phase_vol <= phase_vol + 1;
                if (phase_vol = "111") then
                    if (phase_sum(3) = '0') then
                        phase_sum <= phase_sum + 1;
                    end if;
                    if (phase_sum = "0111") then
                        -- latch after last source finished
                        result_LR(lr_now) <= result_sum(PCM_BIT_WIDTH + 2 downto 3);
                    end if;
                end if;
            end if;

            if (phase_vol = 0) then
                case phase_sum is
                    when "0000" =>
                        in_now := in0(lr_now) & "000";
                        vol_now := vol0;
                        mute_now := mute0;
                    when "0001" =>
                        in_now := in1(lr_now) & "000";
                        vol_now := vol1;
                        mute_now := mute1;
                    when "0010" =>
                        in_now := in2(lr_now) & "000";
                        vol_now := vol2;
                        mute_now := mute2;
                    when "0011" =>
                        in_now := in3(lr_now) & "000";
                        vol_now := vol3;
                        mute_now := mute3;
                    when "0100" =>
                        in_now := in4(lr_now) & "000";
                        vol_now := vol4;
                        mute_now := mute4;
                    when "0101" =>
                        in_now := in5(lr_now) & "000";
                        vol_now := vol5;
                        mute_now := mute5;
                    when "0110" =>
                        in_now := in6(lr_now) & "000";
                        vol_now := vol6;
                        mute_now := mute6;
                    when "0111" =>
                        in_now := in7(lr_now) & "000";
                        vol_now := vol7;
                        mute_now := mute7;
                    when others => -- 終了状態は入力を0にする
                        in_now := (others => '0');
                        vol_now := (others => '0');
                        mute_now := '1';
                end case;

                delta_now := in_now(PCM_BIT_WIDTH + 2) & in_now(PCM_BIT_WIDTH + 2) & in_now(PCM_BIT_WIDTH + 2) & in_now(PCM_BIT_WIDTH + 2 downto 3);

                if (vol_now = "1000" or mute_now = '1') then -- mute
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
                    result_sum <= in_now;
                else
                    addsat_result := add_sat(result_sum, in_now);
                    result_sum <= addsat_result(PCM_BIT_WIDTH + 2 downto 0);
                end if;

                delta <= delta_now;
            else
                phase_vol_int := CONV_INTEGER('0' & phase_vol);
                if (vol_abs >= phase_vol_int) then
                    addsat_result := add_sat(result_sum, delta);
                    result_sum <= addsat_result(PCM_BIT_WIDTH + 2 downto 0);
                end if;
            end if;
        end if;
    end process;
end rtl;