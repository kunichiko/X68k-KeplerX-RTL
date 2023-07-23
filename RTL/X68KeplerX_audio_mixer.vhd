library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.STD_LOGIC_SIGNED.all;
use work.X68KeplerX_pkg.all;
use ieee.std_logic_arith.all;

-- Kepler-X のオーディオソースを合成し、48kHzのステレオPCM信号に変換するモジュール
--
-- Kepler-X には以下の入力ソースがあります
-- 
-- 【8MHzを2の累乗で分周した 62.5kHz系】
-- OPMのFM音源
-- OPNAのSSG音源(x2)
-- ADPCM(MSM6258)
--
-- 【8MHzを9で割った後に2の累乗で分周した 55.5kHz系】
-- OPNAのFM音源(x2)
-- OPNAのリズム音源(x2)
-- OPNAのADPCM(x2)
-- 
-- 【48kHz】
-- マーキュリーユニットのPCM音源
-- mt32-pi
-- S/PDIF入力
--
-- ※マーキュリーのPCM音源や S/PDIF入力が 44.1kHzや32kHzになることがありますが、
-- 当面はサポートしない
--
-- 本モジュールはサンプリングレート変換を行って48kHzに統一します。
--
-- ●入力系統
-- 合計16系統の入力を受け付けます
-- - 62.5kHz系 - 最大4入力
-- - 55.5kHz系 - 最大8入力
-- - 48.0kHz系 - 最大4入力
entity X68KeplerX_audio_mixer is
    port (
        snd_clk : std_logic;
        rst_n : std_logic;

        --
        lrck625 : in std_logic; -- snd_clkに同期した62.5kHzの入力ソースのLRCK

        in625_0 : in pcmLR_type;
        vol625_0 : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
        mute625_0 : in std_logic;

        in625_1 : in pcmLR_type;
        vol625_1 : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
        mute625_1 : in std_logic;

        in625_2 : in pcmLR_type;
        vol625_2 : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
        mute625_2 : in std_logic;

        in625_3 : in pcmLR_type;
        vol625_3 : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
        mute625_3 : in std_logic;

        --
        lrck555 : in std_logic; -- snd_clkに同期した55.5kHzの入力ソースのLRCK

        in555_0 : in pcmLR_type;
        vol555_0 : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
        mute555_0 : in std_logic;

        in555_1 : in pcmLR_type;
        vol555_1 : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
        mute555_1 : in std_logic;

        in555_2 : in pcmLR_type;
        vol555_2 : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
        mute555_2 : in std_logic;

        in555_3 : in pcmLR_type;
        vol555_3 : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
        mute555_3 : in std_logic;

        in555_4 : in pcmLR_type;
        vol555_4 : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
        mute555_4 : in std_logic;

        in555_5 : in pcmLR_type;
        vol555_5 : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
        mute555_5 : in std_logic;

        in555_6 : in pcmLR_type;
        vol555_6 : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
        mute555_6 : in std_logic;

        in555_7 : in pcmLR_type;
        vol555_7 : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
        mute555_7 : in std_logic;

        --
        lrck480 : in std_logic; -- snd_clkに同期した48kHzの「出力」ソースのLRCK (入力もこれに同期している必要あり)

        in480_0 : in pcmLR_type;
        vol480_0 : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
        mute480_0 : in std_logic;

        in480_1 : in pcmLR_type;
        vol480_1 : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
        mute480_1 : in std_logic;

        in480_2 : in pcmLR_type;
        vol480_2 : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
        mute480_2 : in std_logic;

        in480_3 : in pcmLR_type;
        vol480_3 : in std_logic_vector(3 downto 0); -- (+7〜-7)/8, -8 is mute
        mute480_3 : in std_logic;

        --
        outq : out pcmLR_type
    );
end X68KeplerX_audio_mixer;

