library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.STD_LOGIC_ARITH.all;
use IEEE.STD_LOGIC_UNSIGNED.all;
use work.X68KeplerX_pkg.all;

--
-- Command list (see https://github.com/dwhinham/mt32-pi/wiki/Custom-System-Exclusive-messages)
--
-- ● 0 Reboot the Raspberry Pi
--
-- ● 1 Switch ROM set
-- param: 
--  00: MT-32 (old)
--  01: MT-32 (new)
--  02: CM-32L
--
-- ● 2 Switch Sound Font
-- param:
--  xx: Zero-based index into contents of soundfonts directory (lexicographically sorted).
--
-- ● 3 Switch synthesizer
-- param:
--  00: MT-32
--  01: SoundFont
-- 
-- ● 4 Enable/disable MT-32 reversed stereo
-- param:
--  00: Disabled
--  01: Enabled (panpot CC values are inverted)
--
entity mt32pi_ctrl is
    generic (
        sysclk : integer := 25000
    );
    port (
        sys_clk : in std_logic;
        sys_rstn : in std_logic;
        req : in std_logic;
        ack : out std_logic;

        rw : in std_logic;
        --        addr : in std_logic_vector(2 downto 0);
        idata : in std_logic_vector(15 downto 0);
        odata : out std_logic_vector(15 downto 0);

        txd_ext : in std_logic;
        active_ext : in std_logic;

        txd : out std_logic;
        active : out std_logic
    );
end mt32pi_ctrl;

architecture rtl of mt32pi_ctrl is
    type bus_state_t is(
    BUS_IDLE,
    BUS_WR_ACK,
    BUS_RD_ACK
    );
    signal bus_state : bus_state_t;

    type exmes_state_t is(
    EXMES_IDLE,
    EXMES_WAITING,
    EXMES_SEND_F0,
    EXMES_SEND_7D,
    EXMES_SEND_COMMAND,
    EXMES_SEND_PARAMETER,
    EXMES_SEND_F7,
    EXMES_FIN
    );
    signal exmes_state : exmes_state_t;

    constant divtx : integer := (sysclk * 1000)/31250; -- 25MHzの時 800
    signal counttx : integer range 0 to divtx;
    signal sfttx : std_logic;
    signal iactive : std_logic;

    signal exmes_req : std_logic;
    signal exmes_ack : std_logic;
    signal command : integer range 0 to 4;
    signal param : std_logic_vector(7 downto 0);

    signal sendword : std_logic_vector(7 downto 0);
    signal sending : std_logic_vector(15 downto 0);
    signal send_req : std_logic;
    signal send_ack : std_logic;
    signal bit_counter : integer range 0 to 15;
begin

    process (sys_clk, sys_rstn)
    begin
        if (sys_rstn = '0') then
            bus_state <= BUS_IDLE;
            ack <= '0';
            -- リセット直後にmt32-piのリセットを送る
            command <= 0;
            param <= (others => '0');
            exmes_req <= '1';
        elsif (sys_clk' event and sys_clk = '1') then
            if (exmes_ack = '0') then
                exmes_req <= '0';
            end if;

            case bus_state is
                when BUS_IDLE =>
                    if req = '1' then
                        if rw = '0' then
                            bus_state <= BUS_WR_ACK;
                            exmes_req <= '1';
                            command <= CONV_INTEGER(idata(11 downto 8));
                            param <= idata(7 downto 0);
                            ack <= '1';
                        else
                            bus_state <= BUS_RD_ACK;
                            odata <= iactive & "0000000" & x"00";
                            ack <= '1';
                        end if;
                    end if;

                    -- write cycle
                when BUS_WR_ACK =>
                    if req = '1' then
                        ack <= '1';
                    else
                        ack <= '0';
                        bus_state <= BUS_IDLE;
                    end if;

                    -- read cycle
                when BUS_RD_ACK =>
                    if req = '1' then
                        ack <= '1';
                    else
                        ack <= '0';
                        bus_state <= BUS_IDLE;
                    end if;
                when others =>
                    bus_state <= BUS_IDLE;
            end case;
        end if;
    end process;

    process (sys_clk, sys_rstn)
    begin
        if (sys_rstn = '0') then
            exmes_state <= EXMES_IDLE;
            exmes_ack <= '0';
            sendword <= (others => '0');
            send_req <= '0';
        elsif (sys_clk' event and sys_clk = '1') then
            case exmes_state is
                when EXMES_IDLE =>
                    send_req <= '0';
                    if (exmes_req = '1') then
                        exmes_state <= EXMES_WAITING;
                    end if;
                when EXMES_WAITING =>
                    -- MIDI 出力が空くのを待つ
                    if (active_ext = '0') then
                        exmes_state <= EXMES_SEND_F0;
                    end if;
                when EXMES_SEND_F0 =>
                    sendword <= x"f0";
                    send_req <= '1';
                    if (send_ack = '1') then
                        exmes_state <= EXMES_SEND_7D;
                        send_req <= '0';
                    end if;
                when EXMES_SEND_7D =>
                    sendword <= x"7d";
                    send_req <= '1';
                    if (send_ack = '1') then
                        exmes_state <= EXMES_SEND_COMMAND;
                        send_req <= '0';
                    end if;
                when EXMES_SEND_COMMAND =>
                    sendword <= CONV_STD_LOGIC_VECTOR(command, 8);
                    send_req <= '1';
                    if (send_ack = '1') then
                        if (command = 0) then
                            exmes_state <= EXMES_SEND_F7;
                        else
                            exmes_state <= EXMES_SEND_PARAMETER;
                        end if;
                        send_req <= '0';
                    end if;
                when EXMES_SEND_PARAMETER =>
                    sendword <= param;
                    send_req <= '1';
                    if (send_ack = '1') then
                        exmes_state <= EXMES_SEND_F7;
                        send_req <= '0';
                    end if;
                when EXMES_SEND_F7 =>
                    sendword <= x"f7";
                    send_req <= '1';
                    if (send_ack = '1') then
                        exmes_state <= EXMES_FIN;
                        send_req <= '0';
                        exmes_ack <= '1';
                    end if;
                when EXMES_FIN =>
                    if (exmes_req = '0') then
                        exmes_ack <= '0';
                        exmes_state <= EXMES_IDLE;
                    end if;
                when others =>
                    exmes_state <= EXMES_IDLE;
            end case;
        end if;
    end process;

    process (sys_clk, sys_rstn)
    begin
        if (sys_rstn = '0') then
            bit_counter <= 0;
            send_ack <= '0';
            sending <= (others => '1');
        elsif (sys_clk' event and sys_clk = '1') then
            send_ack <= '0';
            if (sfttx = '1') then
                case bit_counter is
                    when 0 =>
                        send_ack <= '0';
                        if (send_req = '1') then
                            sending <= "1111111" & sendword & '0'; -- stop bit = '1', start bit = '0'
                            bit_counter <= 15;
                        end if;
                    when others =>
                        bit_counter <= bit_counter - 1;
                        sending <= '1' & sending(15 downto 1);
                        if (bit_counter = 1) then
                            send_ack <= '1';
                        end if;
                end case;
            end if;
        end if;
    end process;

    process (sys_clk, sys_rstn)
    begin
        if (sys_rstn = '0') then
            counttx <= divtx - 1;
            sfttx <= '0';
        elsif (sys_clk' event and sys_clk = '1') then
            sfttx <= '0';
            if (counttx = 0) then
                sfttx <= '1';
                counttx <= divtx - 1;
            else
                counttx <= counttx - 1;
            end if;
        end if;
    end process;

    iactive <= '0' when exmes_state = EXMES_IDLE else '1';
    active <= iactive;
    txd <= sending(0) when (exmes_state /= EXMES_IDLE) and (exmes_state /= EXMES_WAITING) else
        txd_ext;
end rtl;