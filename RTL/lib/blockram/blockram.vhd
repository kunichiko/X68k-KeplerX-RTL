library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;

entity blockram is
    generic (
        datawidth : integer := 8;
        addrwidth : integer := 8
    );
    port (
        clk : in std_logic;
        address : in std_logic_vector(addrwidth - 1 downto 0);
        din : in std_logic_vector(datawidth - 1 downto 0);
        dout : out std_logic_vector(datawidth - 1 downto 0);
        we : in std_logic
    );
end;

architecture RTL of blockram is

    type BRAM_TYPE is array (0 to 2 ** addrwidth - 1) of std_logic_vector(datawidth - 1 downto 0);

    function initialize_ram
        return BRAM_TYPE is
        variable result : BRAM_TYPE;
    begin
        for i in 2 ** addrwidth -1 downto 0 loop
            result(i) := conv_std_logic_vector(i, datawidth);
        end loop;
        return result;
    end;

    signal BRAM : BRAM_TYPE;
    signal ad_w, ad_r : integer range 0 to 2 ** 8 - 1;

begin

    ad_w <= conv_integer(address);

    process (clk) begin
        if (clk'event and clk = '1') then
            if (we = '1') then
                BRAM(ad_w) <= din;
            end if;
            ad_r <= ad_w;
        end if;
    end process;

    dout <= BRAM(ad_r);

end;