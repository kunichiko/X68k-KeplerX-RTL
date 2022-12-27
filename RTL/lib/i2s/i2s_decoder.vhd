--
--  i2s_decoder.vhd
--
--    Copyright (C)2022 Kunihiko Ohnaka All rights reserved.
--
library IEEE;

use IEEE.STD_LOGIC_1164.all;
use IEEE.STD_LOGIC_ARITH.all;
use IEEE.STD_LOGIC_UNSIGNED.all;

-- i2s_encoderの逆の動作を行います。
--
-- ● I2S入力仕様について
-- 48kHz 32bit フォーマットを、MCK(SCK)を使わない 3線式のI2Sで入力することを
-- 想定しています
-- i2s_bclk: 48kHz * 32 * 2(ステレオ) で 3.072MHzとなります
-- i2s_lrck: i2s_bclkに同期したLRクロックです
-- i2s_data: i2s_bclkに同期したデータです
--
-- 本モジュールは上記3つのクロックを snd_clk (16MHz) でサンプリングし、
-- snd_clkに同期した、16bitステレオのPCMデータに復元します。

entity i2s_decoder is
    port (
        snd_clk : in std_logic;

        i2s_data : in std_logic;
        i2s_lrck : in std_logic;
        i2s_bclk : in std_logic; -- I2S BCLK (Bit Clock) 3.072MHz (=48kHz * 64)

        detected : out std_logic;

        snd_pcmL : out std_logic_vector(31 downto 0);
        snd_pcmR : out std_logic_vector(31 downto 0);

        rstn : in std_logic
    );
end i2s_decoder;

architecture rtl of i2s_decoder is
    signal i2s_data_d : std_logic;
    signal i2s_lrck_d : std_logic;
    signal i2s_lrck_dd : std_logic;
    signal i2s_bclk_d : std_logic;
    signal i2s_bclk_dd : std_logic;

    signal i2s_data_v : std_logic_vector(63 downto 0);

    signal watchdog_bclk : std_logic_vector(3 downto 0);
    signal watchdog_lrck : std_logic_vector(7 downto 0);
begin

    process (snd_clk, rstn)
    begin
        if (rstn = '0') then
            i2s_data_d <= '0';
            i2s_lrck_d <= '0';
            i2s_bclk_d <= '0';
            i2s_bclk_dd <= '0';
            i2s_data_v <= (others => '0');
            watchdog_bclk <= (others => '0');
            watchdog_lrck <= (others => '0');
            detected <= '0';
        elsif (snd_clk' event and snd_clk = '1') then
            -- メタステーブル回避
            i2s_data_d <= i2s_data;
            i2s_lrck_d <= i2s_lrck;
            i2s_bclk_d <= i2s_bclk;
            i2s_bclk_dd <= i2s_bclk_d;

            -- 無信号検出
            watchdog_bclk <= watchdog_bclk + 1;
            if (watchdog_bclk = "1111" or watchdog_lrck = "11111111") then
                -- 一定期間BCLKもLRCKを検出しなかったら強制的に消音にする
                -- (カウンタが1111の後0000に戻って再カウントするのは意図的)
                snd_pcmL <= (others => '0');
                snd_pcmR <= (others => '0');
                detected <= '0';
            end if;

            -- bclk のエッジ検出
            if (i2s_bclk_dd = '0' and i2s_bclk_d = '1') then -- rising edge
                i2s_data_v <= i2s_data_v(62 downto 0) & i2s_data_d;

                watchdog_bclk <= (others => '0');
                watchdog_lrck <= watchdog_lrck + 1;
                i2s_lrck_dd <= i2s_lrck_d;
                if (i2s_lrck_dd = '1' and i2s_lrck_d = '0') then
                    snd_pcmL <= i2s_data_v(63 downto 32);
                    snd_pcmR <= i2s_data_v(31 downto 0);
                    watchdog_lrck <= (others => '0');
                    detected <= '1';
                end if;
            end if;
        end if;
    end process;
end rtl;