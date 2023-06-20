library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.STD_LOGIC_ARITH.all;
use IEEE.STD_LOGIC_UNSIGNED.all;
use work.X68KeplerX_pkg.all;

--
-- MIDIメッセージの送受信を制御するモジュール
--
-- 本モジュールは以下の制御を行います。
--
--  * Kepler-X の MIDIメッセージのルーティング制御
--  * 全ての送信先に All notes offメッセージを送る機能 (リセット後にトップエンティティからトリガーされる)
--  * mt32-pi の特殊コマンドの送信(サウンドフォントの切り替えなど)
--
-- ## Host interface
-- 
-- ### MIDI ルーティング
-- MIDIのルーティングは、トップエンティティからの制御信号によって行います。
--  * midi_routing_ext: 外部MIDI-OUTへのルーティング ("00": None, "01": Source1, "10": Source2, "11": Source3)
--  * midi_routing_mt32pi: mt32-piへのルーティング ("00": None, "01": Source1, "10": Source2, "11": Source3)
--
-- ### all notes off
-- 全ての送信先に All notes offメッセージを送る機能は、トップエンティティからの制御信号によって行います。
--  * all_notes_off_req: 全ての送信先に All notes offメッセージを送る要求
--  * all_notes_off_ack: 全ての送信先に All notes offメッセージを送る要求の完了を通知
-- この機能は Kepler-X のリセット後にトップエンティティからトリガーされます。
--
-- ### mt32-pi コントロールメッセージ
-- mt32-piの特殊コマンドは、ホストからのバスアクセスによって行います。
--  * req: バスアクセス要求
--  * rw: リード/ライト指定 ("0": ライト, "1": リード)
--      * 書き込み時 idata: (上位) コマンド番号(0-4), (下位) パラメータ
--      * 読み込み時 odata: bit15: 送信中フラグ
--
-- mt32-piの特殊コマンドは後述する mt32-pi control message に従います。
-- 
--
-- ## mt32-pi control message
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
entity midi_ctrl is
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

        -- All notes off request
        all_notes_off_req : in std_logic;
        all_notes_off_ack : out std_logic;

        -- MIDI sources
        midi_source_1 : in std_logic; -- 3802の出力
        midi_source_1_active : in std_logic; -- 送信中は '1'
        midi_source_2 : in std_logic; -- 外部MIDI入力
        midi_source_2_active : in std_logic; -- 送信中は '1'
        midi_source_3 : in std_logic; -- 予備
        midi_source_3_active : in std_logic; -- 予備

        -- MIDI outputs
        midi_out_ext : out std_logic; -- 外部MIDI-OUTへの出力
        midi_out_mt32pi : out std_logic; -- mt32-piへの出力

        -- MIDI routing
        midi_routing_ext : in std_logic_vector(1 downto 0); --  ("00": None, "01": Source1, "10": Source2, "11": Source3)
        midi_routing_mt32pi : in std_logic_vector(1 downto 0); --  ("00": None, "01": Source1, "10": Source2, "11": Source3)

        sending_ctrl_msg : out std_logic -- MIDI コントロールメッセージ送信中は '1'
    );
end midi_ctrl;

architecture rtl of midi_ctrl is
    type bus_state_t is(
    BUS_IDLE,
    BUS_WR_ACK,
    BUS_RD_ACK
    );
    signal bus_state : bus_state_t;

    type mctrl_state_t is(
    MCTRL_IDLE,
    MCTRL_SEND_F0,
    MCTRL_SEND_7D,
    MCTRL_SEND_COMMAND,
    MCTRL_SEND_PARAMETER,
    MCTRL_SEND_F7,
    MCTRL_ANOFF_SEND_Bn, -- n: Channel number
    MCTRL_ANOFF_SEND_7B, -- 0x7B: 123 (All notes off)
    MCTRL_ANOFF_SEND_00, -- 0x00: dummy
    MCTRL_ANOFF_WAIT,
    MCTRL_ASOFF_SEND_Bn, -- n: Channel number
    MCTRL_ASOFF_SEND_78, -- 0x7B: 120 (All sound off)
    MCTRL_ASOFF_SEND_00, -- 0x00: dummy
    MCTRL_ASOFF_WAIT,
    MCTRL_FIN
    );
    signal mctrl_state : mctrl_state_t;

    constant divtx : integer := (sysclk * 1000)/31250; -- 100MHzの時 3200
    signal counttx : integer range 0 to divtx;
    signal sfttx : std_logic;
    signal iactive : std_logic;

    signal exmes_req : std_logic;
    signal exmes_ack : std_logic;
    signal command : integer range 0 to 4;
    signal param : std_logic_vector(7 downto 0);

    signal i_all_notes_off_ack : std_logic;

    signal sendword : std_logic_vector(7 downto 0);
    signal sending : std_logic_vector(15 downto 0);
    signal send_req : std_logic;
    signal send_ack : std_logic;
    signal bit_counter : integer range 0 to 15;

    signal channel : std_logic_vector(3 downto 0);
    signal wait_counter : std_logic_vector(3 downto 0);

    signal txd : std_logic;
