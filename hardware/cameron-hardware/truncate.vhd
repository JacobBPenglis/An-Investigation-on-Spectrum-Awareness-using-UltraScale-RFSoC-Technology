library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity truncate is

    generic (
        INPUT_WIDTH  : positive := 48;
        OUTPUT_WIDTH : positive := 40
    );

    port (
        aclk    : in  std_logic;
        aresetn : in  std_logic;

        -- Input AXI Stream
        s_axis_tdata  : in  std_logic_vector(INPUT_WIDTH-1 downto 0);
        s_axis_tvalid : in  std_logic;
        s_axis_tready : out std_logic;

        -- Output AXI Stream
        m_axis_tdata  : out std_logic_vector(OUTPUT_WIDTH-1 downto 0);
        m_axis_tvalid : out std_logic;
        m_axis_tready : in  std_logic
    );

end truncate;


architecture rtl of truncate is

    constant DROP_BITS : integer :=
        INPUT_WIDTH - OUTPUT_WIDTH;

    signal out_data  : std_logic_vector(OUTPUT_WIDTH-1 downto 0)
                     := (others => '0');

    signal out_valid : std_logic := '0';

begin

    ------------------------------------------------------------
    -- Configuration checks
    ------------------------------------------------------------

    assert INPUT_WIDTH >= OUTPUT_WIDTH
        report "INPUT_WIDTH must be >= OUTPUT_WIDTH"
        severity failure;

    assert INPUT_WIDTH mod 8 = 0
        report "INPUT_WIDTH must be a multiple of 8"
        severity failure;

    assert OUTPUT_WIDTH mod 8 = 0
        report "OUTPUT_WIDTH must be a multiple of 8"
        severity failure;


    ------------------------------------------------------------
    -- AXI Stream handshake
    ------------------------------------------------------------

    s_axis_tready <= not out_valid or m_axis_tready;

    m_axis_tdata  <= out_data;
    m_axis_tvalid <= out_valid;


    ------------------------------------------------------------
    -- Truncate LSBs
    ------------------------------------------------------------

    process(aclk)
    begin

        if rising_edge(aclk) then

            if aresetn = '0' then

                out_data  <= (others => '0');
                out_valid <= '0';

            elsif out_valid = '0' or m_axis_tready = '1' then

                out_valid <= s_axis_tvalid;

                if s_axis_tvalid = '1' then

                    out_data <= s_axis_tdata(
                        INPUT_WIDTH-1
                        downto
                        DROP_BITS
                    );

                end if;

            end if;

        end if;

    end process;

end rtl;