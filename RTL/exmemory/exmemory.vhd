library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_unsigned.all;

entity exmemory is
    generic (
        HADDR_WIDTH : integer := 24;
        SDRADDR_WIDTH : integer := 13;
        BANK_WIDTH : integer := 2
    );
    port (
        sys_clk : in std_logic;
        sys_rstn : in std_logic;
        req : in std_logic;
        ack : out std_logic;

        rw : in std_logic;
        uds_n : in std_logic;
        lds_n : in std_logic;
        addr : in std_logic_vector(23 downto 0);
        idata : in std_logic_vector(15 downto 0);
        odata : out std_logic_vector(15 downto 0);

        -- SDRAM SIDE
        sdram_clk : in std_logic;
        sdram_addr : out std_logic_vector(SDRADDR_WIDTH - 1 downto 0);
        sdram_bank_addr : out std_logic_vector(BANK_WIDTH - 1 downto 0);
        sdram_idata : in std_logic_vector(15 downto 0);
        sdram_odata : out std_logic_vector(15 downto 0);
        sdram_odata_en : out std_logic;
        sdram_clock_enable : out std_logic;
        sdram_cs_n : out std_logic;
        sdram_ras_n : out std_logic;
        sdram_cas_n : out std_logic;
        sdram_we_n : out std_logic;
        sdram_data_mask_low : out std_logic;
        sdram_data_mask_high : out std_logic
    );
end exmemory;

architecture rtl of exmemory is

    signal req_d : std_logic;

    type state_t is(
    IDLE,
    WR_REQ,
    WR_ACK,
    RD_REQ,
    RD_WAIT,
    RD_ACK
    );
    signal state : state_t;

    --     module sdram_controller (
    --     /* HOST INTERFACE */
    --     wr_addr, -- [HADDR_WIDTH-1:0]
    --     wr_data, -- [15:0]
    --     wr_enable,

    --     rd_addr, -- [HADDR_WIDTH-1:0]
    --     rd_data, -- [15:0]
    --     rd_ready,
    --     rd_enable,

    --     busy, rst_n, clk,

    --     /* SDRAM SIDE */
    --     addr, -- [SDRADDR_WIDTH-1:0]
    --     bank_addr, -- [BANK_WIDTH-1:0]
    --     data, -- [15:0]
    --    clock_enable, cs_n, ras_n, cas_n, we_n,
    --     data_mask_low, data_mask_high
    -- );
    -- /* Internal Parameters */
    -- parameter ROW_WIDTH = 13;
    -- parameter COL_WIDTH = 9;
    -- parameter BANK_WIDTH = 2;

    -- parameter SDRADDR_WIDTH = ROW_WIDTH > COL_WIDTH ? ROW_WIDTH : COL_WIDTH;
    -- parameter HADDR_WIDTH = BANK_WIDTH + ROW_WIDTH + COL_WIDTH;

    -- parameter CLK_FREQUENCY = 133;  // Mhz
    -- parameter REFRESH_TIME =  32;   // ms     (how often we need to refresh)
    -- parameter REFRESH_COUNT = 8192; // cycles (how many refreshes required per refresh time)

    -- // clk / refresh =  clk / sec
    -- //                , sec / refbatch
    -- //                , ref / refbatch
    -- localparam CYCLES_BETWEEN_REFRESH = ( CLK_FREQUENCY
    --                                       * 1_000
    --                                       * REFRESH_TIME
    --                                     ) / REFRESH_COUNT;

    component sdram_controller
        generic (
            CLK_FREQUENCY : integer := 75
        );
        port (
            wr_addr : in std_logic_vector(HADDR_WIDTH - 1 downto 0);
            wr_data : in std_logic_vector(15 downto 0);
            wr_enable : in std_logic;
            wr_mask_low : in std_logic;
            wr_mask_high : in std_logic;

            rd_addr : in std_logic_vector(HADDR_WIDTH - 1 downto 0);
            rd_data : out std_logic_vector(15 downto 0);
            rd_ready : out std_logic;
            rd_enable : in std_logic;

            busy : out std_logic;
            rst_n : in std_logic;
            clk : in std_logic;

            -- SDRAM SIDE
            addr : out std_logic_vector(SDRADDR_WIDTH - 1 downto 0);
            bank_addr : out std_logic_vector(BANK_WIDTH - 1 downto 0);
            idata : in std_logic_vector(15 downto 0);
            odata : out std_logic_vector(15 downto 0);
            odata_en : out std_logic;
            clock_enable : out std_logic;
            cs_n : out std_logic;
            ras_n : out std_logic;
            cas_n : out std_logic;
            we_n : out std_logic;
            data_mask_low : out std_logic;
            data_mask_high : out std_logic
        );
    end component;

    signal wr_addr : std_logic_vector(23 downto 0);
    signal wr_data : std_logic_vector(15 downto 0);
    signal wr_enable : std_logic;
    signal wr_mask_low : std_logic;
    signal wr_mask_high : std_logic;
    signal rd_addr : std_logic_vector(23 downto 0);
    signal rd_enable : std_logic;
    signal rd_ready : std_logic;
    signal busy : std_logic;
