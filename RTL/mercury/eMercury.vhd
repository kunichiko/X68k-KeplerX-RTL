library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.STD_LOGIC_UNSIGNED.all;
use work.X68KeplerX_pkg.all;

--
-- ●まーきゅりーゆにっとV4 (MK-MU1)の仕様
-- 
-- まーきゅりーゆにっとのドライバ(mdrv088)のソースコード(MercuryDrive.s)などから推測して
-- 実装しています。
--
-- ● 1. 占有アドレス
-- 0xecc000〜0xecdfff
-- ┗ 0xecc080       PCMデータレジスタ
-- ┗ 0xecc090       PCMモードレジスタ
-- ┗ 0xecc091       PCMコマンドレジスタ
-- ┗ 0xecc0a1       PCMステータスレジスタ
-- ┗ 0xecc0b1       割り込みベクタ設定レジスタ
-- ┗ 0xecc0c1       OPNAマスター:レジスタ0
-- ┗ 0xecc0c3       OPNAマスター:データ0
-- ┗ 0xecc0c5       OPNAマスター:レジスタ1
-- ┗ 0xecc0c7       OPNAマスター:データ1
-- ┗ 0xecc0c9       OPNAスレーブ:レジスタ0
-- ┗ 0xecc0cb       OPNAスレーブ:データ0
-- ┗ 0xecc0cd       OPNAスレーブ:レジスタ1
-- ┗ 0xecc0cf       OPNAスレーブ:データ1
--
-- ● 2. アーキテクチャ
--
-- KeplerXの内部PCM周波数は 62.5kHzなので、本来はサンプリングレート変換が必要に
-- なりますが、一旦正しいレート変換はせずに直接受け渡します
--
-- MF-MU1に実装されていたのは YMF288のようですが、KeplerXでは jt12という
-- YM2610(OPNB)の互換実装を利用します。
-- https://github.com/jotego/jt12

entity eMercury is
    generic (
        NUM_OPNS : integer := 2
    );
    port (
        sys_clk : in std_logic;
        sys_rstn : in std_logic;
        req : in std_logic;
        ack : out std_logic;

        rw : in std_logic;
        addr : in std_logic_vector(7 downto 0);
        idata : in std_logic_vector(15 downto 0);
        odata : out std_logic_vector(15 downto 0);

        irq_n : out std_logic;

        drq_n : out std_logic;
        dack_n : in std_logic;

        pcl_en : out std_logic;
        pcl : out std_logic;

        -- specific i/o
        snd_clk : in std_logic;
        pcmL : out pcm_type;
        pcmR : out pcm_type
    );
end eMercury;

