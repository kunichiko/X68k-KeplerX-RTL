-- This source code should be edited with CP437 encoding.
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;
use ieee.numeric_std.all;

entity console_textram is
    generic (
        datawidth : integer := 8;
        addrwidth : integer := 3 + 7
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
    type RAM_TYPE is array (natural range <>) of std_logic_vector(datawidth - 1 downto 0);
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
        -- This source code should be edited with CP437 encoding.
        result(000 to 000 + 89) := to_slv("浜様様様様様様様様様様様様様様様様様様様 Kepler X 様様様様様様様様様様様様様様様様様様様融");
        result(128 to 128 + 89) := to_slv("�                                 Welcome to MI68 2023!!                                 �");
        result(256 to 256 + 89) := to_slv("�                                                                                        �");
        result(384 to 384 + 89) := to_slv("藩様様様様様様様様用様用様用様用様用様様様様冪様様様様冤様冤様冤様冤様冤様様様様様様様様夕");
        result(512 to 512 + 89) := to_slv("敖� Mercury Unit 陳� MT�S/P�   �   �  Master崖Master  �   �   �S/P�MT 団� Mercury Unit 陳�");
        result(640 to 640 + 89) := to_slv("�F288-1胡F288-0�   � 32�DIF�AD �OPM�        崖        �OPM� AD�DIF�32 �   �F288-0胡F288-1�");
        result(768 to 768 + 89) := to_slv("�SSG FM崖SSG FM�PCM� pi� in�PCM�   �    Left崖Right   �   �PCM�in �pi �PCM�FM SSG崖FM SSG�");
        result(896 to 896 + 89) := to_slv("青陳陳珍祖陳陳珍陳珍陳珍陳珍陳珍陳珍陳陳陳陳拈陳陳陳陳祖陳祖陳祖陳祖陳祖陳祖陳陳珍祖陳陳潰");
        return result;
    end;

    signal RAM : BRAM_TYPE := initialize_ram;
    signal addr : integer range 0 to 2 ** addrwidth - 1;

begin

    addr <= conv_integer(address);

    process (clk) begin
        if (clk'event and clk = '1') then
            if (we = '1') then
                RAM(addr) <= din;
            end if;
            dout <= RAM(addr);
        end if;
    end process;

end;