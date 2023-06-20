library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

entity ram_8x256 is
    port (
        clk : in std_logic;
        address : in std_logic_vector(7 downto 0);
        din : in std_logic_vector(7 downto 0);
        dout : out std_logic_vector(7 downto 0);
        we : in std_logic
    );
end;

architecture RTL of ram_8x256 is

    type BRAM_TYPE is array (0 to 2 ** 8 - 1) of std_logic_vector(7 downto 0);
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