library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity axis_tlast_generator is

    generic (
        DATA_WIDTH     : positive := 32;
        TLAST_INTERVAL : positive := 16384
    );

    port (
        -- Clock / reset
        aclk    : in  std_logic;
        aresetn : in  std_logic;

        -- AXI4-Stream input
        s_axis_tdata  : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        s_axis_tvalid : in  std_logic;
        s_axis_tready : out std_logic;

        -- AXI4-Stream output
        m_axis_tdata  : out std_logic_vector(DATA_WIDTH-1 downto 0);
        m_axis_tvalid : out std_logic;
        m_axis_tready : in  std_logic;
        m_axis_tlast  : out std_logic
    );

end entity axis_tlast_generator;


architecture rtl of axis_tlast_generator is

    signal sample_count : integer range 0 to TLAST_INTERVAL-1 := 0;
    signal transfer     : std_logic;

begin

    --------------------------------------------------------------------
    -- AXI Stream pass-through
    --------------------------------------------------------------------

    m_axis_tdata  <= s_axis_tdata;
    m_axis_tvalid <= s_axis_tvalid;

    s_axis_tready <= m_axis_tready;


    --------------------------------------------------------------------
    -- A sample is transferred only when VALID and READY are both high
    --------------------------------------------------------------------

    transfer <= s_axis_tvalid and m_axis_tready;


    --------------------------------------------------------------------
    -- Assert TLAST on the final sample of each frame
    --
    -- Example:
    -- TLAST_INTERVAL = 16384
    --
    -- samples:
    -- 0 ... 16382  -> TLAST = 0
    -- 16383        -> TLAST = 1
    --------------------------------------------------------------------

    m_axis_tlast <= '1'
        when (sample_count = TLAST_INTERVAL-1 and
              s_axis_tvalid = '1')
        else '0';


    --------------------------------------------------------------------
    -- Sample counter
    --------------------------------------------------------------------

    process(aclk)
    begin

        if rising_edge(aclk) then

            if aresetn = '0' then

                sample_count <= 0;

            elsif transfer = '1' then

                if sample_count = TLAST_INTERVAL-1 then
                    sample_count <= 0;
                else
                    sample_count <= sample_count + 1;
                end if;

            end if;

        end if;

    end process;

end architecture rtl;