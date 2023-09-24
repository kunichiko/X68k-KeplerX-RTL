library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.std_logic_arith.all;
use IEEE.STD_LOGIC_UNSIGNED.all;

--
-- I2Cバスの読み書きを汎用的に行うためのペリフェラルモジュールです。
-- Kepler Xのレジスタ経由など、CPUから I2Cバスを操作することを想定しています。
--
-- ● できること
-- linuxの i2cget, i2cset 相当のことが可能ですが、簡略化のため、データアドレス指定(レジスタ番号指定)
-- 付きの書き込み、読み出しのみをサポートしています。
-- 
-- - i2cget -y 0 0xAA 0xdd b
--    アドレス0xAAのペリフェラルの 0xddレジスタを 1バイト読み出します。
-- - i2cget -y 0 0xAA 0xdd w
--    アドレス0xAAのペリフェラルの 0xddレジスタを 2バイト読み出します。
--    ビッグエンディアンで読み出しますので、最初に送られたバイトが上位(D15-D8)、次に送られたバイトが下位(D7-D0)になります。
-- - i2cset -y 0 0xAA 0xdd 0x11 b
--    アドレス0xAAのペリフェラルの 0xddレジスタに 0x11を書き込みます。
-- - i2cset -y 0 0xAA 0xdd 0x1122 w
--    アドレス0xAAのペリフェラルの 0xddレジスタに 0x1122を書き込みます。
--    ビッグエンディアンで書き込みますので、上位バイト(0x11)が最初に送られ、次に下位バイト(0x22)が送られます。
--
-- ● I/F
-- ホスト側とのインターフェースは、req/ack信号、rw信号、size信号、addr信号、regnum信号、idata信号、odata信号、
-- busy信号、err信号で行います。
-- - req信号がアサートされたときに、command信号に書き込み/読み出しの指示を行います。
-- - rw信号が0のときは書き込み、1のときは読み出しです。
-- - size信号が0のときは1バイト、1のときは2バイトです。
-- - regnum信号には、書き込み/読み出しを行うレジスタ番号を指定します。
-- - idata信号には、書き込みの場合は書き込むデータを、読み出しの場合はダミーデータを指定します。
-- - odata信号には、読み出しの場合に読み出したデータを返します。
-- - busy信号は、ペリフェラルが処理中のときにアサートされます。
-- - err信号は、ペリフェラルがエラーを検出したときにアサートされます。req信号がアサートされるとリセットされます。
-- 
-- idataおよびodataは、size信号が0の時(1バイトの時)は下位バイトのみが有効です。
-- 
entity I2C_driver is
    port (
        -- Host interface
        req : in std_logic;
        ack : out std_logic;
        rw : in std_logic;
        size : in std_logic;
        addr : in std_logic_vector(6 downto 0);
        regnum : in std_logic_vector(7 downto 0);
        idata : in std_logic_vector(15 downto 0);
        odata : out std_logic_vector(15 downto 0);
        busy : out std_logic;
        err : out std_logic;

        -- I2C interface
        TXOUT : out std_logic_vector(7 downto 0); --tx data
        RXIN : in std_logic_vector(7 downto 0); --rx data
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
end I2C_driver;

architecture rtl of I2C_driver is

    type state_t is(
    IS_IDLE,
    IS_READ_SET_ADDR,
    IS_READ_SET_REGNUM,
    IS_READ_START,
    IS_READ_DATA_U,
    IS_READ_DATA_L,
    IS_WRITE_SET_ADDR,
    IS_WRITE_SET_REGNUM,
    IS_WRITE_DATA_U,
    IS_WRITE_DATA_L,
    IS_FINISH
    );
    signal state : state_t;

    signal timeout_counter : std_logic_vector(15 downto 0); -- タイムアウトカウンタ(655 usec @100MHz)

begin

    process (clk, rstn)
    begin
        if (rstn = '0') then
            state <= IS_IDLE;
            timeout_counter <= (others => '0');
            ack <= '0';
            NX_READ <= '0';
            RESTART <= '0';
            START <= '0';
            FINISH <= '0';
            F_FINISH <= '0';
            INIT <= '0';
        elsif (clk' event and clk = '1') then
            F_FINISH <= '0';
            INIT <= '0';

            --
            if (state /= IS_IDLE) then
                busy <= '1';
            else
                busy <= '0';
            end if;
            --
            if (timeout_counter /= 0) then
                timeout_counter <= timeout_counter - 1;
            end if;
            if (timeout_counter = 0 and state /= IS_IDLE) then
                err <= '1';
                busy <= '0';
                INIT <= '1'; -- I2Cを初期化する
                state <= IS_IDLE;
            else
                case state is
                    when IS_IDLE =>
                        if (req = '1') then
                            ack <= '1';
                            timeout_counter <= (others => '1');
                            busy <= '1';
                            err <= '0';
                            if (rw = '1') then
                                state <= IS_READ_SET_ADDR;
                            else
                                state <= IS_WRITE_SET_ADDR;
                            end if;
                        end if;

                    when IS_READ_SET_ADDR =>
                        if (TXEMP = '1') then
                            NX_READ <= '0';
                            RESTART <= '0';
                            START <= '1';
                            FINISH <= '0';
                            TXOUT <= addr & '0'; -- Device Address
                            WRn <= '0';
                            state <= IS_READ_SET_REGNUM;
                        end if;
                    when IS_READ_SET_REGNUM =>
                        if (TXEMP = '1') then
                            NX_READ <= '0';
                            RESTART <= '0';
                            START <= '0';
                            FINISH <= '0';
                            TXOUT <= regnum; -- Register Number
                            WRn <= '0';
                            state <= IS_READ_START;
                        end if;
                    when IS_READ_START =>
                        if (TXEMP = '1') then
                            NX_READ <= '1';
                            RESTART <= '1';
                            START <= '0';
                            FINISH <= '0';
                            TXOUT <= addr & '1'; -- Device Address
                            WRn <= '0';
                            if (size = '0') then
                                state <= IS_READ_DATA_L;
                            else
                                state <= IS_READ_DATA_U;
                            end if;
                        end if;
                    when IS_READ_DATA_U =>
                        if (RXED = '1') then
                            RDn <= '0'; -- read ack
                            odata(15 downto 8) <= RXIN;
                            NX_READ <= '1';
                            RESTART <= '0';
                            START <= '0';
                            FINISH <= '0';
                            state <= IS_READ_DATA_L;
                        end if;
                    when IS_READ_DATA_L =>
                        if (RXED = '1') then
                            RDn <= '0'; -- read ack
                            odata(7 downto 0) <= RXIN;
                            NX_READ <= '0';
                            RESTART <= '0';
                            START <= '0';
                            FINISH <= '1';
                            state <= IS_FINISH;
                        end if;
                        --
                    when IS_WRITE_SET_ADDR =>
                        if (TXEMP = '1') then
                            NX_READ <= '0';
                            RESTART <= '0';
                            START <= '1';
                            FINISH <= '0';
                            TXOUT <= addr & '0'; -- Device Address
                            WRn <= '0';
                            state <= IS_WRITE_SET_REGNUM;
                        end if;
                    when IS_WRITE_SET_REGNUM =>
                        if (TXEMP = '1') then
                            NX_READ <= '0';
                            RESTART <= '0';
                            START <= '0';
                            FINISH <= '0';
                            TXOUT <= regnum; -- Register Number
                            WRn <= '0';
                            state <= IS_WRITE_DATA_U;
                        end if;
                    when IS_WRITE_DATA_U =>
                        NX_READ <= '0';
                        RESTART <= '0';
                        START <= '0';
                        FINISH <= '0';
                        TXOUT <= idata(15 downto 8);
                        state <= IS_WRITE_DATA_L;
                    when IS_WRITE_DATA_L =>
                        NX_READ <= '0';
                        RESTART <= '0';
                        START <= '0';
                        FINISH <= '1';
                        TXOUT <= idata(7 downto 0);
                        state <= IS_FINISH;
                    when IS_FINISH =>
                        if (req = '0') then
                            ack <= '0';
                            state <= IS_IDLE;
                        end if;
                    when others =>
                        state <= IS_IDLE;
                end case;
            end if;
        end if;
    end process;
end;