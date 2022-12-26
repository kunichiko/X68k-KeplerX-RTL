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
        command : in integer range 0 to 4;
        param : in std_logic_vector(7 downto 0);
        req : in std_logic;
        ack : out std_logic;

        active : out std_logic;
        txd : out std_logic;

        sys_clk : in std_logic;
        sys_rstn : in std_logic
    );
end mt32pi_ctrl;

architecture rtl of mt32pi_ctrl is
    type state_t is(
    IDLE,
    SEND_F0,
    SEND_7D,
    SEND_COMMAND,
    SEND_PARAMETER,
    SEND_F7,
    FIN
    );
    signal state : state_t;

    constant divtx : integer := (sysclk * 1000)/31250; -- 25MHzの時 800
    signal counttx : integer range 0 to divtx;
    signal sfttx : std_logic;

    signal sendword : std_logic_vector(7 downto 0);
    signal sending : std_logic_vector(15 downto 0);
    signal send_req : std_logic;
    signal send_ack : std_logic;
    signal bit_counter : integer range 0 to 15;
begin

    process (sys_clk, sys_rstn)
    begin
        if (sys_rstn = '0') then
            state <= IDLE;
            ack <= '0';
            sendword <= (others => '0');
            send_req <= '0';
        elsif (sys_clk' event and sys_clk = '1') then
            case state is
                when IDLE =>
                    send_req <= '0';
                    if (req = '1') then
                        state <= SEND_F0;
                    end if;
                when SEND_F0 =>
                    sendword <= x"f0";
                    send_req <= '1';
                    if (send_ack = '1') then
                        state <= SEND_7D;
                        send_req <= '0';
                    end if;
                when SEND_7D =>
                    sendword <= x"7d";
                    send_req <= '1';
                    if (send_ack = '1') then
                        state <= SEND_COMMAND;
                        send_req <= '0';
                    end if;
                when SEND_COMMAND =>
                    sendword <= CONV_STD_LOGIC_VECTOR(command, 8);
                    send_req <= '1';
                    if (send_ack = '1') then
                        if (command = 0) then
                            state <= SEND_F7;
                        else
                            state <= SEND_PARAMETER;
                        end if;
                        send_req <= '0';
                    end if;
                when SEND_PARAMETER =>
                    sendword <= param;
                    send_req <= '1';
                    if (send_ack = '1') then
                        state <= SEND_F7;
                        send_req <= '0';
                    end if;
                when SEND_F7 =>
                    sendword <= x"f7";
                    send_req <= '1';
                    if (send_ack = '1') then
                        state <= FIN;
                        send_req <= '0';
                        ack <= '1';
                    end if;
                when FIN =>
                    if (req = '0') then
                        ack <= '0';
                        state <= IDLE;
                    end if;
                when others =>
                    state <= IDLE;
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

    active <= '0' when state = IDLE else '1';
    txd <= '1' when bit_counter = 0 else sending(0);
end rtl;