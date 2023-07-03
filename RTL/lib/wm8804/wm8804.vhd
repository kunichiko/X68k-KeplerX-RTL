library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.std_logic_arith.all;
use IEEE.STD_LOGIC_UNSIGNED.all;

-- # Reset
-- i2cset -y 1 0x3a 0x00 0x00
--
-- # Power Up
-- # b0: PLL Power          = 0 (up)
-- # b1: S/PDIF Recv  Power = 0 (up)
-- # b2: S/PDIF Trans Power = 0 (up)
-- # b3: Oscillator Power   = 0 (up)
-- # b4: Digital Audio I/F  = 0 (up)
-- # b5: Tri-state all Out  = 0 (Outputs not tri-stated)
-- i2cset -y 1 0x3a 0x1e 0x00
--
-- # b1-0:AIFTX_FMT = 10 (I2S mode)
-- # b3-2:AIFTX_WL  = 00 (16 bits)
-- i2cset -y 1 0x3a 0x1b 0x02
--
-- # b1-0:AIFRX_FMT = 10 (I2S mode)
-- # b3-2:AIFRX_WL  = 00 (16 bits)
-- # b6  :AIF_MS    = 0  (Slave mode)
-- # b7  :SYNC_OFF  = 0  (LRCLK, BCLK are not output when S/PDIF source has been removed)
-- i2cset -y 1 0x3a 0x1c 0x02
--
-- # b3-0:FREQ[3:0]   = 0001
-- # b5-4:CLKACU[1:0] = 11
-- # b6  :TXSRC       = 1  (Digial Audio Interface)
-- i2cset -y 1 0x3a 0x15 0x71
--
-- # b2-0:            = 000
-- # b3: CLKOUTSRC    = 0 (CLKOUT is CLK1)
-- # b4: CLKOUTDIS    = 0 (CLKOUT is disabled)
-- # b5: FILLMODE     = 1 (Error data is all zeros)
-- # b6: ALWAYSVALID  = 0 (Use INVALID flag)
-- # b7: MCLKSRC      = 0 (MCLK source is CLK2)
-- i2cset -y 1 0x3a 0x08 0x20
--
-- # INT MASK
-- # 上のFILLMODE = 1 を使いたいので、割り込みは全て無効にする
-- i2cset -y 1 0x3a 0x0a 0xff
entity wm8804 is
    port (
        TXOUT : out std_logic_vector(7 downto 0); --tx data in
        RXIN : in std_logic_vector(7 downto 0); --rx data out
        WRn : out std_logic; --write
        RDn : out std_logic; --read

        TXEMP : in std_logic; --tx buffer empty
        RXED : in std_logic; --rx buffered
        NOACK : in std_logic; --no ack
        COLL : in std_logic; --collision detect
        NX_READ : out std_logic; --next data is read
        RESTART : out std_logic; --make re-start condition
        START : out std_logic; --make start condition
        FINISH : out std_logic; --next data is final(make stop condition)
        F_FINISH : out std_logic; --next data is final(make stop condition) (force stop)
        INIT : out std_logic;

        clk : in std_logic;
        rstn : in std_logic
    );
end wm8804;

architecture rtl of wm8804 is
    type state_t is(
    IS_WAKEUP,
    -- IS_RESET,
    -- IS_RESET_REG,
    -- IS_RESET_DAT,
    -- IS_RESET_FIN,
    IS_POWERUP,
    IS_POWERUP_REG,
    IS_POWERUP_DAT,
    IS_POWERUP_FIN,
    IS_SET_AIF_TXFMT,
    IS_SET_AIF_TXFMT_REG,
    IS_SET_AIF_TXFMT_DAT,
    IS_SET_AIF_TXFMT_FIN,
    IS_SET_AIF_RXFMT,
    IS_SET_AIF_RXFMT_REG,
    IS_SET_AIF_RXFMT_DAT,
    IS_SET_AIF_RXFMT_FIN,
    IS_SET_TXFREQ_SRC,
    IS_SET_TXFREQ_SRC_REG,
    IS_SET_TXFREQ_SRC_DAT,
    IS_SET_TXFREQ_SRC_FIN,
    IS_SET_PLL6,
    IS_SET_PLL6_REG,
    IS_SET_PLL6_DAT,
    IS_SET_PLL6_FIN,
    IS_SET_INTMASK,
    IS_SET_INTMASK_REG,
    IS_SET_INTMASK_DAT,
    IS_SET_INTMASK_FIN,
    IS_IDLE
    );
    signal state : state_t;

