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
    signal sum625 : pcmLR_type;
    signal sum555 : pcmLR_type;
    signal conv625 : pcmLR_type;
    signal conv555 : pcmLR_type;

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
begin

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


    mix480 : addsat_LR_8
	port map(
		snd_clk, rst_n,
        lrck480,
        conv625, x"0", '0',
        conv555, x"0", '0',
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
        elsif (snd_clk' event and snd_clk = '1') then
            conv625 <= sum625;
            conv555 <= sum555;
        end if;
    end process;
end rtl;