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
-- MF-MU1に実装されていたのは YMF288のようですが、KeplerXでは jt10という
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
        int_vec : out std_logic_vector(7 downto 0);

        drq_n : out std_logic;
        dack_n : in std_logic;

        pcl_en : out std_logic;
        pcl : out std_logic;

        -- specific i/o
        snd_clk : in std_logic;
        pcm_clk_12M288 : in std_logic; -- 48kHz * 2 * 127
        pcm_clk_11M2896 : in std_logic; -- 44.1kHz * 2 * 127
        pcm_clk_8M : in std_logic; -- 32kHz * 2 * 125
        pcm_pcmL : out pcm_type;
        pcm_pcmR : out pcm_type;
        pcm_fm0 : out pcm_type;
        pcm_ssg0 : out pcm_type;
        pcm_fm1 : out pcm_type;
        pcm_ssg1 : out pcm_type
    );
end eMercury;

architecture rtl of eMercury is

    -- module jt10(
    --     input           rst,        // rst should be at least 6 clk&cen cycles long
    --     input           clk,        // CPU clock
    --     input           cen,        // optional clock enable, if not needed leave as 1'b1
    --     input   [7:0]   din,
    --     input   [1:0]   addr,
    --     input           cs_n,
    --     input           wr_n,

    --     output  [7:0]   dout,
    --     output          irq_n,
    --     // ADPCM pins
    --     output  [19:0]  adpcma_addr,  // real hardware has 10 pins multiplexed through RMPX pin
    --     output  [3:0]   adpcma_bank,
    --     output          adpcma_roe_n, // ADPCM-A ROM output enable
    --     input   [7:0]   adpcma_data,  // Data from RAM
    --     output  [23:0]  adpcmb_addr,  // real hardware has 12 pins multiplexed through PMPX pin
    --     output          adpcmb_roe_n, // ADPCM-B ROM output enable
    --     input   [7:0]   adpcmb_data,
    --     // Separated output
    --     output          [ 7:0] psg_A,
    --     output          [ 7:0] psg_B,
    --     output          [ 7:0] psg_C,
    --     output  signed  [15:0] fm_snd,
    --     // combined output
    --     output          [ 9:0] psg_snd,
    --     output  signed  [15:0] snd_right,
    --     output  signed  [15:0] snd_left,
    --     output          snd_sample
    -- );
    component jt10
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
            --     // ADPCM pins
            adpcma_addr : out std_logic_vector(19 downto 0); -- real hardware has 10 pins multiplexed through RMPX pin
            adpcma_bank : out std_logic_vector(3 downto 0);
            adpcma_roe_n : out std_logic; -- ADPCM-A ROM output enable
            adpcma_data : in std_logic_vector(7 downto 0); -- Data from RAM
            adpcmb_addr : out std_logic_vector(23 downto 0); -- real hardware has 12 pins multiplexed through PMPX pin
            adpcmb_roe_n : out std_logic; -- ADPCM-B ROM output enable
            adpcmb_data : in std_logic_vector(7 downto 0);
            -- Separated output
            psg_A : out std_logic_vector(7 downto 0);
            psg_B : out std_logic_vector(7 downto 0);
            psg_C : out std_logic_vector(7 downto 0);
            fm_snd : out std_logic_vector(15 downto 0);

            -- combined output
            psg_snd : out std_logic_vector(9 downto 0);
            snd_right : out std_logic_vector(15 downto 0);
            snd_left : out std_logic_vector(15 downto 0);
            snd_sample : out std_logic
        );
    end component;
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
    RD_OPN,
    RD_FIN
    );
    signal snd_state : snd_state_t;

    -- FM
    signal opn_rst : std_logic;
    signal opn_cen : std_logic;
    signal opn_csn : std_logic_vector(NUM_OPNS - 1 downto 0);
    signal opn_wrn : std_logic;
    type opn_data_buses is array (0 to NUM_OPNS - 1) of std_logic_vector(7 downto 0);
    signal opn_odata : opn_data_buses;
    signal opn_irq_n : std_logic_vector(NUM_OPNS - 1 downto 0);
    type opn_ssgs is array (0 to NUM_OPNS - 1) of std_logic_vector(9 downto 0);
    type opn_pcms is array (0 to NUM_OPNS - 1) of pcm_type;
    signal opn_ssg : opn_ssgs;
    signal opn_fm : opn_pcms;
    signal opn_pcmL : opn_pcms;
    signal opn_pcmR : opn_pcms;
    signal opn_snd_sample : std_logic_vector(NUM_OPNS - 1 downto 0);

    signal opn_reg_addrA : opn_data_buses;

    -- PCM
    signal pcm_buf : pcm_type; -- 最後に書き込んだワード
    signal pcm_bufL : pcm_type;
    signal pcm_bufR : pcm_type;
    signal pcm_LR : std_logic;
    signal pcm_clk_div_count : integer range 0 to 3; -- /2 (mono or stereo), /2 (halfrate or fullrate)

    -- 12.288MHz → /4 /32 → 48kHz *2
    signal pcm_clk_div_shift_S48k : std_logic_vector(3 downto 0);
    signal pcm_clk_div_count_S48k : integer range 0 to 31;
    -- 11.2896MHz → /4 /32 → 44.1kHz *2
    signal pcm_clk_div_shift_S44k : std_logic_vector(3 downto 0);
    --signal pcm_clk_div_count_S44k : integer range 0 to 31;
    signal pcm_clk_div_count_S44k : integer range 0 to 127;
    -- 8MHz → /5 /25 → 32kHz *2
    signal pcm_clk_div_shift_S32k : std_logic_vector(4 downto 0);
    signal pcm_clk_div_count_S32k : integer range 0 to 24;

    signal pcm_clk_req_S48k : std_logic;
    signal pcm_clk_req_S44k : std_logic;
    signal pcm_clk_req_S32k : std_logic;
    signal pcm_clk_req : std_logic;
    signal pcm_clk_req_d : std_logic;
    signal pcm_clk_ack : std_logic;
    signal pcm_datuse : std_logic;
    signal mercury_int_vec : std_logic_vector(7 downto 0);

    -- 0xecc090 : pcm_mode
    -- bit0: (R/W) DMAからのEXACKをみてEXREQ(drq)をネゲートする(1)しない(0)
    -- bit1: (R/W) EXPCLを出力する(1)しない(0)
    -- bit2: (R) DMA EXREQ
    -- bit3: (R) DMA PCSの値
    -- 
    -- MercuryのPCMは単一の16ビットポートで交互にL/Rの値を書き込むことでステレオを
    -- 実現している。それだと、タイミングによってLとRが逆転してしまうため、PCSの値で
    -- 次に左右どちらの値として取り込まれるかがわかるようになっているようだ
    -- (Lの場合PCSが0、Rの場合PCSが1)
    -- マーキュリーのドライバのソースを読むと、DMAの転送開始前はこのPCSをポーリングして
    -- 0→1→0になった瞬間にDMA転送を開始するようにしてタイミングを合わせている
    signal pcm_mode : std_logic_vector(7 downto 0);

    -- 0xecc091 : pcm_command
    -- bit0: PCM再生(1), 停止/PCMスルー(0) ???
    -- bit1: mono(0), stereo(1)
    -- bit2-3: mute(00), lonly(01), ronly(10), both(11)
    -- bit4-5: ?(00), 32kHz(01), 44.1kHz(10), 48kHz(11)
    -- bit6: input source select: optial(0), coaxial(1)
    -- bit7: Half rate(0), Full rate(1)
    signal pcm_command : std_logic_vector(7 downto 0);

    -- 0xecc0a1 : pcm_status
    -- bit0: input sync: ok(0), ng(1) ??? PCMスルー中のステータス
    -- bit1: mono(0), stereo(1) ???
    -- bit2-3: mute(00), lonly(01), ronly(10), both(11) ???
    -- bit4-5: ?(00), 32kHz(01), 44.1kHz(10), 48kHz(11) ???
    -- bit6: input source is optial(0), coaxial(1) ???
    -- bit7: Half rate(0), Full rate(1) ???

