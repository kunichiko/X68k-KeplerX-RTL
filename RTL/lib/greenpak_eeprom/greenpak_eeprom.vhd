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
-- 256バイトのメモリ領域のうち、実際に書き換える領域は、先頭128バイトのみです。
-- その際、最後の16バイト領域には、各ブロックのCRC値が格納されます。
-- 具体的には、
-- 0x70,0x71 : 0x00-0x0fのCRC値
-- 0x72,0x73 : 0x10-0x1fのCRC値
-- 0x7c,0x7d : 0x60-0x6fのCRC値
-- 0x7e,0x7f : 0x70-0x7dのCRC値 (最後の2バイトは自分自身なので含まない)
-- また、EEPROMの総書き換え回数が以下のアドレスに16ビットで格納されます。
-- 0x6e,0x6f : 総書き換え回数
-- この値は、EEPROMへの書き込みを行うと自動的にインクリメントされます。
-- (最大32767)
entity GreenPAK_EEPROM is
    port (
        -- Host interface
        addr : in std_logic_vector(7 downto 0);
        data_in : in std_logic_vector(7 downto 0);
        data_out : out std_logic_vector(7 downto 0);
        we : in std_logic := '1';

        ready : out std_logic;
        crc_error : out std_logic;

        write_count : out std_logic_vector(15 downto 0);

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
    constant num_blocks_16 : integer := 8; -- 16バイト単位でのブロック数(128バイトの場合は8)
    constant counter_addr : integer := 16#6e#; -- 書き込み回数をカウントするアドレス(2バイト、16bit)

    type state_t is(
    IS_WAKEUP,
    IS_READ_SETUP,
    IS_READ_SET_ADDR,
    IS_READ_SET_ADDR_VAL,
    IS_READ_START,
    IS_READ_DATA,
    IS_READ_CHECK_CRC_AU,
    IS_READ_CHECK_CRC_WU,
    IS_READ_CHECK_CRC_AL,
    IS_READ_CHECK_CRC_WL,
    IS_READ_CHECK_CRC_FIN,
    IS_READ_LOOP,
    IS_IDLE,
    IS_UPDATE_COUNT_U,
    IS_UPDATE_COUNT_L,
    IS_ERASE_BLOCK,
    IS_ERASE_BLOCK_CMD,
    IS_ERASE_BLOCK_VAL,
    IS_ERASE_BLOCK_WAIT,
    IS_SET_WRITE_ADDR,
    IS_SET_WRITE_ADDR_VAL,
    IS_WRITE_DATA,
    IS_WRITE_WAIT,
    IS_SET_CRC_U,
    IS_SET_CRC_L,
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
    signal i_write_count : std_logic_vector(15 downto 0);

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
    write_count <= i_write_count;

    process (clk, rstn)
    begin
        if (rstn = '0') then
            state <= IS_WAKEUP;
            counter <= "0" & "0000" & "00000000" & "11111111";
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
            --
            i_write_count <= (others => '0');
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
                        state <= IS_READ_SETUP;
                    end if;

                when IS_READ_SETUP =>
                    address <= x"70"; -- CRCのチェックをしたいので先に0x70から読み出す
                    crc_error <= '0'; -- 再チェックするので一旦フラグをクリア
                    state <= IS_READ_SET_ADDR;

                when IS_READ_SET_ADDR =>
                    if (TXEMP = '1') then
                        NX_READ <= '0';
                        RESTART <= '0';
                        START <= '1';
                        FINISH <= '0';
                        TXOUT <= SADR_EEPROM & '0'; -- Device Address
                        WRn <= '0';
                        state <= IS_READ_SET_ADDR_VAL;
                        crc_current <= (others => '0'); -- CRCはブロック単位で計算するので初期化
                    end if;
                when IS_READ_SET_ADDR_VAL =>
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
                        -- calc_crc
                        if ((address /= x"7e") and (address /= x"7f")) then -- この2バイトだけ除外
                            crc_input <= RXIN;
                            crc_we <= '1';
                        end if;
                        -- write count
                        if (address = counter_addr + 0) then
                            i_write_count(15 downto 8) <= RXIN;
                        elsif (address = counter_addr + 1) then
                            i_write_count(7 downto 0) <= RXIN;
                        end if;
                        -- loop
                        if (address(3 downto 0) = "1111") then
                            NX_READ <= '0';
                            RESTART <= '0';
                            START <= '0';
                            FINISH <= '1';
                            if (address(7) = '0') then
                                state <= IS_READ_CHECK_CRC_AU;
                            else
                                address <= address + 1;
                                state <= IS_READ_LOOP;
                            end if;
                        else
                            NX_READ <= '1';
                            RESTART <= '0';
                            START <= '0';
                            FINISH <= '0';
                            address <= address + 1;
                            state <= IS_READ_DATA;
                        end if;
                    end if;
                when IS_READ_CHECK_CRC_AU =>
                    ram_addr <= x"7" & address(6 downto 4) & "0";
                    state <= IS_READ_CHECK_CRC_WU;
                when IS_READ_CHECK_CRC_WU =>
                    state <= IS_READ_CHECK_CRC_AL;
                when IS_READ_CHECK_CRC_AL =>
                    if (ram_data_out /= crc_current(15 downto 8)) then
                        crc_error <= '1';
                    end if;
                    ram_addr <= x"7" & address(6 downto 4) & "1";
                    state <= IS_READ_CHECK_CRC_WL;
                when IS_READ_CHECK_CRC_WL =>
                    state <= IS_READ_CHECK_CRC_FIN;
                when IS_READ_CHECK_CRC_FIN =>
                    if (ram_data_out /= crc_current(7 downto 0)) then
                        crc_error <= '1';
                    end if;
                    address <= address + 1;
                    state <= IS_READ_LOOP;

                when IS_READ_LOOP =>
                    if (address = x"70") then -- 0x70から読み始めて0x70に戻ったら終了
                        state <= IS_IDLE;
                    else
                        state <= IS_READ_SET_ADDR;
                    end if;
                    --
                    -- 待機状態
                    --
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
                    if (save_req = '1') then -- EEPROMへの書き込み要求
                        address <= (others => '0');
                        if (i_write_count(15) = '0') then
                            i_write_count <= i_write_count + 1; -- 書き込み回数をインクリメント
                        end if;
                        state <= IS_UPDATE_COUNT_U;
                    end if;
                    --
                    --
                    --
                when IS_UPDATE_COUNT_U =>
                    ram_addr <= x"6e";
                    ram_data_in <= i_write_count(15 downto 8);
                    ram_we <= '1';
                    state <= IS_UPDATE_COUNT_L;
                when IS_UPDATE_COUNT_L =>
                    ram_addr <= x"6f";
                    ram_data_in <= i_write_count(7 downto 0);
                    ram_we <= '1';
                    state <= IS_ERASE_BLOCK;

                when IS_ERASE_BLOCK =>
                    if (TXEMP = '1') then
                        NX_READ <= '0';
                        RESTART <= '0';
                        START <= '1';
                        FINISH <= '0';
                        TXOUT <= SADR_REG0 & '0'; -- Device Address
                        WRn <= '0';
                        crc_current <= (others => '0'); -- CRCはブロック単位で計算するので初期化
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
                        if (address = x"7e") then
                            TXOUT <= crc_current(15 downto 8);
                        elsif (address = x"7f") then
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
                            address <= address + 1;
                            state <= IS_WRITE_DATA;
                        end if;
                    end if;
                when IS_WRITE_WAIT =>
                    counter <= counter - 1;
                    if (counter = 0) then
                        if (address = x"7f") then -- 128バイト書き終わったら終了
                            state <= IS_WRITE_FIN;
                        else
                            state <= IS_SET_CRC_U;
                        end if;
                    end if;
                when IS_SET_CRC_U =>
                    ram_addr <= x"7" & address(6 downto 4) & "0";
                    ram_data_in <= crc_current(15 downto 8);
                    ram_we <= '1';
                    state <= IS_SET_CRC_L;
                when IS_SET_CRC_L =>
                    ram_addr <= x"7" & address(6 downto 4) & "1";
                    ram_data_in <= crc_current(7 downto 0);
                    ram_we <= '1';
                    address <= address + 1;
                    state <= IS_ERASE_BLOCK;

                when IS_WRITE_FIN =>
                    save_ack <= '1';
                    if (save_req = '0') then
                        save_ack <= '0';
                        state <= IS_READ_SETUP; -- EEPROMから読み直す
                    end if;

                when others =>
                    state <= IS_IDLE;
            end case;
        end if;
    end process;
end;