begin

    sdram0 : sdram_controller
    generic map(75)
    port map(
        wr_addr => wr_addr,
        wr_data => wr_data,
        wr_enable => wr_enable,
        wr_mask_low => wr_mask_low,
        wr_mask_high => wr_mask_high,

        rd_addr => rd_addr,
        rd_data => odata,
        rd_ready => rd_ready,
        rd_enable => rd_enable,

        busy => busy,
        rst_n => sys_rstn,

        -- SDRAM SIDE
        clk => sdram_clk,
        addr => sdram_addr,
        bank_addr => sdram_bank_addr,
        idata => sdram_idata,
        odata => sdram_odata,
        odata_en => sdram_odata_en,
        clock_enable => sdram_clock_enable,
        cs_n => sdram_cs_n,
        ras_n => sdram_ras_n,
        cas_n => sdram_cas_n,
        we_n => sdram_we_n,
        data_mask_low => sdram_data_mask_low,
        data_mask_high => sdram_data_mask_high
    );

    -- sdram clk synchronized inputs
    process (sdram_clk, sys_rstn)
    begin
        if (sys_rstn = '0') then
            state <= IDLE;
            req_d <= '0';
            ack <= '0';
        elsif (sdram_clk' event and sdram_clk = '1') then
            req_d <= req;
            ack <= '0';
            wr_enable <= '0';
            rd_enable <= '0';

            case state is
                when IDLE =>
                    if (busy = '0') then
                        if req_d = '1' then
                            wr_addr <= "0" & addr(23 downto 1);
                            rd_addr <= "0" & addr(23 downto 1);
                            wr_data <= idata;
                            wr_mask_low <= lds_n;
                            wr_mask_high <= uds_n;
                            if rw = '0' then
                                wr_enable <= '1';
                                state <= WR_REQ;
                            else
                                rd_enable <= '1';
                                state <= RD_REQ;
                            end if;
                        end if;
                    end if;

                    -- write cycle
                when WR_REQ =>
                    -- SDRAM???BUSY?????????(??????????????????????????????)????????????
                    if (busy = '1') then
                        state <= WR_ACK;
                    else
                        wr_enable <= '1';
                    end if;
                when WR_ACK =>
                    if req_d = '1' then
                        ack <= '1';
                    else
                        ack <= '0';
                        state <= IDLE;
                    end if;

                    -- read cycle
                when RD_REQ =>
                    -- SDRAM???BUSY?????????(??????????????????????????????)????????????
                    if (busy = '1') then
                        state <= RD_WAIT;
                    else
                        rd_enable <= '1';
                    end if;
                when RD_WAIT =>
                    -- SDRAM??????????????????????????????????????????
                    if (rd_ready = '1') then
                        state <= RD_ACK;
                    end if;
                when RD_ACK =>
                    if req_d = '1' then
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
end architecture;