architecture rtl of X68KeplerX_audio_mixer is

    component addsat_LR_8
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
    end component;

    type av_send_st is(
    AV_SEND_L,
    AV_SEND_R
    );

    type av_recv_st is(
    AV_RECV_L,
    AV_RECV_R
    );

    -- 62.5kHz section
    signal lrck625_d : std_logic;
    signal sum625 : pcmLR_type;
    signal conv625 : pcmLR_type;
    signal avsend625_state : av_send_st;
    signal avrecv625_state : av_recv_st;

    component cic_up96 is
        port (
            clk : in std_logic := 'X'; -- clk
            reset_n : in std_logic := 'X'; -- reset_n
            in_error : in std_logic_vector(1 downto 0) := (others => 'X'); -- error
            in_valid : in std_logic := 'X'; -- valid
            in_ready : out std_logic; -- ready
            in_data : in std_logic_vector(15 downto 0) := (others => 'X'); -- in_data
            in_startofpacket : in std_logic := 'X'; -- startofpacket
            in_endofpacket : in std_logic := 'X'; -- endofpacket
            out_data : out std_logic_vector(15 downto 0); -- out_data
            out_error : out std_logic_vector(1 downto 0); -- error
            out_valid : out std_logic; -- valid
            out_ready : in std_logic := 'X'; -- ready
            out_startofpacket : out std_logic; -- startofpacket
            out_endofpacket : out std_logic; -- endofpacket
            out_channel : out std_logic; -- channel
            clken : in std_logic := 'X' -- clken
        );
    end component cic_up96;

    signal cicup96_in_valid : std_logic;
    signal cicup96_in_ready : std_logic;
    signal cicup96_in_data : std_logic_vector(15 downto 0);
    signal cicup96_in_startofpacket : std_logic;
    signal cicup96_in_endofpacket : std_logic;
    signal cicup96_out_valid : std_logic;
    signal cicup96_out_ready : std_logic;
    signal cicup96_out_data : std_logic_vector(15 downto 0);
    signal cicup96_out_startofpacket : std_logic;
    signal cicup96_out_endofpacket : std_logic;
    signal cicup96_out_channel : std_logic;

    component cic_down125 is
        port (
            clk : in std_logic := 'X'; -- clk
            reset_n : in std_logic := 'X'; -- reset_n
            in_error : in std_logic_vector(1 downto 0) := (others => 'X'); -- error
            in_valid : in std_logic := 'X'; -- valid
            in_ready : out std_logic; -- ready
            in_data : in std_logic_vector(15 downto 0) := (others => 'X'); -- in_data
            in_startofpacket : in std_logic := 'X'; -- startofpacket
            in_endofpacket : in std_logic := 'X'; -- endofpacket
            out_data : out std_logic_vector(15 downto 0); -- out_data
            out_error : out std_logic_vector(1 downto 0); -- error
            out_valid : out std_logic; -- valid
            out_ready : in std_logic := 'X'; -- ready
            out_startofpacket : out std_logic; -- startofpacket
            out_endofpacket : out std_logic; -- endofpacket
            out_channel : out std_logic; -- channel
            clken : in std_logic := 'X' -- clken
        );
    end component cic_down125;

    signal cicdown125_in_valid : std_logic;
    signal cicdown125_in_ready : std_logic;
    signal cicdown125_in_data : std_logic_vector(15 downto 0);
    signal cicdown125_in_startofpacket : std_logic;
    signal cicdown125_in_endofpacket : std_logic;
    signal cicdown125_out_valid : std_logic;
    signal cicdown125_out_ready : std_logic;
    signal cicdown125_out_data : std_logic_vector(15 downto 0);
    signal cicdown125_out_startofpacket : std_logic;
    signal cicdown125_out_endofpacket : std_logic;
    signal cicdown125_out_channel : std_logic;

    -- 55.5kHz section
    signal lrck555_d : std_logic;
    signal sum555 : pcmLR_type;
    signal conv555 : pcmLR_type;

    -- 48.0kHz section
    signal lrck480_d : std_logic;
    signal in480_from625 : pcmLR_type;
    signal in480_from555 : pcmLR_type;