architecture rtl of eMercury is

    -- module jt12 (
    --     input           rst,        // rst should be at least 6 clk&cen cycles long
    --     input           clk,        // CPU clock
    --     input           cen,        // optional clock enable, if not needed leave as 1'b1
    --     input   [7:0]   din,
    --     input   [1:0]   addr,
    --     input           cs_n,
    --     input           wr_n,

    --     output  [7:0]   dout,
    --     output          irq_n,
    --     // configuration
    --     input           en_hifi_pcm,
    --     // combined output
    --     output  signed  [15:0]  snd_right,
    --     output  signed  [15:0]  snd_left,
    --     output          snd_sample
    -- );
    component jt12
        port (
            rst : in std_logic; -- rst should be at least 6 clk & cen cycles long
            clk : in std_logic; --  CPU clock
            cen : in std_logic; --  optional clock enable, if not needed leave as 1'b1
            din : in std_logic_vector(7 downto 0);
            addr : in std_logic_vector(1 downto 0);
            cs_n : in std_logic;
            wr_n : in std_logic;

            dout : out std_logic_vector(7 downto 0);
            irq_n : out std_logic;
            -- configuration
            en_hifi_pcm : in std_logic;
            -- combined output
            snd_right : out std_logic_vector(15 downto 0);
            snd_left : out std_logic_vector(15 downto 0);
            snd_sample : out std_logic
        );
    end component;

    type state_t is(
    IDLE,
    WR_REQ,
    WR_WAIT,
    WR_ACK,
    RD_REQ,
    RD_WAIT,
    RD_ACK
    );
    signal state : state_t;

    signal idatabuf : std_logic_vector(15 downto 0);
    signal addrbuf : std_logic_vector(7 downto 0);

    signal drq : std_logic;
    signal drq_counter : std_logic_vector(6 downto 0);

    signal datwr_req : std_logic;
    signal datwr_req_d : std_logic;
    signal datwr_ack : std_logic;
    signal datrd_req : std_logic;
    signal datrd_req_d : std_logic;
    signal datrd_ack : std_logic;
    signal datrd_ack_d : std_logic;

    type snd_state_t is(
    IDLE,
    RD_PCM,
    RD_OPN,
    RD_OTHER
    );
    signal snd_state : snd_state_t;

    signal jt12_rst : std_logic;
    signal jt12_cen : std_logic;
    signal jt12_cen_div_count : integer range 0 to 7;
    signal jt12_csn : std_logic_vector(NUM_OPNS - 1 downto 0);
    signal jt12_wrn : std_logic;
    type jt12_data_buses is array (0 to NUM_OPNS - 1) of std_logic_vector(7 downto 0);
    signal jt12_odata : jt12_data_buses;
    signal jt12_irq_n : std_logic_vector(NUM_OPNS - 1 downto 0);
    type jt12_pcms is array (0 to NUM_OPNS - 1) of pcm_type;
    signal jt12_pcmL : jt12_pcms;
    signal jt12_pcmR : jt12_pcms;
    signal jt12_snd_sample : std_logic_vector(NUM_OPNS - 1 downto 0);

    -- PCM
    signal pcm_buf : pcm_type; -- 最後に書き込んだワード
    signal pcm_bufL : pcm_type;
    signal pcm_bufR : pcm_type;
    signal pcm_LR : std_logic;
    signal pcm_clk_div_count : integer range 0 to 999; -- 32MHz → 32kHz
    signal pcm_datuse : std_logic;
    signal pcm_pcmL : pcm_type;
    signal pcm_pcmR : pcm_type;
    signal pcm_intvec : std_logic_vector(7 downto 0);

    -- 0xecc090 : pcm_mode
    -- bit0: (R/W) DMAからのEXACKをみてEXREQ(drq)をネゲートする(1)しない(0)
    -- bit1: (R/W) EXPCLを出力する(1)しない(0)
    -- bit2: (R) DMA EXREQ
    -- bit3: (R) DMA PCSの値
    -- 
    -- MercuryのPCMは単一の16ビットポートで交互にL/Rの値を書き込むことでステレオを
    -- 実現している。それだと、タイミングによってLとRが逆転してしまうため、PCSの値で
    -- 次に左右どちらの値として取り込まれるかがわかるようになっている
    -- (Lの場合PCS0、Rの場合PCS1)
    -- マーキュリーのドライバのソースを読むと、DMAの転送開始前はこのPCSをポーリングして
    -- 0→1→0になった瞬間にDMA転送を開始するようにしている
    signal pcm_mode : std_logic_vector(7 downto 0);

    -- 0xecc091 : pcm_command
    -- bit0: PCM再生(1), 停止(0) ???
    -- bit1: mono(0), stereo(1)
    -- bit2-3: mute(00), lonly(01), ronly(10), both(11)
    -- bit4-5: ?(00), 32kHz(01), 44.1kHz(10), 48kHz(11)
    signal pcm_command : std_logic_vector(7 downto 0);
