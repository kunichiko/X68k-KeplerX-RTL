library ieee, work;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

package X68KeplerX_pkg is
    constant PCM_BIT_WIDTH : integer := 16;

    subtype pcm_type is std_logic_vector(PCM_BIT_WIDTH - 1 downto 0);
	type pcmLR_type is array (0 to 1) of pcm_type;

end X68KeplerX_pkg;