begin

    --
    -- 62.5kHz section
    --
    mix625 : addsat_LR_8
    port map(
        snd_clk, rst_n,
        lrck625,
        in625_0, vol625_0, mute625_0,
        in625_1, vol625_1, mute625_1,
        in625_2, vol625_2, mute625_2,
        in625_3, vol625_3, mute625_3,
        (others => (others => '0')), x"0", '0',
        (others => (others => '0')), x"0", '0',
        (others => (others => '0')), x"0", '0',
        (others => (others => '0')), x"0", '0',
        sum625
    );

    process (snd_clk, rst_n)
    begin
        if (rst_n = '0') then
            lrck625_d <= '0';
            cicup96_in_valid <= '0';
            cicup96_in_ready <= '0';
            cicup96_in_data <= (others => '0');
            cicup96_in_startofpacket <= '0';
            cicup96_in_endofpacket <= '0';
            avsend625_state <= AV_SEND_L;
        elsif (snd_clk' event and snd_clk = '1') then
            lrck625_d <= lrck625;

            case avsend625_state is
                when AV_SEND_L =>
                    if (lrck625 = '1' and lrck625_d = '0') then
                        cicup96_in_valid <= '1';
                        cicup96_in_ready <= '1';
                        cicup96_in_data <= sum625(0);
                        cicup96_in_startofpacket <= '1';
                        cicup96_in_endofpacket <= '0';
                        avsend625_state <= AV_SEND_R;
                    else
                        cicup96_in_valid <= '0';
                        cicup96_in_ready <= '0';
                        cicup96_in_data <= (others => '0');
                        cicup96_in_startofpacket <= '0';
                        cicup96_in_endofpacket <= '0';
                    end if;
                when AV_SEND_R =>
                    if (lrck625 = '0' and lrck625_d = '1') then
                        cicup96_in_valid <= '1';
                        cicup96_in_ready <= '1';
                        cicup96_in_data <= sum625(1);
                        cicup96_in_startofpacket <= '0';
                        cicup96_in_endofpacket <= '1';
                        avsend625_state <= AV_SEND_L;
                    else
                        cicup96_in_valid <= '0';
                        cicup96_in_ready <= '0';
                        cicup96_in_data <= (others => '0');
                        cicup96_in_startofpacket <= '0';
                        cicup96_in_endofpacket <= '0';
                    end if;
                when others =>
                    avsend625_state <= AV_SEND_L;
            end case;
        end if;
    end process;

    cic625_up96 : cic_up96
    port map(
        clk => snd_clk,
        reset_n => rst_n,
        in_valid => cicup96_in_valid,
        in_ready => cicup96_in_ready,
        in_data => cicup96_in_data,
        in_startofpacket => cicup96_in_startofpacket,
        in_endofpacket => cicup96_in_endofpacket,
        out_valid => cicup96_out_valid,
        out_ready => cicup96_out_ready,
        out_data => cicup96_out_data,
        out_startofpacket => cicup96_out_startofpacket,
        out_endofpacket => cicup96_out_endofpacket,
        out_channel => cicup96_out_channel
    );

    cicdown125_in_valid <= cicup96_out_valid;
    cicdown125_in_ready <= cicup96_out_ready;
    cicdown125_in_data <= cicup96_out_data;
    cicdown125_in_startofpacket <= cicup96_out_startofpacket;
    cicdown125_in_endofpacket <= cicup96_out_endofpacket;

    cic625_down125 : cic_down125
    port map(
        clk => snd_clk,
        reset_n => rst_n,
        in_valid => cicdown125_in_valid,
        in_ready => cicdown125_in_ready,
        in_data => cicdown125_in_data,
        in_startofpacket => cicdown125_in_startofpacket,
        in_endofpacket => cicdown125_in_endofpacket,
        out_valid => cicdown125_out_valid,
        out_ready => cicdown125_out_ready,
        out_data => cicdown125_out_data,
        out_startofpacket => cicdown125_out_startofpacket,
        out_endofpacket => cicdown125_out_endofpacket,
        out_channel => cicdown125_out_channel
    );

    process (snd_clk, rst_n)
    begin
        if (rst_n = '0') then
            cicdown125_in_valid <= '0';
            cicdown125_in_ready <= '0';
            cicdown125_in_data <= (others => '0');
            cicdown125_in_startofpacket <= '0';
            cicdown125_in_endofpacket <= '0';
            avrecv625_state <= AV_RECV_L;
            conv625 <= (others => (others => '0'));
        elsif (snd_clk' event and snd_clk = '1') then

            case avrecv625_state is
                when AV_RECV_L =>
                    if (cicdown125_out_valid = '1') then
                        if (cicdown125_out_startofpacket = '1' and cicdown125_out_endofpacket = '0') then
                            conv625(0) <= cicdown125_out_data;
                            avrecv625_state <= AV_RECV_R;
                        else
                            -- invalid state
                            avrecv625_state <= AV_RECV_L;
                        end if;
                    end if;
                when AV_RECV_R =>
                    if (cicdown125_out_valid = '1') then
                        if (cicdown125_out_startofpacket = '0' and cicdown125_out_endofpacket = '1') then
                            conv625(1) <= cicdown125_out_data;
                            avrecv625_state <= AV_RECV_L;
                        else
                            -- invalid state
                            avrecv625_state <= AV_RECV_L;
                        end if;
                    end if;
                when others =>
                    avsend625_state <= AV_SEND_L;
            end case;
        end if;
    end process;

    --
    -- 55.5kHz section
    --
    mix555 : addsat_LR_8
    port map(
        snd_clk, rst_n,
        lrck555,
        in555_0, vol555_0, mute555_0,
        in555_1, vol555_1, mute555_1,
        in555_2, vol555_2, mute555_2,
        in555_3, vol555_3, mute555_3,
        in555_4, vol555_4, mute555_4,
        in555_5, vol555_5, mute555_5,
        in555_6, vol555_6, mute555_6,
        in555_7, vol555_7, mute555_7,
        sum555
    );

    --
    -- 48.0kHz section
    --
    mix480 : addsat_LR_8
    port map(
        snd_clk, rst_n,
        lrck480,
        in480_from625, x"0", '0',
        in480_from555, x"0", '0',
        in480_0, vol480_0, mute480_0,
        in480_1, vol480_1, mute480_1,
        in480_2, vol480_2, mute480_2,
        in480_3, vol480_3, mute480_3,
        (others => (others => '0')), x"0", '0',
        (others => (others => '0')), x"0", '0',
        outq
    );

    process (snd_clk, rst_n)
    begin
        if (rst_n = '0') then
            lrck480_d <= '0';
            conv555 <= (others => (others => '0'));
        elsif (snd_clk' event and snd_clk = '1') then
            lrck480_d <= lrck480;
            conv555 <= sum555;

            if (lrck480 = '1' and lrck480_d = '0') then
                in480_from625 <= conv625;
                in480_from555 <= conv555;
            end if;
        end if;
    end process;
end rtl;