begin

    -- EXPCL出力有効の時だけDRQをアクティブにする
    --drq_n <= '1' when pcm_mode(1) = '0' else not drq;
    drq_n <= not drq;
    drq <= '1' when drq_counter > 0 else '0';

    pcl_en <= pcm_mode(1);
    pcl <= pcm_LR;

    irq_n <= jt12_irq_n(0) and jt12_irq_n(1);
    GEN1 : for I in 0 to NUM_OPNS - 1 generate
        U : jt12
        port map(
            rst => jt12_rst,
            clk => snd_clk,
            cen => jt12_cen,
            din => idatabuf(7 downto 0),
            addr => addrbuf(2 downto 1),
            cs_n => jt12_csn(I),
            wr_n => jt12_wrn,

            dout => jt12_odata(I),
            irq_n => jt12_irq_n(I),
            -- configuration
            en_hifi_pcm => '1',
            -- combined output
            snd_right => jt12_pcmR(I),
            snd_left => jt12_pcmL(I),
            snd_sample => jt12_snd_sample(I)
        );
    end generate;

    -- snd_clk enable
    -- YM2610 is driven by 8MHz.
    -- So cen should be active every 4 clocks (32MHz/4 = 8MHz)
    process (snd_clk, sys_rstn)begin
        if (sys_rstn = '0') then
            jt12_cen <= '0';
            jt12_cen_div_count <= 0;
        elsif (snd_clk' event and snd_clk = '1') then
            jt12_cen <= '0';
            if (jt12_cen_div_count = 0) then
                jt12_cen <= '1';
                jt12_cen_div_count <= 3;
            else
                jt12_cen_div_count <= jt12_cen_div_count - 1;
            end if;
        end if;
    end process;

    -- sysclk synchronized inputs
    process (sys_clk, sys_rstn)
    begin
        if (sys_rstn = '0') then
            idatabuf <= (others => '0');
            addrbuf <= (others => '0');
            --
            ack <= '0';
            datwr_req <= '0';
            datrd_ack_d <= '0';
        elsif (sys_clk' event and sys_clk = '1') then
            ack <= '0';
            datrd_ack_d <= datrd_ack;
            case state is
                when IDLE =>
                    if req = '1' then
                        addrbuf <= addr;
                        if rw = '0' then
                            state <= WR_REQ;
                            idatabuf <= idata;
                            datwr_req <= not datwr_req;
                        else
                            state <= RD_REQ;
                            datrd_req <= not datrd_req;
                        end if;
                    end if;

                    -- write cycle
                when WR_REQ =>
                    state <= WR_WAIT;
                when WR_WAIT =>
                    state <= WR_ACK;
                    ack <= '1';
                when WR_ACK =>
                    if req = '1' then
                        ack <= '1';
                    else
                        ack <= '0';
                        state <= IDLE;
                    end if;

                    -- read cycle
                when RD_REQ =>
                    state <= RD_WAIT;
                when RD_WAIT =>
                    if (datrd_req = datrd_ack_d) then
                        state <= RD_ACK;
                        ack <= '1';
                    end if;
                when RD_ACK =>
                    if req = '1' then
                        ack <= '1';
                    else
                        ack <= '0';
                        state <= IDLE;
                    end if;
                when others =>
                    state <= IDLE;
            end case;
        end if;
    end process;
    --
    -- sound clock section
    --
    process (snd_clk, sys_rstn)
        variable opnsel : integer range 0 to NUM_OPNS - 1;
    begin
        if (sys_rstn = '0') then
            drq_counter <= (others => '0');
            odata <= (others => '1');
            datwr_req_d <= '0';
            datwr_ack <= '0';
            datrd_req_d <= '0';
            datrd_ack <= '0';
            snd_state <= IDLE;
            -- PCM
            pcm_buf <= (others => '0');
            pcm_bufL <= (others => '0');
            pcm_bufR <= (others => '0');

            -- OPNA(OPNB)
        elsif (snd_clk' event and snd_clk = '1') then
            datwr_req_d <= datwr_req;
            datrd_req_d <= datrd_req;

            for i in 0 to NUM_OPNS - 1 loop
                jt12_csn(i) <= '1';
            end loop;
            jt12_wrn <= '1';

            case snd_state is
                when IDLE =>
                    if (datwr_req_d /= datwr_ack) then
                        -- 書き込みサイクル
                        datwr_ack <= datwr_req_d;
                        case addrbuf is
                                -- ┗ 0xecc0a1       PCMステータスレジスタ
                            when x"80" =>
                                -- ┗ 0xecc080       PCMデータレジスタ
                                pcm_buf <= idatabuf;
                                if (pcm_command(1) = '0') then -- モノラル
                                    pcm_bufL <= idatabuf;
                                    pcm_bufR <= idatabuf;
                                else
                                    if (pcm_LR = '0') then
                                        pcm_bufL <= idatabuf;
                                    else
                                        pcm_bufR <= idatabuf;
                                    end if;
                                end if;
                            when x"90" =>
                                -- ┗ 0xecc090       PCMモードレジスタ
                                pcm_mode <= idatabuf(15 downto 8);
                                pcm_command <= idatabuf(7 downto 0); -- ワードアクセス時
                            when x"91" =>
                                -- ┗ 0xecc091       PCMコマンドレジスタ
                                pcm_command <= idatabuf(7 downto 0); -- バイトアクセス時
                            when x"a1" =>
                                -- ┗ 0xecc0a1       PCMステータスレジスタ
                            when x"b1" =>
                                -- ┗ 0xecc0b1       割り込みベクタ設定レジスタ
                                pcm_intvec <= idatabuf(7 downto 0);
                            when x"c1" | x"c3" | x"c5" | x"c7" | x"c9" | x"cb" | x"cd" | x"cf" =>
                                -- OPNA(OPNB)
                                if (addrbuf(3) = '0') then
                                    opnsel := 0;
                                else
                                    opnsel := 1;
                                end if;
                                jt12_csn(opnsel) <= '0';
                                jt12_wrn <= '0';
                            when others =>
                                null;
                        end case;
                    elsif (datrd_req_d /= datrd_ack) then
                        -- 読み込みサイクル
                        case addrbuf(7 downto 0) is
                            when x"80" | x"81" =>
                                -- ┗ 0xecc080       PCMデータレジスタ
                                odata <= pcm_buf;
                                snd_state <= RD_PCM;
                            when x"90" | x"91" =>
                                -- ┗ 0xecc090       PCMモードレジスタ
                                -- ┗ 0xecc091       PCMコマンドレジスタ
                                odata <= "0000" & pcm_LR & drq & pcm_mode(1 downto 0) & pcm_command;
                                snd_state <= RD_PCM;
                            when x"a0" | x"a1" =>
                                -- ┗ 0xecc0a1       PCMステータスレジスタ
                                odata <= x"ff" & pcm_command; -- TODO
                                snd_state <= RD_PCM;
                            when x"b0" | x"b1" =>
                                -- ┗ 0xecc0b1       割り込みベクタ設定レジスタ
                                odata <= x"00" & pcm_intvec;
                                snd_state <= RD_PCM;
                            when x"c0" | x"c2" | x"c4" | x"c6" | x"c8" | x"ca" | x"cc" | x"ce" |
                                x"c1" | x"c3" | x"c5" | x"c7" | x"c9" | x"cb" | x"cd" | x"cf" =>
                                -- OPNA(OPNB)
                                if (addrbuf(3) = '0') then
                                    opnsel := 0;
                                else
                                    opnsel := 1;
                                end if;
                                jt12_csn(opnsel) <= '0';
                                snd_state <= RD_OPN;
                            when others =>
                                odata <= (others => '1');
                                snd_state <= RD_OTHER;
                        end case;
                    end if;
                when RD_PCM =>
                    datrd_ack <= datrd_req_d;
                    snd_state <= IDLE;
                when RD_OPN =>
                    datrd_ack <= datrd_req_d;
                    if (addrbuf(3) = '0') then
                        opnsel := 0;
                    else
                        opnsel := 1;
                    end if;
                    odata <= x"00" & jt12_odata(opnsel);
                    snd_state <= IDLE;
                when RD_OTHER =>
                    datrd_ack <= datrd_req_d;
                    snd_state <= IDLE;
                when others =>
                    snd_state <= IDLE;
            end case;

            if (pcm_datuse = '1') then
                drq_counter <= (others => '1');
            elsif (pcm_mode(0) = '1') then
                if (dack_n = '0') then
                    drq_counter <= (others => '0');
                else
                    if (drq_counter > 0) then
                        drq_counter <= drq_counter - 1;
                    end if;
                end if;
            else
                if (drq_counter > 0) then
                    drq_counter <= drq_counter - 1;
                end if;
            end if;
        end if;
    end process;

    process (snd_clk, sys_rstn)begin
        if (sys_rstn = '0') then
            pcm_datuse <= '0';
            pcm_clk_div_count <= 0;
        elsif (snd_clk' event and snd_clk = '1') then
            pcm_datuse <= '0';
            if (pcm_clk_div_count = 0) then
                case pcm_command(5 downto 4) & pcm_command(1) is
                    when "010" => -- 32kHz mono
                        pcm_clk_div_count <= 999; -- 32000 / 32 = 1000
                    when "100" => -- 44.1kHz mono
                        pcm_clk_div_count <= 725; -- 32000 / 44.1 = 725.623
                    when "110" => -- 48kHz mono
                        pcm_clk_div_count <= 666; -- 32000 / 48 /2 = 666.666
                    when "011" => -- 32kHz stereo
                        pcm_clk_div_count <= 499; -- 32000 / 32 /2 = 500
                    when "101" => -- 44.1kHz stereo
                        pcm_clk_div_count <= 362; -- 32000 / 44.1 /2 = 362.811
                    when "111" => -- 48kHz stereo
                        pcm_clk_div_count <= 332; -- 32000 / 48 /2 = 333.333
                    when others =>
                        pcm_clk_div_count <= 499; -- 32000 / 32 /2 = 500
                end case;
                pcm_datuse <= '1';
                pcm_LR <= not pcm_LR; -- モノラルでもpcm_LRは交互に反転させる
            else
                pcm_clk_div_count <= pcm_clk_div_count - 1;
            end if;
        end if;
    end process;

    pcmL <= pcm_bufL + jt12_pcmL(0) + jt12_pcmL(1);
    pcmR <= pcm_bufR + jt12_pcmR(0) + jt12_pcmR(1);
end rtl;