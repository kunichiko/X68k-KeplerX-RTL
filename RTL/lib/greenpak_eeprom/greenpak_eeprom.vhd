library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.std_logic_arith.all;
use IEEE.STD_LOGIC_UNSIGNED.all;

--
-- I2Cバス経由でGreenPAKのEEPROMを読み書きするコンポーネントです。
-- リセット後、I2Cバス経由で 256バイトのEEPROMを読み出して内部に保持します。
-- 読み出しが完了すると readyが '1' になります。
-- ホスト側とのインターフェースはシングルポートメモリ形式をしていて、
-- 読み書きが可能です。書き込んだメモリは save_req信号をアサートすることで
-- EEPROMに永続化できます。書き込みが終わると save_ackがアサートされます。
-- 256バイトのメモリ領域のうち、書き換えが可能なのは前半の128バイトのみと
-- なります。
entity GreenPAK_EEPROM is
    port (
        -- Host interface
        addr : in std_logic_vector(7 downto 0);
        data_in : in std_logic_vector(7 downto 0);
        data_out : out std_logic_vector(7 downto 0);
        we : in std_logic := '1';

        ready : out std_logic;
        save_req : in std_logic;
        save_ack : out std_logic;

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
end GreenPAK_EEPROM;

architecture rtl of GreenPAK_EEPROM is
    type state_t is(
    IS_WAKEUP,
    IS_SET_READ_ADDR,
    IS_SET_READ_ADDR_VAL,
    IS_READ_START,
    IS_READ_DATA,
    IS_IDLE
    );
    signal state : state_t;

    signal wakeup_counter : std_logic_vector(9 downto 0); -- 25MHz (40nsec) * 1024 = 40usec

    constant SADR_REG0 : std_logic_vector(6 downto 0) := "0001000"; -- 0x08
    constant SADR_EEPROM : std_logic_vector(6 downto 0) := "0001011"; -- 0x0b

    component ram_8x256
        port (
            clk : in std_logic;
            address : in std_logic_vector(7 downto 0);
            din : in std_logic_vector(7 downto 0);
            dout : out std_logic_vector(7 downto 0);
            we : in std_logic
        );
    end component;

    signal ram_addr : std_logic_vector(7 downto 0);
    signal ram_data_in : std_logic_vector(7 downto 0);
    signal ram_data_out : std_logic_vector(7 downto 0);
    signal ram_we : std_logic;

    --
    signal read_addr : std_logic_vector(7 downto 0);
begin

    ram0 : ram_8x256 port map(
        clk => clk,
        address => ram_addr,
        din => ram_data_in,
        dout => ram_data_out,
        we => ram_we
    );

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
            --
            read_addr <= (others => '0');
            ready <= '0';
        elsif (clk' event and clk = '1') then
            WRn <= '1';
            RDn <= '1';
            F_FINISH <= '0';
            INIT <= '0';

            --
            ram_we <= '0';

            case state is
                when IS_WAKEUP =>
                    wakeup_counter <= wakeup_counter - 1;
                    if (wakeup_counter = 0) then
                        state <= IS_SET_READ_ADDR;
                    end if;

                when IS_SET_READ_ADDR =>
                    if (TXEMP = '1') then
                        NX_READ <= '0';
                        RESTART <= '0';
                        START <= '1';
                        FINISH <= '0';
                        TXOUT <= SADR_EEPROM & '0'; -- Device Address
                        WRn <= '0';
                        state <= IS_SET_READ_ADDR_VAL;
                    end if;
                when IS_SET_READ_ADDR_VAL =>
                    if (TXEMP = '1') then
                        NX_READ <= '0';
                        RESTART <= '0';
                        START <= '0';
                        FINISH <= '0';
                        TXOUT <= x"00"; -- addr: 0x00
                        WRn <= '0';
                        state <= IS_READ_START;
                    end if;
                when IS_READ_START =>
                    if (TXEMP = '1') then
                        NX_READ <= '1';
                        RESTART <= '1';
                        START <= '0';
                        FINISH <= '0';
                        TXOUT <= SADR_EEPROM & '0'; -- Device Address
                        WRn <= '0';
                        state <= IS_READ_DATA;
                    end if;
                when IS_READ_DATA =>
                    if (RXED = '1') then
                        RDn <= '0'; -- read ack
                        -- write to reg
                        ram_addr <= read_addr;
                        ram_data_in <= RXIN;
                        ram_we <= '1';
                        read_addr <= read_addr + 1;
                        -- loop
                        if (read_addr = 255) then
                            NX_READ <= '0';
                            RESTART <= '0';
                            START <= '0';
                            FINISH <= '1';
                            state <= IS_IDLE;
                        else
                            NX_READ <= '1';
                            RESTART <= '0';
                            START <= '0';
                            FINISH <= '0';
                            state <= IS_READ_DATA;
                        end if;
                    end if;
                when IS_IDLE =>
                    state <= IS_IDLE;
                    ready <= '1';
                    --
                    ram_addr <= addr;
                    ram_data_in <= data_in;
                    if (addr(7) = '0') then
                        ram_we <= we;
                    else
                        ram_we <= '0';-- write protect for 0x80-0xff
                    end if;
                    data_out <= ram_data_out;

                when others =>
                    state <= IS_IDLE;
            end case;
        end if;
    end process;
end;