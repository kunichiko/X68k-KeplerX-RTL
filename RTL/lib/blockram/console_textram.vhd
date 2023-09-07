library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;
use ieee.numeric_std.all;

entity console_textram is
    generic (
        datawidth : integer := 8;
        addrwidth : integer := 3+7
    );
    port (
        clk : in std_logic;
        address : in std_logic_vector(addrwidth - 1 downto 0);
        din : in std_logic_vector(datawidth - 1 downto 0);
        dout : out std_logic_vector(datawidth - 1 downto 0);
        we : in std_logic
    );
end;

architecture RTL of console_textram is
    type RAM_TYPE is array (Natural range <>) of std_logic_vector(datawidth - 1 downto 0);
    subtype BRAM_TYPE is RAM_TYPE(0 to 2 ** addrwidth - 1);

    function to_slv(s : string) return RAM_TYPE is
        constant ss : string(1 to s'length) := s;
        variable answer : RAM_TYPE(1 to s'length);
        variable p : integer;
        variable c : integer;
    begin
        for i in ss'range loop
            c := character'pos(ss(i));
            answer(i) := std_logic_vector(to_unsigned(c, 8));
        end loop;
        return answer;
    end function;

    function initialize_ram
        return BRAM_TYPE is
        variable result : BRAM_TYPE;
    begin
        result(0 to 12) := to_slv("Hello, world!");
        result(128 to 187) := to_slv("128 56789012345678901234567890123456789012345678901234567890");
        result(256 to 258) := to_slv("256");
        result(384 to 386) := to_slv("386");
        result(512 to 514) := to_slv("512");
        result(640 to 642) := to_slv("640");
        result(768 to 770) := to_slv("768");
        result(896 to 898) := to_slv("896");
        --for i in 2 ** addrwidth - 1 downto 0 loop
        --    result(i) := conv_std_logic_vector(i, datawidth);
        --end loop;
        return result;
    end;

    signal BRAM : BRAM_TYPE := initialize_ram;
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