begin

    -- EXPCL出力有効の時だけDRQをアクティブにする
    --drq_n <= '1' when pcm_mode(1) = '0' else not drq;
    drq_n <= not drq;
    drq <= '0' when drq_counter = 0 else '1';

    pcl_en <= pcm_mode(1);
    pcl <= pcm_LR;

    irq_n <= opn_irq_n(0) and opn_irq_n(1);
    int_vec <= mercury_int_vec;

    GEN1 : for I in 0 to NUM_OPNS - 1 generate
        U : jt10
        port map(
            rst => opn_rst,
            clk => snd_clk,
            cen => opn_cen,
            din => idatabuf(7 downto 0),
            addr => addrbuf(2 downto 1),
            cs_n => opn_csn(I),
            wr_n => opn_wrn,

            dout => opn_odata(I),
            irq_n => opn_irq_n(I),

            adpcma_addr => open,
            adpcma_bank => open,
            adpcma_roe_n => open,
            adpcma_data => (others => '0'),
            adpcmb_addr => open,
            adpcmb_roe_n => open,
            adpcmb_data => (others => '0'),
            -- Separated output
            psg_A => open,
            psg_B => open,
            psg_C => open,
            fm_snd => opn_fm(I),
            -- combined output
            psg_snd => opn_ssg(I),
            snd_right => opn_pcmR(I),
            snd_left => opn_pcmL(I),
            snd_sample => opn_snd_sample(I)
        );
    end generate;

    opn_rst <= not sys_rstn;

    -- snd_clk enable
    -- YM2610 is driven by 8MHz.
    -- So cen should be active every 2 clocks (16MHz/2 = 8MHz)
    process (snd_clk, sys_rstn)begin
        if (sys_rstn = '0') then
            opn_cen <= '0';
        elsif (snd_clk' event and snd_clk = '1') then
            opn_cen <= not opn_cen;
        end if;
    end process;

    -- sysclk synchronized inputs
    process (sys_clk, sys_rstn)
    begin
        if (sys_rstn = '0') then
            state <= IDLE;
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
            opn_wrn <= '1';

            -- registers
            pcm_mode <= x"03";
            pcm_command <= (others => '0');
            mercury_int_vec <= x"ff";
            for i in 0 to NUM_OPNS - 1 loop
                opn_reg_addrA(i) <= (others => '0');
            end loop;

            -- PCM
            pcm_buf <= (others => '0');
            pcm_bufL <= (others => '0');
            pcm_bufR <= (others => '0');

            -- OPNA(OPNB)
        elsif (snd_clk' event and snd_clk = '1') then
            datwr_req_d <= datwr_req;
            datrd_req_d <= datrd_req;

            for i in 0 to NUM_OPNS - 1 loop
                opn_csn(i) <= '1';
            end loop;
            opn_wrn <= '1';

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
                                mercury_int_vec <= idatabuf(7 downto 0);
                            when others =>
                                if (addrbuf >= x"c0") then
                                    -- OPNA(OPNB)
                                    if (addrbuf(3) = '0') then
                                        opnsel := 0;
                                    else
                                        opnsel := 1;
                                    end if;
                                    if (addrbuf(2 downto 0) = "001") then
                                        -- ffレジスタの読み出しを検出するためにアドレスを覚えておく
                                        opn_reg_addrA(opnsel) <= idatabuf(7 downto 0);
                                    end if;
                                    opn_csn(opnsel) <= '0';
                                    opn_wrn <= '0';
                                end if;
                        end case;
                    elsif (datrd_req_d /= datrd_ack) then
                        -- 読み込みサイクル
                        case addrbuf(7 downto 0) is
                            when x"80" | x"81" =>
                                -- ┗ 0xecc080       PCMデータレジスタ
                                odata <= pcm_buf;
                                snd_state <= RD_FIN;
                            when x"90" | x"91" =>
                                -- ┗ 0xecc090       PCMモードレジスタ
                                -- ┗ 0xecc091       PCMコマンドレジスタ
                                odata <= "0000" & pcm_LR & drq & pcm_mode(1 downto 0) & pcm_command;
                                snd_state <= RD_FIN;
                            when x"a0" | x"a1" =>
                                -- ┗ 0xecc0a1       PCMステータスレジスタ
                                odata <= x"ff" &
                                    pcm_command(7) & -- Hal rate(0) / Fullrate(1)
                                    pcm_command(6) & -- Input source: optical(0) / coaxial(1)
                                    pcm_command(5 downto 4) & -- ?(00), 32kHz(01), 44.1kHz(10), 48kHz(11)
                                    pcm_command(3 downto 2) & -- mute(00), L only(01), R only(10), both(11)
                                    pcm_command(1) & -- mono(0) / stereo(1)
                                    '1'; -- input sync: ok(0) / ng(1) 入力サポートするまではNG
                                snd_state <= RD_FIN;
                            when x"b0" | x"b1" =>
                                -- ┗ 0xecc0b1       割り込みベクタ設定レジスタ
                                odata <= x"00" & mercury_int_vec;
                                snd_state <= RD_FIN;
                            when others =>
                                if (addrbuf >= x"c0") then
                                    if (addrbuf(3) = '0') then
                                        opnsel := 0;
                                    else
                                        opnsel := 1;
                                    end if;
                                    if ((addrbuf(2 downto 0) = "011") and opn_reg_addrA(opnsel) = x"ff") then
                                        opn_reg_addrA(opnsel) <= idatabuf(7 downto 0);
                                        odata <= x"0001"; -- 1 is YM2608B
                                        snd_state <= RD_FIN;
                                    else
                                        opn_csn(opnsel) <= '0';
                                        snd_state <= RD_OPN;
                                    end if;

                                else odata <= (others => '1');
                                    snd_state <= RD_FIN;
                                end if;
                        end case;
                    end if;
                when RD_OPN =>
                    if (addrbuf(3) = '0') then
                        opnsel := 0;
                    else
                        opnsel := 1;
                    end if;
                    odata <= x"ff" & opn_odata(opnsel);
                    snd_state <= RD_FIN;
                when RD_FIN =>
                    datrd_ack <= datrd_req_d;
                    snd_state <= IDLE;
                when others =>
                    snd_state <= IDLE;
            end case;

            if (pcm_datuse = '1') then
                -- PCM側がデータを消費したらDMAリクエストを投げる
                -- EXREQはエッジトリガなので、カウンタを回して適当なタイミングでネゲートするようにしている
                -- カウンタの長さは適当です。X68000のDMACがエッジを拾ってくれさえすれば良さそうなので
                -- もっと短くてもいいのかもしれない。
                drq_counter <= "0111111";
            else
            if (pcm_mode(0) = '1') then
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
        end if;
    end process;

    -- 12.288MHzを128分周して 96kHz (48kHzのステレオ) 周期のリクエストを作る回路
    process (pcm_clk_12M288, sys_rstn)
    begin
        if (sys_rstn = '0') then
            pcm_clk_div_shift_S48k <= "1010";
            pcm_clk_div_count_S48k <= 0;
            pcm_clk_req_S48k <= '0';
        elsif (pcm_clk_12M288' event and pcm_clk_12M288 = '1') then
            pcm_clk_div_shift_S48k <= pcm_clk_div_shift_S48k(0) & pcm_clk_div_shift_S48k(3 downto 1);
            if (pcm_clk_div_shift_S48k(3) = '1') then
                if (pcm_clk_div_count_S48k = 0) then
                    pcm_clk_div_count_S48k <= 31;
                    pcm_clk_req_S48k <= not pcm_clk_req_S48k;
                else
                    pcm_clk_div_count_S48k <= pcm_clk_div_count_S48k - 1;
                end if;
            end if;
        end if;
    end process;

    -- 11.2896MHzを256分周して 88.2kHz (44.1kHzのステレオ) 周期のリクエストを作る回路
    process (pcm_clk_11M2896, sys_rstn)
    begin
        if (sys_rstn = '0') then
            pcm_clk_div_shift_S44k <= "1000";
            pcm_clk_div_count_S44k <= 0;
            pcm_clk_req_S44k <= '0';
        elsif (pcm_clk_11M2896' event and pcm_clk_11M2896 = '1') then
--            pcm_clk_div_shift_S44k <= pcm_clk_div_shift_S44k(0) & pcm_clk_div_shift_S44k(3 downto 1);
--            if (pcm_clk_div_shift_S44k(3) = '1') then
                if (pcm_clk_div_count_S44k = 0) then
                    pcm_clk_div_count_S44k <= 63;
                    pcm_clk_req_S44k <= not pcm_clk_req_S44k;
                else
                    pcm_clk_div_count_S44k <= pcm_clk_div_count_S44k - 1;
                end if;
--            end if;
        end if;
    end process;

    -- 8MHzを125分周して 64kHz (32kHzのステレオ) 周期のリクエストを作る回路
    process (pcm_clk_8M, sys_rstn)
    begin
        if (sys_rstn = '0') then
            pcm_clk_div_shift_S32k <= "10000";
            pcm_clk_div_count_S32k <= 0;
            pcm_clk_req_S32k <= '0';
        elsif (pcm_clk_8M' event and pcm_clk_8M = '1') then
            pcm_clk_div_shift_S32k <= pcm_clk_div_shift_S32k(0) & pcm_clk_div_shift_S32k(4 downto 1);
            if (pcm_clk_div_shift_S32k(3) = '1') then
                if (pcm_clk_div_count_S32k = 0) then
                    pcm_clk_div_count_S32k <= 24;
                    pcm_clk_req_S32k <= not pcm_clk_req_S32k;
                else
                    pcm_clk_div_count_S32k <= pcm_clk_div_count_S32k - 1;
                end if;
            end if;
        end if;
    end process;

    process (snd_clk, sys_rstn)
        variable condition : std_logic_vector(3 downto 0);
        variable div : integer range 0 to 3;
    begin
        if (sys_rstn = '0') then
            pcm_datuse <= '0';
            pcm_clk_div_count <= 0;
            pcm_clk_req <= '0';
            pcm_clk_req_d <= '0';
            pcm_clk_ack <= '0';
        elsif (snd_clk' event and snd_clk = '1') then
            pcm_datuse <= '0';
            pcm_clk_req_d <= pcm_clk_req;

            condition := pcm_command(7) & pcm_command(1) & pcm_command(5 downto 4);
            case condition is
                    -- half rate
                when "0000" => -- 22.05kHz mono (Stereo 44.1kHz /2 /2)
                    pcm_clk_req <= pcm_clk_req_S44k;
                    div := 3;
                when "0001" => -- 16kHz mono (Stereo 32kHz /2 /2)
                    pcm_clk_req <= pcm_clk_req_S32k;
                    div := 3;
                when "0010" => -- 22.05kHz mono (Stereo 44.1kHz /2 /2)
                    pcm_clk_req <= pcm_clk_req_S44k;
                    div := 3;
                when "0011" => -- 24kHz mono (Stereo 48kHz /2 /2)
                    pcm_clk_req <= pcm_clk_req_S48k;
                    div := 3;
                when "0100" => -- 22.05kHz stereo (Stereo 44.1kHz /2)
                    pcm_clk_req <= pcm_clk_req_S44k;
                    div := 1;
                when "0101" => -- 16kHz stereo (Stereo 32kHz /2)
                    pcm_clk_req <= pcm_clk_req_S32k;
                    div := 1;
                when "0110" => -- 22.05kHz stereo (Stereo 44.1kHz /2)
                    pcm_clk_req <= pcm_clk_req_S44k;
                    div := 1;
                when "0111" => -- 24kHz stereo (Stereo 48kHz /2 /2)
                    pcm_clk_req <= pcm_clk_req_S48k;
                    div := 1;

                    -- full rate
                when "1000" => -- 44.1kHz mono (Stereo 44.1kHz /2)
                    pcm_clk_req <= pcm_clk_req_S44k;
                    div := 1;
                when "1001" => -- 32kHz mono (Stereo 32kHz /2)
                    pcm_clk_req <= pcm_clk_req_S32k;
                    div := 1;
                when "1010" => -- 44.1kHz mono (Stereo 44.1kHz /2)
                    pcm_clk_req <= pcm_clk_req_S44k;
                    div := 1;
                when "1011" => -- 48kHz mono (Stereo 48kHz /2)
                    pcm_clk_req <= pcm_clk_req_S48k;
                    div := 1;
                when "1100" => -- 44.1kHz stereo
                    pcm_clk_req <= pcm_clk_req_S44k;
                    div := 0;
                when "1101" => -- 32kHz stereo
                    pcm_clk_req <= pcm_clk_req_S32k;
                    div := 0;
                when "1110" => -- 44.1kHz stereo
                    pcm_clk_req <= pcm_clk_req_S44k;
                    div := 0;
                when "1111" => -- 48kHz stereo
                    pcm_clk_req <= pcm_clk_req_S48k;
                    div := 0;
                when others =>
                    pcm_clk_req <= pcm_clk_req_S48k;
                    div := 0;
            end case;

            if (pcm_clk_req_d /= pcm_clk_ack) then
                pcm_clk_ack <= not pcm_clk_ack;
                if (pcm_clk_div_count = 0) then
                    pcm_clk_div_count <= div;
                    pcm_datuse <= '1';
                    pcm_LR <= not pcm_LR; -- モノラルでもpcm_LRは交互に反転させる
                else
                    pcm_clk_div_count <= pcm_clk_div_count - 1;
                end if;
            end if;
        end if;
    end process;

    pcm_pcmL <= pcm_bufL;
    pcm_pcmR <= pcm_bufR;
    pcm_fm0 <= opn_fm(0);
    pcm_ssg0 <= "0000" & opn_ssg(0) & "00";
    pcm_fm1 <= opn_fm(1);
    pcm_ssg1 <= "0000" & opn_ssg(1) & "00";

end rtl;