begin

    process (sys_clk, sys_rstn)
    begin
        if (sys_rstn = '0') then
            midi_out_ext <= '1';
            midi_out_mt32pi <= '1';
        elsif (sys_clk' event and sys_clk = '1') then
            if (mctrl_state /= MCTRL_IDLE and all_notes_off_req = '1') then
                midi_out_ext <= txd;
            else
                case midi_routing_ext is
                    when "01" =>
                        midi_out_ext <= midi_source_1;
                    when "10" =>
                        midi_out_ext <= midi_source_2;
                    when "11" =>
                        midi_out_ext <= midi_source_3;
                    when others =>
                        midi_out_ext <= '1';
                end case;
            end if;

            if (mctrl_state /= MCTRL_IDLE) then
                midi_out_mt32pi <= txd;
            else
                case midi_routing_mt32pi is
                    when "01" =>
                        midi_out_mt32pi <= midi_source_1;
                    when "10" =>
                        midi_out_mt32pi <= midi_source_2;
                    when "11" =>
                        midi_out_mt32pi <= midi_source_3;
                    when others =>
                        midi_out_mt32pi <= '1';
                end case;
            end if;
        end if;
    end process;

    process (sys_clk, sys_rstn)
    begin
        if (sys_rstn = '0') then
            bus_state <= BUS_IDLE;
            ack <= '0';
            command <= 0;
            param <= (others => '0');
            exmes_req <= '1';
        elsif (sys_clk' event and sys_clk = '1') then
            if (exmes_ack = '0') then
                exmes_req <= '0';
            end if;

            case bus_state is
                when BUS_IDLE =>
                    -- ホストからのバスアクセス                
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
            mctrl_state <= MCTRL_IDLE;
            exmes_ack <= '0';
            i_all_notes_off_ack <= '0';
            channel <= (others => '0');
            sendword <= (others => '0');
            send_req <= '0';
        elsif (sys_clk' event and sys_clk = '1') then
            case mctrl_state is
                when MCTRL_IDLE =>
                    send_req <= '0';
                    -- MIDI出力が空いている時にリクエストが来るのを待つ
                    if (midi_source_1_active = '0' and
                        midi_source_2_active = '0' and
                        midi_source_3_active = '0') then
                        if (exmes_req = '1') then
                            mctrl_state <= MCTRL_SEND_F0;
                        elsif (all_notes_off_req = '1') then
                            mctrl_state <= MCTRL_ANOFF_SEND_Bn;
                            channel <= (others => '0');
                        end if;
                    end if;
                    -- mt32-pi control message
                when MCTRL_SEND_F0 =>
                    sendword <= x"f0";
                    send_req <= '1';
                    if (send_ack = '1') then
                        mctrl_state <= MCTRL_SEND_7D;
                        send_req <= '0';
                    end if;
                when MCTRL_SEND_7D =>
                    sendword <= x"7d";
                    send_req <= '1';
                    if (send_ack = '1') then
                        mctrl_state <= MCTRL_SEND_COMMAND;
                        send_req <= '0';
                    end if;
                when MCTRL_SEND_COMMAND =>
                    sendword <= CONV_STD_LOGIC_VECTOR(command, 8);
                    send_req <= '1';
                    if (send_ack = '1') then
                        if (command = 0) then
                            mctrl_state <= MCTRL_SEND_F7;
                        else
                            mctrl_state <= MCTRL_SEND_PARAMETER;
                        end if;
                        send_req <= '0';
                    end if;
                when MCTRL_SEND_PARAMETER =>
                    sendword <= param;
                    send_req <= '1';
                    if (send_ack = '1') then
                        mctrl_state <= MCTRL_SEND_F7;
                        send_req <= '0';
                    end if;
                when MCTRL_SEND_F7 =>
                    sendword <= x"f7";
                    send_req <= '1';
                    if (send_ack = '1') then
                        mctrl_state <= MCTRL_FIN;
                        send_req <= '0';
                        exmes_ack <= '1';
                    end if;

                    -- All notes off
                when MCTRL_ANOFF_SEND_Bn =>
                    sendword <= x"B" & channel;
                    send_req <= '1';
                    if (send_ack = '1') then
                        mctrl_state <= MCTRL_ANOFF_SEND_7B; -- 0x7B: 123 (All notes off)
                        send_req <= '0';
                    end if;
                when MCTRL_ANOFF_SEND_7B =>
                    sendword <= x"7B";
                    send_req <= '1';
                    if (send_ack = '1') then
                        mctrl_state <= MCTRL_ANOFF_SEND_00; -- 0x00: dummy
                        send_req <= '0';
                    end if;
                when MCTRL_ANOFF_SEND_00 =>
                    sendword <= x"00";
                    send_req <= '1';
                    if (send_ack = '1') then
                        mctrl_state <= MCTRL_ANOFF_WAIT;
                        send_req <= '0';
                        wait_counter <= x"f";
                    end if;
                when MCTRL_ANOFF_WAIT =>
                    if (wait_counter = 0) then
                        mctrl_state <= MCTRL_ASOFF_SEND_Bn;
                    else
                        if (sfttx = '1') then
                            wait_counter <= wait_counter - 1;
                        end if;
                    end if;
                when MCTRL_ASOFF_SEND_Bn =>
                    sendword <= x"B" & channel;
                    send_req <= '1';
                    if (send_ack = '1') then
                        mctrl_state <= MCTRL_ASOFF_SEND_78; -- 0x78: 120 (All sound off)
                        send_req <= '0';
                    end if;
                when MCTRL_ASOFF_SEND_78 =>
                    sendword <= x"78";
                    send_req <= '1';
                    if (send_ack = '1') then
                        mctrl_state <= MCTRL_ASOFF_SEND_00; -- 0x00: dummy
                        send_req <= '0';
                    end if;
                when MCTRL_ASOFF_SEND_00 =>
                    sendword <= x"00";
                    send_req <= '1';
                    if (send_ack = '1') then
                        mctrl_state <= MCTRL_ASOFF_WAIT;
                        send_req <= '0';
                        wait_counter <= x"f";
                    end if;
                when MCTRL_ASOFF_WAIT =>
                    if (wait_counter = 0) then
                        if (channel = "1111") then
                            mctrl_state <= MCTRL_FIN;
                            send_req <= '0';
                            i_all_notes_off_ack <= '1';
                        else
                            channel <= channel + 1;
                            mctrl_state <= MCTRL_ANOFF_SEND_Bn;
                            send_req <= '0';
                        end if;
                    else
                        if (sfttx = '1') then
                            wait_counter <= wait_counter - 1;
                        end if;
                    end if;

                    -- finish
                when MCTRL_FIN =>
                    if (exmes_ack = '1' and exmes_req = '0') then
                        exmes_ack <= '0';
                        mctrl_state <= MCTRL_IDLE;
                    end if;
                    if (i_all_notes_off_ack = '1' and all_notes_off_req = '0') then
                        i_all_notes_off_ack <= '0';
                        mctrl_state <= MCTRL_IDLE;
                    end if;

                when others =>
                    mctrl_state <= MCTRL_IDLE;
            end case;
        end if;
    end process;

    all_notes_off_ack <= i_all_notes_off_ack;

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

    iactive <= '0' when mctrl_state = MCTRL_IDLE else '1';
    sending_ctrl_msg <= iactive;
    txd <= sending(0) when (mctrl_state /= MCTRL_IDLE) else '1';

end rtl;