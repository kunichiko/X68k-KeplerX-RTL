library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.std_logic_arith.all;
use IEEE.STD_LOGIC_UNSIGNED.all;

-- VGA互換のテキスト画面を表示するためのモジュールです。
-- 表示デバイスは hdmi-util で作成した HDMI デバイスの画面モード2(720x480)を使用します。
-- 8x16ドットのフォントを使用すると、90x30文字のテキスト領域が確保できる計算ですが、
-- Kepler Xでは画面上部 8行しか使用しないため、本モジュールは90x8文字のテキスト画面のみを
-- サポートします。
--
-- ●描画アルゴリズム
-- HDMIのcx,cyに合わせて文字を描画するためには、
-- * cx - 3: VRAMのアドレスに次の描画位置のアドレスをセットする
-- * cx - 2: VRAMから読み出された文字コードをフォントROMのアドレスにセットする
-- * cx - 1: フォントROMから読み出されたフォントデータをシフトレジスタ偽とする
-- * cx - 0: シフトレジスタからRGB値を決定する
-- という処理を行う必要があります。描画には cxの次のクロックエッジでそのcxの位置のRGB値を出力する必要があるため、
-- 上記の通りcxの3クロック前から処理を開始する必要があります。
-- 720x480の画面モードにはバックポーチがあるため、実際の(cx,cy)の最大値は (857,524) になります。
-- これを考慮し、cx, cyの値を先読みして、3クロック手前で読み出し処理を開始するようにします。
entity textconsole is
    port (
        -- Host interface for VRAM update
        sys_clk : in std_logic;
        sys_rstn : in std_logic;

        req : in std_logic;
        ack : out std_logic;
        rw : in std_logic;
        addr : in std_logic_vector(6 downto 0);
        idata : in std_logic_vector(7 downto 0);
        odata : out std_logic_vector(7 downto 0);

        -- color setting
        fgrgb : in std_logic_vector(23 downto 0);
        bgrgb : in std_logic_vector(23 downto 0);

        -- HDMI interface
        hdmi_clk : in std_logic;
        cx : in std_logic_vector(9 downto 0);
        cy : in std_logic_vector(9 downto 0);
        rgb : out std_logic_vector(23 downto 0)
    );
end textconsole;

architecture rtl of textconsole is

    component console_textram is
        port (
            clk : in std_logic;
            address : in std_logic_vector(3 + 7 - 1 downto 0);
            din : in std_logic_vector(7 downto 0);
            dout : out std_logic_vector(7 downto 0);
            we : in std_logic
        );
    end component;

	signal console_ram_addr : std_logic_vector(3 + 7 - 1 downto 0);
	signal console_ram_din : std_logic_vector(7 downto 0);
	signal console_ram_dout : std_logic_vector(7 downto 0);
	signal console_ram_we : std_logic;

    component console_glyphrom is
        port (
            clk : in std_logic;
            address : in std_logic_vector(7 downto 0);
            din : in std_logic_vector(7 downto 0);
            dout : out std_logic_vector(7 downto 0);
            we : in std_logic
        );
    end component;

    signal console_glyph_addr : std_logic_vector(7 downto 0);
	signal console_glyph_din : std_logic_vector(7 downto 0);
	signal console_glyph_dout : std_logic_vector(7 downto 0);
	signal console_glyph_we : std_logic;

    signal glyph_sft : std_logic_vector(7 downto 0);
    signal glyph_d : std_logic;
begin
    console_textram0 : console_textram
    port map(
        clk => hdmi_clk,
        address => console_ram_addr,
        din => console_ram_din,
        dout => console_ram_dout,
        we => console_ram_we
    );

    console_glyphrom0 : console_glyphrom
    port map(
        clk => hdmi_clk,
        address => console_glyph_addr,
        din => console_glyph_din,
        dout => console_glyph_dout,
        we => console_glyph_we
    );

    process (sys_clk, sys_rstn)
    begin
        if (sys_rstn = '0') then
        elsif (sys_clk' event and sys_clk = '1') then
        end if;
    end process;

    process (hdmi_clk, sys_rstn)
        variable next_lx : std_logic_vector(6 downto 0); -- 0-89
        variable next_ly : std_logic_vector(2 downto 0); -- 0-7
    begin
        if (sys_rstn = '0') then
            console_ram_addr <= (others => '0');
            console_ram_din <= (others => '0');
            console_ram_we <= '0';
            console_glyph_din <= (others => '0');
            console_glyph_we <= '0';
            glyph_sft <= (others => '0');
            glyph_d <= '0';
        elsif (hdmi_clk' event and hdmi_clk = '1') then
            if (cx = 857 - 2) then -- あと3クロックでcx = 0になるタイミング
                next_lx := "0000000";
                if (cy = 524) then -- 最終ラインの場合、次のcx = 0 で　cy = 0 になる
                    next_ly := "000";
                elsif (cy(3 downto 0) = "1111") then -- 各行の最終ラインの場合、次のcx = 0 で　cy = cy + 1 になる
                    next_ly := cy(6 downto 4) + 1;
                else
                    next_ly := cy(6 downto 4); -- 各行の途中
                end if;
                console_ram_addr <= next_ly & next_lx;
            elsif (cx(2 downto 0) = "101") then -- 各文字の最終ピクセル-2のタイミング(あと3クロックでcx = cx + 1になる)
                next_lx := cx(9 downto 3) + 1;
                next_ly := cy(6 downto 4);
                console_ram_addr <= next_ly & next_lx;
            end if;

            -- glyph rendering
            if (cx(2 downto 0) = "111") then -- 
                glyph_sft <= console_glyph_dout;
                glyph_d <= '0';
            else
                glyph_sft <= glyph_sft(6 downto 0) & "0";
                glyph_d <= glyph_sft(7);
            end if;

            if (glyph_sft(7) = '1' or glyph_d = '1') then -- bold
                rgb <= fgrgb;
            else
                rgb <= bgrgb;
            end if;
            
        end if;
    end process;

    console_glyph_addr <= console_ram_dout;

end;