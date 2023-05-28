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
        crc_error : out std_logic;

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
    IS_READ_LOOP,
    IS_IDLE,
    IS_ERASE_BLOCK,
    IS_ERASE_BLOCK_CMD,
    IS_ERASE_BLOCK_VAL,
    IS_ERASE_BLOCK_WAIT,
    IS_SET_WRITE_ADDR,
    IS_SET_WRITE_ADDR_VAL,
    IS_WRITE_DATA,
    IS_WRITE_WAIT,
    IS_WRITE_FIN
    );
    signal state : state_t;

    signal counter : std_logic_vector(20 downto 0); -- 100MHz (10nsec) * 2,097,152 = 20msec

    constant SADR_REG0 : std_logic_vector(6 downto 0) := "0001000"; -- 0x08
    constant SADR_NVM : std_logic_vector(6 downto 0) := "0001010"; -- 0x0a : NVM (GreenPAK Configuration)
    constant SADR_EEPROM : std_logic_vector(6 downto 0) := "0001011"; -- 0x0b : EEPROM

    component crc16_ccitt
        port (
            crcIn : in std_logic_vector(15 downto 0);
            data : in std_logic_vector(7 downto 0);
            crcOut : out std_logic_vector(15 downto 0)
        );
    end component;

    signal crc_validate : std_logic_vector(15 downto 0);
    signal crc_current : std_logic_vector(15 downto 0);
    signal crc_input : std_logic_vector(7 downto 0);
    signal crc_next : std_logic_vector(15 downto 0);
    signal crc_we : std_logic;

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
    signal address : std_logic_vector(7 downto 0);