--    signal wakeup_counter : std_logic_vector(10 downto 0); -- 100MHz (10nsec) * 2048 = 2usec
    signal wakeup_counter : std_logic_vector(16 downto 0); -- 100MHz (10nsec) * 2048 = 2usec

    constant SADR_WM8804 : std_logic_vector(6 downto 0) := "0111010"; -- 3a

begin
    process (clk, rstn)
    begin
        if (rstn = '0') then
            state <= IS_WAKEUP;
            wakeup_counter <= (others => '1');
            WRn <= '1';
            RDn <= '1';
            NX_READ <= '0';
            RESTART <= '0';
            START <= '0';
            FINISH <= '0';
            F_FINISH <= '0';
            INIT <= '0';
        elsif (clk' event and clk = '1') then
            WRn <= '1';
            RDn <= '1';
            F_FINISH <= '0';
            INIT <= '0';
            case state is
                when IS_WAKEUP =>
                    wakeup_counter <= wakeup_counter - 1;
                    if (wakeup_counter = 0) then
                        state <= IS_POWERUP;
                    end if;
                    -- RESET
                    -- when IS_RESET =>
                    --     if (TXEMP = '1') then
                    --         NX_READ <= '0';
                    --         RESTART <= '0';
                    --         START <= '1';
                    --         FINISH <= '0';
                    --         TXOUT <= SADR_WM8804 & '0'; -- WR
                    --         WRn <= '0';
                    --         state <= IS_RESET_REG;
                    --     end if;
                    -- when IS_RESET_REG =>
                    --     if (TXEMP = '1') then
                    --         NX_READ <= '0';
                    --         RESTART <= '0';
                    --         START <= '0';
                    --         FINISH <= '0';
                    --         TXOUT <= x"00"; -- reg: 0x00
                    --         WRn <= '0';
                    --         state <= IS_RESET_DAT;
                    --     end if;
                    -- when IS_RESET_DAT =>
                    --     if (TXEMP = '1') then
                    --         NX_READ <= '0';
                    --         RESTART <= '0';
                    --         START <= '0';
                    --         FINISH <= '1';
                    --         TXOUT <= x"00"; -- data : 0x00
                    --         WRn <= '0';
                    --         state <= IS_RESET_FIN;
                    --     end if;
                    -- when IS_RESET_FIN =>
                    --     if (TXEMP = '1') then
                    --         NX_READ <= '0';
                    --         RESTART <= '0';
                    --         START <= '0';
                    --         FINISH <= '0';
                    --         state <= IS_POWERUP;
                    --     end if;
                    -- POWER UP
                when IS_POWERUP =>
                    if (TXEMP = '1') then
                        NX_READ <= '0';
                        RESTART <= '0';
                        START <= '1';
                        FINISH <= '0';
                        TXOUT <= SADR_WM8804 & '0'; -- WR
                        WRn <= '0';
                        state <= IS_POWERUP_REG;
                    end if;
                when IS_POWERUP_REG =>
                    if (TXEMP = '1') then
                        NX_READ <= '0';
                        RESTART <= '0';
                        START <= '0';
                        FINISH <= '0';
                        TXOUT <= x"1e"; -- reg: 0x1e
                        WRn <= '0';
                        state <= IS_POWERUP_DAT;
                    end if;
                when IS_POWERUP_DAT =>
                    if (TXEMP = '1') then
                        NX_READ <= '0';
                        RESTART <= '0';
                        START <= '0';
                        FINISH <= '1';
                        TXOUT <= x"00"; -- data : 0x00
                        WRn <= '0';
                        state <= IS_POWERUP_FIN;
                    end if;
                when IS_POWERUP_FIN =>
                    if (TXEMP = '1') then
                        NX_READ <= '0';
                        RESTART <= '0';
                        START <= '0';
                        FINISH <= '0';
                        state <= IS_SET_AIF_TXFMT;
                    end if;
                    -- SET AIF TXFMT
                when IS_SET_AIF_TXFMT =>
                    if (TXEMP = '1') then
                        NX_READ <= '0';
                        RESTART <= '0';
                        START <= '1';
                        FINISH <= '0';
                        TXOUT <= SADR_WM8804 & '0'; -- WR
                        WRn <= '0';
                        state <= IS_SET_AIF_TXFMT_REG;
                    end if;
                when IS_SET_AIF_TXFMT_REG =>
                    if (TXEMP = '1') then
                        NX_READ <= '0';
                        RESTART <= '0';
                        START <= '0';
                        FINISH <= '0';
                        TXOUT <= x"1b"; -- reg: 0x1b
                        WRn <= '0';
                        state <= IS_SET_AIF_TXFMT_DAT;
                    end if;
                when IS_SET_AIF_TXFMT_DAT =>
                    if (TXEMP = '1') then
                        NX_READ <= '0';
                        RESTART <= '0';
                        START <= '0';
                        FINISH <= '1';
                        TXOUT <= x"02"; -- data : 0x02
                        WRn <= '0';
                        state <= IS_SET_AIF_TXFMT_FIN;
                    end if;
                when IS_SET_AIF_TXFMT_FIN =>
                    if (TXEMP = '1') then
                        NX_READ <= '0';
                        RESTART <= '0';
                        START <= '0';
                        FINISH <= '0';
                        state <= IS_SET_AIF_RXFMT;
                    end if;
                    -- SET AIF RXFMT
                when IS_SET_AIF_RXFMT =>
                    if (TXEMP = '1') then
                        NX_READ <= '0';
                        RESTART <= '0';
                        START <= '1';
                        FINISH <= '0';
                        TXOUT <= SADR_WM8804 & '0'; -- WR
                        WRn <= '0';
                        state <= IS_SET_AIF_RXFMT_REG;
                    end if;
                when IS_SET_AIF_RXFMT_REG =>
                    if (TXEMP = '1') then
                        NX_READ <= '0';
                        RESTART <= '0';
                        START <= '0';
                        FINISH <= '0';
                        TXOUT <= x"1c"; -- reg: 0x1c
                        WRn <= '0';
                        state <= IS_SET_AIF_RXFMT_DAT;
                    end if;
                when IS_SET_AIF_RXFMT_DAT =>
                    if (TXEMP = '1') then
                        NX_READ <= '0';
                        RESTART <= '0';
                        START <= '0';
                        FINISH <= '1';
                        TXOUT <= x"02"; -- data : 0x02
                        WRn <= '0';
                        state <= IS_SET_AIF_RXFMT_FIN;
                    end if;
                when IS_SET_AIF_RXFMT_FIN =>
                    if (TXEMP = '1') then
                        NX_READ <= '0';
                        RESTART <= '0';
                        START <= '0';
                        FINISH <= '0';
                        state <= IS_SET_TXFREQ_SRC;
                    end if;
                    -- SET TX FREQ and SRC
                when IS_SET_TXFREQ_SRC =>
                    if (TXEMP = '1') then
                        NX_READ <= '0';
                        RESTART <= '0';
                        START <= '1';
                        FINISH <= '0';
                        TXOUT <= SADR_WM8804 & '0'; -- WR
                        WRn <= '0';
                        state <= IS_SET_TXFREQ_SRC_REG;
                    end if;
                when IS_SET_TXFREQ_SRC_REG =>
                    if (TXEMP = '1') then
                        NX_READ <= '0';
                        RESTART <= '0';
                        START <= '0';
                        FINISH <= '0';
                        TXOUT <= x"15"; -- reg: 0x15
                        WRn <= '0';
                        state <= IS_SET_TXFREQ_SRC_DAT;
                    end if;
                when IS_SET_TXFREQ_SRC_DAT =>
                    if (TXEMP = '1') then
                        NX_READ <= '0';
                        RESTART <= '0';
                        START <= '0';
                        FINISH <= '1';
                        TXOUT <= x"71"; -- data : 0x71
                        WRn <= '0';
                        state <= IS_SET_TXFREQ_SRC_FIN;
                    end if;
                when IS_SET_TXFREQ_SRC_FIN =>
                    if (TXEMP = '1') then
                        NX_READ <= '0';
                        RESTART <= '0';
                        START <= '0';
                        FINISH <= '0';
                        state <= IS_SET_PLL6;
                    end if;
                    -- SET PLL6
                when IS_SET_PLL6 =>
                    if (TXEMP = '1') then
                        NX_READ <= '0';
                        RESTART <= '0';
                        START <= '1';
                        FINISH <= '0';
                        TXOUT <= SADR_WM8804 & '0'; -- WR
                        WRn <= '0';
                        state <= IS_SET_PLL6_REG;
                    end if;
                when IS_SET_PLL6_REG =>
                    if (TXEMP = '1') then
                        NX_READ <= '0';
                        RESTART <= '0';
                        START <= '0';
                        FINISH <= '0';
                        TXOUT <= x"08"; -- reg: 0x08
                        WRn <= '0';
                        state <= IS_SET_PLL6_DAT;
                    end if;
                when IS_SET_PLL6_DAT =>
                    if (TXEMP = '1') then
                        NX_READ <= '0';
                        RESTART <= '0';
                        START <= '0';
                        FINISH <= '1';
                        TXOUT <= x"20"; -- data : 0x20
                        WRn <= '0';
                        state <= IS_SET_PLL6_FIN;
                    end if;
                when IS_SET_PLL6_FIN =>
                    if (TXEMP = '1') then
                        NX_READ <= '0';
                        RESTART <= '0';
                        START <= '0';
                        FINISH <= '0';
                        state <= IS_SET_INTMASK;
                    end if;
                    -- SET INTMASK
                    when IS_SET_INTMASK =>
                    if (TXEMP = '1') then
                        NX_READ <= '0';
                        RESTART <= '0';
                        START <= '1';
                        FINISH <= '0';
                        TXOUT <= SADR_WM8804 & '0'; -- WR
                        WRn <= '0';
                        state <= IS_SET_INTMASK_REG;
                    end if;
                when IS_SET_INTMASK_REG =>
                    if (TXEMP = '1') then
                        NX_READ <= '0';
                        RESTART <= '0';
                        START <= '0';
                        FINISH <= '0';
                        TXOUT <= x"0A"; -- reg: 0x0A
                        WRn <= '0';
                        state <= IS_SET_INTMASK_DAT;
                    end if;
                when IS_SET_INTMASK_DAT =>
                    if (TXEMP = '1') then
                        NX_READ <= '0';
                        RESTART <= '0';
                        START <= '0';
                        FINISH <= '1';
                        TXOUT <= x"FF"; -- data : 0xFF
                        WRn <= '0';
                        state <= IS_SET_INTMASK_FIN;
                    end if;
                when IS_SET_INTMASK_FIN =>
                    if (TXEMP = '1') then
                        NX_READ <= '0';
                        RESTART <= '0';
                        START <= '0';
                        FINISH <= '0';
                        state <= IS_IDLE;
                    end if;
                when IS_IDLE =>
                    state <= IS_IDLE;
                when others =>
                    state <= IS_IDLE;
            end case;
        end if;
    end process;
end;