begin

    crc : crc16_ccitt port map(
        crcIn => crc_current,
        data => crc_input,
        crcOut => crc_next
    );

    ram_nvm : ram_8x256 port map(
        clk => clk,
        address => ram_addr,
        din => ram_data_in,
        dout => ram_data_out,
        we => ram_we
    );

    data_out <= ram_data_out;

    process (clk, rstn)
    begin
        if (rstn = '0') then
            state <= IS_WAKEUP;
            counter <= "0" & "0000" & "00000011" & "11111111";
            WRn <= '1';
            RDn <= '1';
            NX_READ <= '0';
            RESTART <= '0';
            START <= '0';
            FINISH <= '0';
            F_FINISH <= '0';
            INIT <= '0';
            --
            address <= (others => '0');
            crc_error <= '0';
            ready <= '0';
            --
            crc_validate <= (others => '0');
            crc_current <= (others => '0');
            crc_input <= (others => '0');
            crc_we <= '0';
        elsif (clk' event and clk = '1') then
            WRn <= '1';
            RDn <= '1';
            F_FINISH <= '0';
            INIT <= '0';

            --
            ram_we <= '0';

            --
            crc_we <= '0';
            if (crc_we = '1') then
                crc_current <= crc_next;
            end if;

            --
            case state is
                when IS_WAKEUP =>
                    counter <= counter - 1;
                    if (counter = 0) then
                        state <= IS_SET_READ_ADDR;
                        address <= (others => '0');
                        crc_current <= (others => '0');
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
                        TXOUT <= address; -- addr
                        WRn <= '0';
                        state <= IS_READ_START;
                    end if;
                when IS_READ_START =>
                    if (TXEMP = '1') then
                        NX_READ <= '1';
                        RESTART <= '1';
                        START <= '0';
                        FINISH <= '0';
                        TXOUT <= SADR_EEPROM & '1'; -- Device Address
                        WRn <= '0';
                        state <= IS_READ_DATA;
                    end if;
                when IS_READ_DATA =>
                    if (RXED = '1') then
                        RDn <= '0'; -- read ack
                        -- write to reg
                        ram_addr <= address;
                        ram_data_in <= RXIN;
                        ram_we <= '1';
                        address <= address + 1;
                        -- calc_crc
                        if (address < 30) then -- 先頭30バイトのみを対象
                            crc_input <= RXIN;
                            crc_we <= '1';
                        elsif (address = x"1e") then
                            crc_validate(15 downto 8) <= RXIN;
                        elsif (address = x"1f") then
                            crc_validate(7 downto 0) <= RXIN;
                        end if;
                        -- loop
                        if (address(3 downto 0) = "1111") then
                            NX_READ <= '0';
                            RESTART <= '0';
                            START <= '0';
                            FINISH <= '1';
                            state <= IS_READ_LOOP;
                        else
                            NX_READ <= '1';
                            RESTART <= '0';
                            START <= '0';
                            FINISH <= '0';
                            state <= IS_READ_DATA;
                        end if;
                    end if;
                when IS_READ_LOOP =>
                    if (address(7 downto 4) = "0000") then
                        state <= IS_IDLE;
                        if (crc_validate = crc_current) then
                            crc_error <= '0';
                        else
                            crc_error <= '1';
                        end if;
                    else
                        state <= IS_SET_READ_ADDR;
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
                    if (save_req = '1') then
                        state <= IS_ERASE_BLOCK;
                        address <= (others => '0');
                        crc_current <= (others => '0');
                    end if;
                    --
                    --
                    --
                when IS_ERASE_BLOCK =>
                    if (TXEMP = '1') then
                        NX_READ <= '0';
                        RESTART <= '0';
                        START <= '1';
                        FINISH <= '0';
                        TXOUT <= SADR_REG0 & '0'; -- Device Address
                        WRn <= '0';
                        state <= IS_ERASE_BLOCK_CMD;
                    end if;
                when IS_ERASE_BLOCK_CMD =>
                    if (TXEMP = '1') then
                        NX_READ <= '0';
                        RESTART <= '0';
                        START <= '0';
                        FINISH <= '0';
                        TXOUT <= x"e3"; -- Erase command
                        WRn <= '0';
                        state <= IS_ERASE_BLOCK_VAL;
                    end if;
                when IS_ERASE_BLOCK_VAL =>
                    if (TXEMP = '1') then
                        NX_READ <= '0';
                        RESTART <= '0';
                        START <= '0';
                        FINISH <= '1';
                        TXOUT <= x"9" & address(7 downto 4); -- Erase EEPROM block n
                        WRn <= '0';
                        state <= IS_ERASE_BLOCK_WAIT;
                        counter <= (others => '1');
                    end if;
                when IS_ERASE_BLOCK_WAIT =>
                    counter <= counter - 1;
                    if (counter = 0) then
                        state <= IS_SET_WRITE_ADDR;
                    end if;
                when IS_SET_WRITE_ADDR =>
                    if (TXEMP = '1') then
                        NX_READ <= '0';
                        RESTART <= '0';
                        START <= '1';
                        FINISH <= '0';
                        TXOUT <= SADR_EEPROM & '0'; -- Device Address
                        WRn <= '0';
                        state <= IS_SET_WRITE_ADDR_VAL;
                    end if;
                when IS_SET_WRITE_ADDR_VAL =>
                    if (TXEMP = '1') then
                        NX_READ <= '0';
                        RESTART <= '0';
                        START <= '0';
                        FINISH <= '0';
                        TXOUT <= address; -- Write address
                        WRn <= '0';
                        state <= IS_WRITE_DATA;
                    end if;
                when IS_WRITE_DATA =>
                    ram_addr <= address;
                    if (TXEMP = '1') then
                        WRn <= '0'; -- write ack
                        if (address = x"1e") then
                            TXOUT <= crc_current(15 downto 8);
                        elsif (address = x"1f") then
                            TXOUT <= crc_current(7 downto 0);
                        else
                            TXOUT <= ram_data_out; -- Write data
                            -- calc_crc
                            crc_input <= ram_data_out;
                            crc_we <= '1';
                        end if;
                        -- loop
                        if (address(3 downto 0) = "1111") then
                            NX_READ <= '0';
                            RESTART <= '0';
                            START <= '0';
                            FINISH <= '1';
                            state <= IS_WRITE_WAIT;
                            counter <= (others => '1');
                        else
                            NX_READ <= '0';
                            RESTART <= '0';
                            START <= '0';
                            FINISH <= '0';
                            state <= IS_WRITE_DATA;
                        end if;
                        --
                        address <= address + 1;
                    end if;
                when IS_WRITE_WAIT =>
                    counter <= counter - 1;
                    if (counter = 0) then
                        if (address(7 downto 4) < 2) then
                            state <= IS_ERASE_BLOCK; -- loop
                        else
                            state <= IS_WRITE_FIN;
                        end if;
                    end if;
                when IS_WRITE_FIN =>
                    save_ack <= '1';
                    if (save_req = '0') then
                        save_ack <= '0';
                        state <= IS_IDLE;
                    end if;

                when others =>
                    state <= IS_IDLE;
            end case;
        end if;
    end process;
end;